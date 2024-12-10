`include "1_types.sv"
`timescale 1ns / 1ps
`default_nettype none

typedef enum {EC_READY, EC_NEXT, EC_GENERATING, EC_WRITEBACK, EC_FINISH} ec_depth_state;

module engine_coordinator_sim#(parameter MAX_DEPTH = 64, parameter MAX_QUIESCE = 10)(
    input wire    clk_in,
    input wire    rst_in,
    input board_t board_in,
    input wire    board_valid_in,
    input wire    go_in,
    input wire [31:0] time_in,
    input wire [$clog2(MAX_DEPTH) - 1:0] depth_in,
    output logic  ready_out,
    output move_t bestmove_out,
    output logic  valid_out,
    output logic [31:0][7:0] info_buf,
    output logic info_valid_out
);
    localparam MAX_MOVES = 63;
    localparam NUM_SORTERS = 1;

    typedef logic [$clog2(MAX_MOVES) - 1:0] move_idx_t;

    board_t [MAX_DEPTH - 1:0] pos_stack_board;
    eval_t [MAX_DEPTH - 1:0] pos_stack_alpha;
    eval_t [MAX_DEPTH - 1:0] pos_stack_beta;
    eval_t [MAX_DEPTH - 1:0] pos_stack_score;
    move_idx_t [MAX_DEPTH - 1:0] pos_stack_move_idx;
    move_idx_t [MAX_DEPTH - 1:0] pos_stack_num_moves;

    logic [$clog2(MAX_DEPTH) - 1:0] cur_depth;
    logic [$clog2(MAX_DEPTH) - 1:0] target_depth;
    ec_depth_state cur_state;
    move_t old_best;

    move_t prefetch_move;

    move_t cur_move0;
    eval_t move0_score;
    logic [$bits(eval_t)-1:0] move0_key;
    assign move0_score = -$signed(pos_stack_score[1]);
    assign move0_key = {~move0_score[$bits(eval_t) - 1], move0_score[$bits(eval_t) - 2:0]};

    logic [(MAX_MOVES-1):0][$bits(move_t)-1:0] move0_values;
    logic [(MAX_MOVES-1):0][$bits(eval_t)-1:0] move0_keys;

    move_t cur_best;
    eval_t cur_best_eval;

    assign cur_best = move0_values[0];
    assign cur_best_eval = {~move0_keys[0][$bits(eval_t) - 1], move0_keys[0][$bits(eval_t) - 2:0]};

    stream_sorter#(.MAX_LEN(MAX_MOVES), .KEY_BITS($bits(eval_t)), .VALUE_BITS($bits(move_t))) root_best(
        .clk_in(clk_in),
        .rst_in(rst_in || (cur_state == EC_FINISH && cur_depth == 0)),
        .value_in(cur_move0),
        .key_in(move0_key),
        .valid_in(cur_depth == 1 && cur_state == EC_FINISH),
        .dequeue_in(),
        .array_out(move0_values),
        .keys_out(move0_keys),
        .array_len_out() // TODO
    );

    logic [NUM_SORTERS - 1:0][$clog2(MAX_DEPTH) - 1:0] sort_depth;
    logic [NUM_SORTERS - 1:0][$clog2(MAX_MOVES + 1) - 1:0] sort_len;
    logic [NUM_SORTERS - 1:0][$clog2(MAX_MOVES) - 1:0] sort_i;

    logic [NUM_SORTERS - 1:0][$bits(move_t)-1:0] sort_top_value;
    logic [NUM_SORTERS - 1:0][$bits(eval_t)-1:0] sort_top_key;

    logic [$bits(move_t)-1:0] sort_new_value;
    logic [$bits(eval_t)-1:0] sort_new_key;
    logic sort_valid_in;

    logic [$clog2(NUM_SORTERS + 1) - 1:0] cur_sorter;
    logic [$clog2(NUM_SORTERS) - 1:0] prev_sorter;
    logic [$clog2(NUM_SORTERS + 1) - 1:0] drain_sorter;
    logic [$clog2(NUM_SORTERS + 1) - 1:0] next_drain_sorter;
    logic [$clog2(NUM_SORTERS + 1) - 1:0] next_free_sorter;

    xilinx_true_dual_port_read_first_1_clock_ram#(
        .RAM_WIDTH($bits(move_t)),
        .RAM_DEPTH((1 << $clog2(MAX_MOVES)) * MAX_DEPTH),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE") // use 2-cycle for now since we don't need great latency
    ) move_stack(
        .clka(clk_in),
        .addra({cur_depth - 1'b1, pos_stack_move_idx[cur_depth - 1]}),
        .douta(prefetch_move),
        .wea(1'b0),

        .addrb({sort_depth[drain_sorter - 1], sort_i[drain_sorter - 1]}),
        .dinb(sort_top_value[drain_sorter - 1]),
        .web(drain_sorter != 0 && sort_len[drain_sorter - 1] > 0),

        .rsta(1'b0),
        .rstb(1'b0),
        .regcea(1'b1),
        .ena(1'b1),
        .enb(1'b1)
    );

    always_comb begin
        logic found_drain;
        logic found_free;

        found_drain = 0;
        found_free = 0;

        next_drain_sorter = 0;
        next_free_sorter = 0;

        for (integer i = 0; i < NUM_SORTERS; i++) begin
            if (!found_free && sort_len[i] == 0) begin
                found_free = 1;
                next_free_sorter = i + 1;
            end

            if (!found_drain && sort_len[i] != 0 && i + 1 != cur_sorter && i + 1 != drain_sorter) begin
                found_drain = 1;
                next_drain_sorter = i + 1;
            end
        end
    end

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            drain_sorter <= 0;
        end else begin
            if (drain_sorter == 0 || sort_len[drain_sorter - 1] <= 1) begin
                drain_sorter <= next_drain_sorter;
            end
        end
    end

    generate
        for (genvar i = 0; i < NUM_SORTERS; i++) begin
            logic [(MAX_MOVES-1):0][$bits(move_t)-1:0] sort_values;
            logic [(MAX_MOVES-1):0][$bits(eval_t)-1:0] sort_keys;

            assign sort_top_value[i] = sort_values[0];
            assign sort_top_key[i] = sort_keys[0];

            stream_sorter#(.MAX_LEN(MAX_MOVES), .KEY_BITS($bits(eval_t)), .VALUE_BITS($bits(move_t))) sst(
                .clk_in(clk_in),
                .rst_in(rst_in),
                .value_in(sort_new_value),
                .key_in(sort_new_key),
                .valid_in(sort_valid_in && cur_sorter == i + 1),
                .dequeue_in(drain_sorter == i + 1),
                .array_out(sort_values),
                .keys_out(sort_keys),
                .array_len_out(sort_len[i])
            );

            always_ff @(posedge clk_in) begin
                if (rst_in || cur_sorter == i + 1) begin
                    sort_i[i] <= 0;
                end else begin
                    if (drain_sorter == i + 1 && sort_len[i] != 0) begin
                        sort_i[i] <= sort_i[i] + 1;
                    end
                end
            end
        end
    endgenerate

    board_t cur_board;
    logic cur_check;
    assign cur_board = pos_stack_board[cur_depth];

    logic [5:0] cur_king;
    assign cur_king = cur_board.ply[0] ? cur_board.kings[1] : cur_board.kings[0];

    check_finder cf(
        .board_in(cur_board),
        .king_pos_in(cur_king),
        .is_black_in(cur_board.ply[0]),
        .is_check_out(cur_check)
    );

    logic movegen_ready;
    logic start_movegen;

    move_t movegen_pipe[2];
    logic movegen_valid_pipe[2];
    board_t movegen_board;

    localparam MOVEGEN_BOARD_SYNC = 1;
    synchronizer#(.COUNT(MOVEGEN_BOARD_SYNC), .WIDTH($bits(board_t))) mv_gen_board_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(cur_board),
        .data_out(movegen_board)
    ); 

    move_generator movegen(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .board_in(movegen_board),
        .valid_in(start_movegen),
        .move_out(movegen_pipe[1]),
        .valid_out(movegen_valid_pipe[1]),
        .ready_out(movegen_ready)
    );

    logic mvp;
    assign mvp = movegen_valid_pipe[1];

    localparam MOVEGEN_SYNC = 1;
    synchronizer#(.COUNT(MOVEGEN_SYNC), .WIDTH($bits(move_t))) mv_gen_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(movegen_pipe[1]),
        .data_out(movegen_pipe[0])
    );

    synchronizer#(.COUNT(MOVEGEN_SYNC), .WIDTH(1)) mv_gen_valid_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(movegen_valid_pipe[1]),
        .data_out(movegen_valid_pipe[0])
    );

    move_t [1:0] exec_move_pipe;
    board_t [1:0] exec_board_pipe;
    logic [1:0] exec_capture_pipe;
    logic [1:0] exec_valid_pipe;

    synchronizer#(.COUNT(1), .WIDTH($bits(move_t))) me_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(movegen_pipe[0]),
        .data_out(exec_move_pipe[1])
    );

    move_executor moveexec(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .move_in(movegen_pipe[0]),
        .board_in(cur_board),
        .valid_in(movegen_valid_pipe[0]),
        .board_out(exec_board_pipe[1]),
        .captured_out(exec_capture_pipe[1]),
        .valid_out(exec_valid_pipe[1])
    );

    logic evp;
    assign evp = exec_valid_pipe[1];

    localparam MOVE_EXEC_SYNC = 1;
    synchronizer#(.COUNT(MOVE_EXEC_SYNC), .WIDTH($bits(board_t))) mex_board_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(exec_board_pipe[1]),
        .data_out(exec_board_pipe[0])
    );
    synchronizer#(.COUNT(MOVE_EXEC_SYNC), .WIDTH($bits(move_t))) mex_move_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(exec_move_pipe[1]),
        .data_out(exec_move_pipe[0])
    );
    synchronizer#(.COUNT(MOVE_EXEC_SYNC), .WIDTH(1)) mex_capture_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(exec_capture_pipe[1]),
        .data_out(exec_capture_pipe[0])
    );
    synchronizer#(.COUNT(MOVE_EXEC_SYNC), .WIDTH(1)) mex_valid_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(exec_valid_pipe[1]),
        .data_out(exec_valid_pipe[0])
    );

    logic do_eval_move;
    assign do_eval_move = exec_valid_pipe[0] && (cur_depth < target_depth || cur_check || exec_capture_pipe[0]);

    move_t eval_move;
    eval_t eval_result;
    logic eval_valid;

    logic ecp;
    move_t emp;
    assign ecp = exec_capture_pipe[0];
    assign emp = exec_move_pipe[0];

    move_evaluator moveeval(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .last_move_in(exec_move_pipe[0]),
        .no_validate(cur_state != EC_GENERATING),
        .board_in(cur_state == EC_GENERATING ? exec_board_pipe[0] : cur_board),
        .valid_in(do_eval_move),
        .move_out(eval_move),
        .eval_out(eval_result),
        .valid_out(eval_valid)
    );

    logic pos_eval_ready;
    eval_t stand_pat;
    ec_depth_state old_state;
    synchronizer#(.COUNT(2), .WIDTH($bits(ec_depth_state))) pos_eval_ec_state_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(cur_state),
        .data_out(old_state)
    );
    assign pos_eval_ready = old_state == EC_NEXT && cur_state == EC_NEXT;
    // because eval_result automatically flips the evaluation side
    assign stand_pat = -eval_result;

    localparam MOVE_EVAL_SYNC = 1;
    synchronizer#(.COUNT(MOVE_EVAL_SYNC), .WIDTH($bits(eval_t))) mev_key_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in({~eval_result[$bits(eval_t) - 1], eval_result[$bits(eval_t) - 2:0]}),
        .data_out(sort_new_key)
    );
    synchronizer#(.COUNT(MOVE_EVAL_SYNC), .WIDTH($bits(move_t))) mev_value_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(eval_move),
        .data_out(sort_new_value)
    );
    synchronizer#(.COUNT(MOVE_EVAL_SYNC), .WIDTH(1)) mev_valid_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(eval_valid && old_state == EC_GENERATING),
        .data_out(sort_valid_in)
    );

    logic [$bits(eval_t) - 1:0] top_sort_move_key;
    eval_t top_sort_move_eval;
    move_t top_sort_move;

    assign top_sort_move_key = sort_top_key[cur_sorter - 1];
    assign top_sort_move_eval = $signed({~top_sort_move_key[$bits(eval_t) - 1], top_sort_move_key[$bits(eval_t) - 2:0]});
    assign top_sort_move = sort_top_value[cur_sorter - 1];

    logic last_move_sorted;

    // movegen -> [movegen sync -> move exec -> move exec sync -> move eval -> move eval sync] -> sorter
    localparam GEN_TO_SORT_LATENCY = MOVEGEN_SYNC + 1 + MOVE_EXEC_SYNC + 2 + MOVE_EVAL_SYNC;
    synchronizer#(.COUNT(GEN_TO_SORT_LATENCY), .WIDTH(1)) gen_sort_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(movegen_ready),
        .data_out(last_move_sorted)
    );

    logic start_gen_bit;
    logic old_gen_bit;
    logic gen_propagated;
    synchronizer#(.COUNT(GEN_TO_SORT_LATENCY + 1), .WIDTH(1)) gen_propagated_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(start_gen_bit),
        .data_out(old_gen_bit)
    );
    assign gen_propagated = old_gen_bit == start_gen_bit;

    board_t next_pos;
    move_t np_move;
    logic np_valid;
    
    assign np_move = cur_state == EC_GENERATING && last_move_sorted ? top_sort_move : prefetch_move;
    assign np_valid = 1; // TODO

    move_executor next_pos_gen(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .move_in(np_move),
        .board_in(cur_state == EC_GENERATING ? cur_board : pos_stack_board[cur_depth - 1]),
        .valid_in(np_valid),
        .board_out(next_pos),
        .captured_out(),
        .valid_out()
    );

    eval_t child_eval;
    assign child_eval = -$signed(pos_stack_score[cur_depth]) - ($signed(pos_stack_score[cur_depth]) <= -16'sd32700 ? 16'sd1 : 16'sd0);

    eval_t new_alpha;
    assign new_alpha = $signed(child_eval) > $signed(pos_stack_alpha[cur_depth - 1]) ? child_eval : $signed(pos_stack_alpha[cur_depth - 1]);

    logic [$clog2((1 + 2) + 1):0] finish_latency;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            cur_depth <= 0;
            start_movegen <= 0;
            cur_state <= EC_READY;
            valid_out <= 0;
            info_valid_out <= 0;
            cur_sorter <= 0;
            start_gen_bit <= 0;
        end else if (cur_state != EC_READY && time_in == 0) begin
            bestmove_out <= old_best;
            valid_out <= 1;
            cur_state <= EC_READY;
        end else begin
            case (cur_state)
                EC_READY: begin
                    valid_out <= 0;
                    if (board_valid_in) begin
                        pos_stack_board[0] <= board_in;
                    end

                    if (go_in) begin
                        cur_depth <= 0;
                        ready_out <= 0;
                        target_depth <= 1;
                        pos_stack_alpha[0] <= -16'sd32760;
                        pos_stack_score[0] <= -16'sd32760;
                        pos_stack_beta[0] <= 16'sd32760;
                        pos_stack_move_idx[0] <= 1;
                        cur_state <= EC_NEXT;
                    end else begin
                        ready_out <= 1;
                    end
                end
                EC_NEXT: begin
                    if (cur_depth >= target_depth) begin
                        if (pos_eval_ready) begin
                            // now evaluating for us...flip sign
                            pos_stack_score[cur_depth] <= stand_pat;

                            if ($signed(stand_pat) > $signed(pos_stack_alpha[cur_depth])) begin
                                pos_stack_alpha[cur_depth] <= stand_pat;
                            end

                            if ($signed(stand_pat) > $signed(pos_stack_beta[cur_depth]) || cur_depth >= MAX_DEPTH || cur_depth >= target_depth + MAX_QUIESCE) begin
                                finish_latency <= 0;
                                cur_state <= EC_FINISH;
                            end else if (movegen_ready && next_free_sorter != 0) begin
                                // NOTE: should always be true on the first cycle but doesn't hurt to check
                                start_movegen <= 1;
                                cur_sorter <= next_free_sorter;
                                sort_depth[next_free_sorter - 1] <= cur_depth;
                                start_gen_bit <= ~start_gen_bit;
                                cur_state <= EC_GENERATING;
                            end
                        end 
                    end else if (movegen_ready && next_free_sorter != 0) begin
                        // NOTE: should always be true on the first cycle but doesn't hurt to check
                        start_movegen <= 1;
                        cur_sorter <= next_free_sorter;
                        sort_depth[next_free_sorter - 1] <= cur_depth;
                        start_gen_bit <= ~start_gen_bit;
                        cur_state <= EC_GENERATING;
                    end
                end
                EC_GENERATING: begin
                    start_movegen <= 0;
                    if (gen_propagated & last_move_sorted) begin
                        // getting next position from next_pos_gen already
                        cur_state <= EC_WRITEBACK;
                        // note: due to the assumptions we make this strategy only works with 2 or fewer sorters
                        cur_sorter <= 0; // drain can begin *after* the next cycle (2 cycles from now)
                        prev_sorter <= cur_sorter - 1;
                        if (cur_depth == 0) begin
                            cur_move0 <= top_sort_move;
                        end
                    end
                end
                EC_WRITEBACK: begin
                    finish_latency <= 0;
                    if (sort_len[prev_sorter] == 0) begin
                        // otherwise checkmate/quiescent search and default to -32760/static_eval
                        if (cur_depth < target_depth && !cur_check) begin
                            pos_stack_score[cur_depth] <= 16'sd0;
                        end
                        cur_state <= EC_FINISH;
                    end else begin
                        cur_depth <= cur_depth + 1;
                        //$display(sort_len[prev_sorter]);
                        pos_stack_num_moves[cur_depth] <= sort_len[prev_sorter];
                        pos_stack_score[cur_depth + 1] <= next_pos.ply50 >= 7'd100 ? 16'sd0 : -16'sd32760;
                        pos_stack_alpha[cur_depth + 1] <= -$signed(pos_stack_beta[cur_depth]);
                        pos_stack_beta[cur_depth + 1] <= -$signed(pos_stack_alpha[cur_depth]);
                        pos_stack_board[cur_depth + 1] <= next_pos;
                        pos_stack_move_idx[cur_depth + 1] <= 1;
                        cur_state <= next_pos.ply50 >= 7'd100 || (next_pos.ply[0] ? next_pos.checkmate[1] : next_pos.checkmate[0]) ? EC_FINISH : EC_NEXT;
                    end
                end
                EC_FINISH: begin
                    if (cur_depth == 0) begin
                        old_best <= cur_best;
                        //$display("best move:");
                        //$display(cur_best);
                        //$display("eval:");
                        //$display(cur_best_eval);
                        if (target_depth < depth_in) begin
                            // iterative deepening
                            target_depth <= target_depth + 1;
                            pos_stack_alpha[0] <= -16'sd32760;
                            pos_stack_score[0] <= -16'sd32760;
                            pos_stack_beta[0] <= 16'sd32760;
                            pos_stack_move_idx[0] <= 1;
                            cur_state <= EC_NEXT;
                        end else begin
                            bestmove_out <= cur_best;
                            valid_out <= 1;
                            cur_state <= EC_READY;
                        end
                    end else begin
                        if (cur_depth == 1) begin
                            cur_move0 <= prefetch_move;
                        end

                        pos_stack_alpha[cur_depth - 1] <= new_alpha;

                        if ($signed(child_eval) > $signed(pos_stack_score[cur_depth - 1])) begin
                            pos_stack_score[cur_depth - 1] <= child_eval;
                        end

                        if ($signed(child_eval) > $signed(pos_stack_beta[cur_depth - 1]) || pos_stack_move_idx[cur_depth - 1] >= pos_stack_num_moves[cur_depth - 1]) begin
                            finish_latency <= 2 + 1;
                            cur_depth <= cur_depth - 1;
                        end else begin
                            if (finish_latency != 0) begin
                                finish_latency <= finish_latency - 1;
                            end else begin
                                pos_stack_move_idx[cur_depth - 1] <= pos_stack_move_idx[cur_depth - 1] + 1;
                                pos_stack_board[cur_depth] <= next_pos;
                                // alpha remains the same for child because beta doesn't change in parent
                                pos_stack_beta[cur_depth] <= -$signed(new_alpha);
                                pos_stack_move_idx[cur_depth] <= 1;

                                cur_state <= EC_NEXT;
                            end
                        end
                    end
                end
            endcase
        end
    end
endmodule

`default_nettype wire