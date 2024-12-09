`include "1_types.sv"
`timescale 1ns / 1ps
`default_nettype none

typedef enum {EC_READY, EC_NEXT, EC_GENERATING, EC_WRITEBACK, EC_FINISH} ec_depth_state;

module engine_coordinator#(parameter MAX_DEPTH = 64, parameter MAX_QUIESCE = 10)(
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
    localparam MAX_MOVES = 255;
    localparam NUM_SORTERS = 2;

    typedef struct packed {
        board_t board;
        logic signed [15:0] alpha;
        logic signed [15:0] beta;
        logic signed [15:0] score;
        logic [$clog2(MAX_MOVES) - 1:0] move_idx;
        logic [$clog2(MAX_MOVES) - 1:0] num_moves;
    } position_stack_entry_t;


    logic [$clog2(MAX_DEPTH) - 1:0] cur_depth;
    logic [$clog2(MAX_DEPTH) - 1:0] target_depth;
    ec_depth_state cur_state;
    move_t cur_best;

    position_stack_entry_t [MAX_DEPTH - 1:0] pos_stack;
    move_t prefetch_move;

    move_t cur_move0;
    eval_t move0_score;
    assign move0_score = -pos_stack[1].score;

    logic [(MAX_MOVES-1):0][$bits(move_t)-1:0] move0_values;
    logic [(MAX_MOVES-1):0][$bits(eval_t)-1:0] move0_keys;

    stream_sorter#(.MAX_LEN(MAX_MOVES), .KEY_BITS($bits(eval_t)), .VALUE_BITS($bits(move_t))) root_best(
        .clk_in(clk_in),
        .rst_in(rst_in || (cur_state == EC_FINISH && cur_depth == 0)),
        .value_in(cur_move0),
        .key_in(move0_score),
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
    logic [NUM_SORTERS - 1:0][$bits(move_t)-1:0] sort_top_key;

    logic [$bits(move_t)-1:0] sort_new_value;
    logic [$bits(eval_t)-1:0] sort_new_key;
    logic sort_valid_in;

    logic [$clog2(NUM_SORTERS + 1) - 1:0] cur_sorter;
    logic [$clog2(NUM_SORTERS + 1) - 1:0] drain_sorter;
    logic [$clog2(NUM_SORTERS + 1) - 1:0] next_drain_sorter;
    logic [$clog2(NUM_SORTERS + 1) - 1:0] next_free_sorter;

    xilinx_true_dual_port_read_first_1_clock_ram#(
        .RAM_WIDTH($bits(move_t)),
        .RAM_DEPTH((1 << $clog2(MAX_MOVES)) * MAX_DEPTH),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE") // use 2-cycle for now since we don't need great latency
    ) move_stack(
        .clka(clk_in),
        .addra({target_depth - 1'b1, pos_stack[cur_depth - 1].move_idx}),
        .douta(prefetch_move),
        .wea(1'b0),

        .addrb({sort_depth[drain_sorter - 1] - 1'b1, sort_i[drain_sorter - 1]}),
        .dinb(sort_top_value[drain_sorter - 1]),
        .web(drain_sorter != 0 && sort_len[drain_sorter - 1] > 0),

        .rsta(1'b0),
        .rstb(1'b0),
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
    assign cur_board = pos_stack[cur_depth].board;

    check_finder cf(
        .board_in(cur_board),
        .king_pos_in(cur_board.kings[cur_board.ply[0]]),
        .is_black_in(cur_board.ply[0]),
        .is_check_out(cur_check)
    );

    logic movegen_ready;
    logic start_movegen;

    move_t movegen_pipe[2];
    logic movegen_valid_pipe[2];

    move_generator movegen(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .board_in(cur_board),
        .valid_in(start_movegen),
        .move_out(movegen_pipe[1]),
        .valid_out(movegen_valid_pipe[1]),
        .ready_out(movegen_ready)
    );

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

    move_t exec_move;
    board_t exec_board;
    logic exec_capture;
    logic exec_valid;

    synchronizer#(.COUNT(1), .WIDTH($bits(move_t))) me_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(movegen_pipe[0]),
        .data_out(exec_move)
    );

    move_executor moveexec(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .move_in(movegen_pipe[0]),
        .board_in(cur_board),
        .valid_in(movegen_valid_pipe[0]),
        .board_out(exec_board),
        .captured_out(exec_capture),
        .valid_out(exec_valid)
    );

    logic do_eval_move;
    assign do_eval_move = exec_valid && (cur_depth < target_depth || cur_check || exec_capture);

    move_t eval_move;
    eval_t eval_result;
    logic eval_valid;

    move_evaluator moveeval(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .last_move_in(exec_move),
        .no_validate(1'b0),
        .board_in(exec_board),
        .valid_in(do_eval_move),
        .move_out(eval_move),
        .eval_out(eval_result),
        .valid_out(eval_valid)
    );

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
        .data_in(eval_valid),
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
    localparam GEN_TO_SORT_LATENCY = MOVEGEN_SYNC + 1 + 0 + 1 + MOVE_EVAL_SYNC;
    synchronizer#(.COUNT(GEN_TO_SORT_LATENCY), .WIDTH(1)) gen_sort_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(movegen_ready),
        .data_out(last_move_sorted)
    );

    board_t next_pos;
    move_t np_move;
    logic np_valid;
    
    assign np_move = cur_state == EC_GENERATING && last_move_sorted ? top_sort_move : prefetch_move;
    assign np_valid = 1; // TODO

    move_executor next_pos_gen(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .move_in(movegen_pipe[0]),
        .board_in(cur_board),
        .valid_in(np_valid),
        .board_out(next_pos),
        .captured_out(),
        .valid_out()
    );

    eval_t stand_pat;
    move_evaluator pos_eval(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .last_move_in(15'b0),
        .no_validate(1'b1),
        .board_in(cur_board),
        .valid_in(cur_depth >= target_depth), // TODO
        .move_out(),
        .eval_out(stand_pat),
        .valid_out() // TODO
    );

    logic old_depth_parity;
    logic pos_eval_ready;
    synchronizer#(.COUNT(1), .WIDTH(1)) pos_eval_ready_sync(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .data_in(cur_depth[0]),
        .data_out(old_depth_parity)
    );
    assign pos_eval_ready = old_depth_parity == cur_depth[0];

    eval_t child_eval;
    assign child_eval = -pos_stack[cur_depth].score - (pos_stack[cur_depth].score <= -16'sd32700 ? 16'sd1 : 16'sd0);

    eval_t new_alpha;
    assign new_alpha = child_eval > pos_stack[cur_depth - 1].alpha ? child_eval : pos_stack[cur_depth - 1].alpha;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            cur_depth <= 0;
            start_movegen <= 0;
            cur_state <= EC_READY;
            valid_out <= 0;
            info_valid_out <= 0;
            cur_sorter <= 0;
        end else if (cur_state != EC_READY && time_in == 0) begin
            bestmove_out <= cur_best;
            valid_out <= 1;
            cur_state <= EC_READY;
        end else begin
            case (cur_state)
                EC_READY: begin
                    valid_out <= 0;
                    if (board_valid_in) begin
                        pos_stack[0].board <= board_in;
                    end

                    if (go_in) begin
                        cur_depth <= 0;
                        ready_out <= 0;
                        target_depth <= 1;
                        pos_stack[0].alpha <= -16'sd32760;
                        pos_stack[0].score <= -16'sd32760;
                        pos_stack[0].beta <= 16'sd32760;
                        pos_stack[0].move_idx <= 1;
                        cur_state <= EC_NEXT;
                    end else begin
                        ready_out <= 1;
                    end
                end
                EC_NEXT: begin
                    if (cur_depth >= target_depth) begin
                        if (pos_eval_ready) begin
                            pos_stack[cur_depth].score <= stand_pat;

                            if (stand_pat > pos_stack[cur_depth].alpha) begin
                                pos_stack[cur_depth].alpha <= stand_pat;
                            end

                            if (stand_pat > pos_stack[cur_depth].beta) begin
                                cur_state <= EC_FINISH;
                            end

                            if (movegen_ready && next_free_sorter != 0) begin
                                // NOTE: should always be true on the first cycle but doesn't hurt to check
                                start_movegen <= 1;
                                cur_sorter <= next_free_sorter;
                                cur_state <= EC_GENERATING;
                            end
                        end 
                    end else if (movegen_ready && next_free_sorter != 0) begin
                        // NOTE: should always be true on the first cycle but doesn't hurt to check
                        start_movegen <= 1;
                        cur_sorter <= next_free_sorter;
                        cur_state <= EC_GENERATING;
                    end
                end
                EC_GENERATING: begin
                    start_movegen <= 0;
                    if (last_move_sorted) begin
                        // getting next position from next_pos_gen already
                        cur_state <= EC_WRITEBACK;
                        pos_stack[cur_depth].num_moves <= sort_len[cur_sorter - 1];
                        // note: due to the assumptions we make this strategy only works with 2 or fewer sorters
                        cur_sorter <= 0; // drain can begin *after* the next cycle (2 cycles from now)
                    end
                end
                EC_WRITEBACK: begin
                    if (pos_stack[cur_depth].num_moves == 0) begin
                        // otherwise checkmate and default to -32760
                        if (!cur_check) begin
                            pos_stack[cur_depth].score <= 0;
                        end
                        cur_state <= EC_FINISH;
                    end else begin
                        cur_depth <= cur_depth + 1;
                        if (cur_depth == 0) begin
                            cur_move0 <= top_sort_move;
                        end
                        
                        pos_stack[cur_depth + 1].score <= next_pos.ply50 >= 7'd100 ? 16'sd0 : -16'sd32760;
                        pos_stack[cur_depth + 1].alpha <= -pos_stack[cur_depth].beta;
                        pos_stack[cur_depth + 1].beta <= -pos_stack[cur_depth].alpha;
                        pos_stack[cur_depth + 1].board <= next_pos;
                        pos_stack[cur_depth + 1].move_idx <= 1;
                        cur_state <= next_pos.ply50 >= 7'd100 || next_pos.checkmate[next_pos.ply[0]] ? EC_FINISH : EC_NEXT;
                    end
                end
                EC_FINISH: begin
                    if (cur_depth == 0) begin
                        if (target_depth < depth_in) begin
                            // iterative deepening
                            target_depth <= target_depth + 1;
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

                        pos_stack[cur_depth - 1].alpha <= new_alpha;

                        if (child_eval > pos_stack[cur_depth - 1].score) begin
                            pos_stack[cur_depth - 1].score <= child_eval;
                        end

                        if (child_eval > pos_stack[cur_depth - 1].beta || pos_stack[cur_depth - 1].move_idx >= pos_stack[cur_depth - 1].num_moves) begin
                            cur_depth <= cur_depth - 1;
                        end else begin
                            pos_stack[cur_depth - 1].move_idx <= pos_stack[cur_depth - 1].move_idx + 1;
                            pos_stack[cur_depth].board <= next_pos;
                            // alpha remains the same for child because beta doesn't change in parent
                            pos_stack[cur_depth].beta <= -new_alpha;
                            pos_stack[cur_depth].move_idx <= 1;

                            cur_state <= EC_NEXT;
                        end
                    end
                end
            endcase
        end
    end
endmodule

`default_nettype wire