`include "1_types.sv"
`timescale 1ns / 1ps
`default_nettype none

module pst(
    input wire [5:0] sq_in,
    input wire [2:0] ptype_in,
    output logic signed [15:0] eval_out
);
    logic [7:0][15:0] piece_weights;
    logic [7:0][63:0][7:0] square_deltas;
    logic [511:0][7:0] square_deltas_raw;

    logic [7:0] sqdelta;
    logic [15:0] sqdelta_sum;

    assign piece_weights[0] = 0;
    assign piece_weights[KNIGHT + 1] = 16'sd300;
    assign piece_weights[BISHOP + 1] = 16'sd340;
    assign piece_weights[ROOK + 1] = 16'sd550;
    assign piece_weights[PAWN + 1] = 16'sd1000;
    assign piece_weights[KING + 1] = 16'sd15000;
    assign piece_weights[KING + 2] = 16'sd15000;

    assign square_deltas[0] = 512'b0;

    assign square_deltas[KNIGHT + 1] = {
        -8'sd50, -8'sd40, -8'sd30, -8'sd30, -8'sd30, -8'sd30, -8'sd40, -8'sd50,
        -8'sd40, -8'sd20,  8'sd00,  8'sd05,  8'sd05,  8'sd00, -8'sd20, -8'sd40,
        -8'sd30,  8'sd05,  8'sd10,  8'sd15,  8'sd15,  8'sd10,  8'sd05, -8'sd30,
        -8'sd30,  8'sd00,  8'sd15,  8'sd20,  8'sd20,  8'sd15,  8'sd00, -8'sd30,
        -8'sd30,  8'sd05,  8'sd15,  8'sd20,  8'sd20,  8'sd15,  8'sd05, -8'sd30,
        -8'sd30,  8'sd00,  8'sd10,  8'sd15,  8'sd15,  8'sd10,  8'sd00, -8'sd30,
        -8'sd40, -8'sd20,  8'sd00,  8'sd00,  8'sd00,  8'sd00, -8'sd20, -8'sd40,
        -8'sd50, -8'sd40, -8'sd30, -8'sd30, -8'sd30, -8'sd30, -8'sd40, -8'sd50
    };

    assign square_deltas[BISHOP + 1] = {
        -8'sd20, -8'sd10, -8'sd10, -8'sd10, -8'sd10, -8'sd10, -8'sd10, -8'sd20,
        -8'sd10,  8'sd05,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd05, -8'sd10,
        -8'sd10,  8'sd10,  8'sd10,  8'sd10,  8'sd10,  8'sd10,  8'sd10, -8'sd10,
        -8'sd10,  8'sd00,  8'sd10,  8'sd10,  8'sd10,  8'sd10,  8'sd00, -8'sd10,
        -8'sd10,  8'sd05,  8'sd05,  8'sd10,  8'sd10,  8'sd05,  8'sd05, -8'sd10,
        -8'sd10,  8'sd00,  8'sd05,  8'sd10,  8'sd10,  8'sd05,  8'sd00, -8'sd10,
        -8'sd10,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00, -8'sd10,
        -8'sd20, -8'sd10, -8'sd10, -8'sd10, -8'sd10, -8'sd10, -8'sd10, -8'sd20
    };

    assign square_deltas[ROOK + 1] = {
         8'sd00,  8'sd00,  8'sd00,  8'sd05,  8'sd05,  8'sd00,  8'sd00,  8'sd00,
        -8'sd05,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00, -8'sd05,
        -8'sd05,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00, -8'sd05,
        -8'sd05,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00, -8'sd05,
        -8'sd05,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00, -8'sd05,
        -8'sd05,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00, -8'sd05,
         8'sd05,  8'sd10,  8'sd10,  8'sd10,  8'sd10,  8'sd10,  8'sd10,  8'sd05,
         8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00
    };

    assign square_deltas[QUEEN + 1] = {
        -8'sd20, -8'sd10, -8'sd10, -8'sd05, -8'sd05, -8'sd10, -8'sd10, -8'sd20,
        -8'sd10,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd05,  8'sd00, -8'sd10,
        -8'sd10,  8'sd00,  8'sd05,  8'sd05,  8'sd05,  8'sd05,  8'sd05, -8'sd10,
        -8'sd05,  8'sd00,  8'sd05,  8'sd05,  8'sd05,  8'sd05,  8'sd00,  8'sd00,
        -8'sd05,  8'sd00,  8'sd05,  8'sd05,  8'sd05,  8'sd05,  8'sd00, -8'sd05,
        -8'sd10,  8'sd00,  8'sd05,  8'sd05,  8'sd05,  8'sd05,  8'sd00, -8'sd10,
        -8'sd10,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00, -8'sd10,
        -8'sd20, -8'sd10, -8'sd10, -8'sd05, -8'sd05, -8'sd10, -8'sd10, -8'sd20
    };

    assign square_deltas[PAWN + 1] = {
        8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,
        8'sd50,  8'sd50,  8'sd50,  8'sd50,  8'sd50,  8'sd50,  8'sd50,  8'sd50,
        8'sd10,  8'sd10,  8'sd20,  8'sd30,  8'sd30,  8'sd20,  8'sd10,  8'sd10,
        8'sd05,  8'sd05,  8'sd10,  8'sd25,  8'sd25,  8'sd10,  8'sd05,  8'sd05,
        8'sd00,  8'sd00,  8'sd00,  8'sd20,  8'sd20,  8'sd00,  8'sd00,  8'sd00,
        8'sd05, -8'sd05, -8'sd10,  8'sd00,  8'sd00, -8'sd10, -8'sd05,  8'sd05,
        8'sd05,  8'sd10,  8'sd10, -8'sd20, -8'sd20,  8'sd10,  8'sd10,  8'sd05,
        8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd00
    };

    // king (normal)
    assign square_deltas[KING + 1] = {
         8'sd20,  8'sd30,  8'sd10,  8'sd00,  8'sd00,  8'sd10,  8'sd30,  8'sd20,
         8'sd20,  8'sd20,  8'sd00,  8'sd00,  8'sd00,  8'sd00,  8'sd20,  8'sd20,
        -8'sd10, -8'sd20, -8'sd20, -8'sd20, -8'sd20, -8'sd20, -8'sd20, -8'sd10,
        -8'sd20, -8'sd30, -8'sd30, -8'sd40, -8'sd40, -8'sd30, -8'sd30, -8'sd20,
        -8'sd30, -8'sd40, -8'sd40, -8'sd50, -8'sd50, -8'sd40, -8'sd40, -8'sd30,
        -8'sd30, -8'sd40, -8'sd40, -8'sd50, -8'sd50, -8'sd40, -8'sd40, -8'sd30,
        -8'sd30, -8'sd40, -8'sd40, -8'sd50, -8'sd50, -8'sd40, -8'sd40, -8'sd30,
        -8'sd30, -8'sd40, -8'sd40, -8'sd50, -8'sd50, -8'sd40, -8'sd40, -8'sd30
    };

    // king (endgame)
    assign square_deltas[KING + 2] = {
        -8'sd50, -8'sd30, -8'sd30, -8'sd30, -8'sd30, -8'sd30, -8'sd30, -8'sd50,
        -8'sd30, -8'sd30,  8'sd00,  8'sd00,  8'sd00,  8'sd00, -8'sd30, -8'sd30,
        -8'sd30, -8'sd10,  8'sd20,  8'sd30,  8'sd30,  8'sd20, -8'sd10, -8'sd30,
        -8'sd30, -8'sd10,  8'sd30,  8'sd40,  8'sd40,  8'sd30, -8'sd10, -8'sd30,
        -8'sd30, -8'sd10,  8'sd30,  8'sd40,  8'sd40,  8'sd30, -8'sd10, -8'sd30,
        -8'sd30, -8'sd10,  8'sd20,  8'sd30,  8'sd30,  8'sd20, -8'sd10, -8'sd30,
        -8'sd30, -8'sd20, -8'sd10,  8'sd00,  8'sd00, -8'sd10, -8'sd20, -8'sd30,
        -8'sd50, -8'sd40, -8'sd30, -8'sd20, -8'sd20, -8'sd30, -8'sd40, -8'sd50
    };

    assign square_deltas_raw = square_deltas;
    assign sqdelta = square_deltas_raw[{ptype_in, sq_in}];
    // sign extension
    assign sqdelta_sum = {{8{sqdelta[7]}}, sqdelta};

    assign eval_out = $signed(piece_weights[ptype_in]) + $signed(sqdelta_sum);
endmodule

module square_evaluator#(parameter [5:0] SQ = 0)(
    input board_t board_in,
    output logic [15:0] abs_eval_out,
    output logic signed [15:0] eval_out
);
    logic [2:0] ptype;
    logic signed [15:0] ps_eval;

    pst tab(
        .sq_in(SQ),
        .ptype_in(ptype),
        .eval_out(ps_eval)
    );

    always_comb begin
        ptype = 0;
        for (integer i = 0; i < `NB_PIECES; i = i + 1) begin
            logic [319:0] pieces;
            pieces = board_in.pieces;

            // TODO: use packed values instead as this might be harder to optimize
            ptype |= {3{pieces[{i, SQ}]}} & 3'(i + 1);
        end
    end

    assign abs_eval_out = ps_eval;
    assign eval_out = board_in.pieces_w[SQ] ? ps_eval : -ps_eval;
endmodule

module check_finder(
    input board_t board_in,
    input wire [5:0] king_pos_in,
    input wire is_black_in,
    output logic is_check_out
);
    logic [63:0] occupied;
    logic [63:0] opp_mask;
    logic [5:0] opp_king;
    logic [63:0] king_mask;
    logic [63:0] knight_mask;
    logic [63:0] bishop_mask;
    logic [63:0] rook_mask;
    logic [63:0] pawn_mask;

    king_moves king_m(.sq_in(king_pos_in), .mask_out(king_mask));
    knight_moves knight_m(.sq_in(king_pos_in), .mask_out(knight_mask));
    bishop_moves bishop_m(.sq_in(king_pos_in), .occ_in(occupied), .mask_out(bishop_mask));
    rook_moves rook_m(.sq_in(king_pos_in), .occ_in(occupied), .mask_out(rook_mask));

    always_comb begin
        occupied = 0;
        for (integer i = 0; i < `NB_PIECES; i = i + 1) begin
            // iVerilog hack
            logic [4:0][63:0] pieces;
            pieces = board_in.pieces;

            occupied = occupied | pieces[i];
        end

        opp_king = is_black_in ? board_in.kings[0] : board_in.kings[1];
        // don't include occupancy of same color king itself
        occupied = occupied | (64'b1 << opp_king);

        opp_mask = is_black_in ? board_in.pieces_w : ~board_in.pieces_w;

        // TODO: make better
        pawn_mask = 0;
        if (is_black_in) begin
            if (king_pos_in[5:3] != 3'b000) begin
                pawn_mask = ((king_pos_in[2:0] != 3'b111) << (king_pos_in - 6'h07)) | ((king_pos_in[2:0] != 3'b000) << (king_pos_in - 6'h09));
            end
        end else begin
            if (king_pos_in[5:3] != 3'b111) begin
                pawn_mask = ((king_pos_in[2:0] != 3'b111) << (king_pos_in + 6'h09)) | ((king_pos_in[2:0] != 3'b000) << (king_pos_in + 6'h07));
            end
        end
    end

    assign is_check_out = (king_mask & (64'b1 << opp_king)) != 0 || ((
        (knight_mask & board_in.pieces[KNIGHT]) |
        (bishop_mask & (board_in.pieces[BISHOP] | board_in.pieces[QUEEN])) |
        (rook_mask & (board_in.pieces[ROOK] | board_in.pieces[QUEEN])) |
        (pawn_mask & board_in.pieces[PAWN])
    ) & opp_mask) != 0;
endmodule

module move_validator(
    input board_t board_in,
    input move_t  last_move_in,
    output wire legal_out
);
    logic moved_into_check;
    logic moved_out_check;
    logic moved_through_check;
    logic [5:0] cur_king;
    logic opp_checkmate;

    // ply flipped after execute: use reverse king (like using old ply)
    assign cur_king = board_in.ply[0] ? board_in.kings[0] : board_in.kings[1];
    assign opp_checkmate = board_in.ply[0] ? board_in.checkmate[1] : board_in.checkmate[0];

    check_finder is_check(
        .board_in(board_in),
        .king_pos_in(cur_king),
        .is_black_in(~board_in.ply[0]),
        .is_check_out(moved_into_check)
    );

    check_finder was_check(
        .board_in(board_in),
        .king_pos_in(last_move_in.src),
        .is_black_in(~board_in.ply[0]),
        .is_check_out(moved_out_check)
    );

    check_finder thru_check(
        .board_in(board_in),
        .king_pos_in({cur_king[5:3], last_move_in.dst[2:0] < last_move_in.src[2:0] ? 3'h3 : 3'h5}),
        .is_black_in(~board_in.ply[0]),
        .is_check_out(moved_through_check)
    );

    // always allow going into check if we "checkmate" (capture opponent king) first
    assign legal_out = opp_checkmate || (!moved_into_check && (last_move_in.special != SPECIAL_CASTLE || (!moved_out_check && !moved_through_check)));
endmodule

module move_evaluator(
    input wire    clk_in,
    input wire    rst_in,
    input move_t  last_move_in,
    input board_t board_in,
    input wire    no_validate,
    input wire    valid_in,
    output move_t move_out,
    output eval_t eval_out,
    output logic  valid_out
);
    logic [63:0][15:0] pst_eval;
    logic [63:0][15:0] pst_eval_abs;

    generate
        for (genvar i = 0; i < 64; i = i + 1) begin
            square_evaluator#(.SQ(i)) sq(
                .board_in(board_in),
                .abs_eval_out(pst_eval_abs[i]),
                .eval_out(pst_eval[i])
            );
        end
    endgenerate

    logic [1:0][15:0] sum_eval;
    logic [1:0][15:0] sum_abs_eval;
    logic [1:0][1:0][5:0] king_locs;

    always_comb begin
        logic signed [15:0] psum;
        logic [15:0] psum_abs;

        psum = 0;
        psum_abs = 0;
        for (integer i = 0; i < 64; i = i + 1) begin
            psum += $signed(pst_eval[i]);
            psum_abs += pst_eval_abs[i];
        end

        sum_eval[1] = psum;
        sum_abs_eval[1] = psum_abs;

        king_locs[1][0] = board_in.kings[0];
        king_locs[1][1] = board_in.kings[1];
    end

    logic [1:0] valid_pipe;
    move_t [1:0] move_pipe;
    logic [1:0][1:0][1:0] checkmate_pipe;
    logic [1:0] is_black_pipe;
    logic [1:0][1:0] bishop_pair_pipe;

    assign valid_pipe[1] = valid_in;
    assign move_pipe[1] = last_move_in;
    assign checkmate_pipe[1] = board_in.checkmate;
    // after executing a move, opposite color - account for that here
    assign is_black_pipe[1] = ~board_in.ply[0];

    always_comb begin
        logic [63:0] black_bishop;
        logic [63:0] white_bishop;

        black_bishop = board_in.pieces[BISHOP] & ~board_in.pieces_w;
        white_bishop = board_in.pieces[BISHOP] & board_in.pieces_w;

        bishop_pair_pipe[1] = {
            (black_bishop & 64'hCC55CC55CC55CC55) != 0 && (black_bishop & 64'h55CC55CC55CC55CC) != 0,
            (white_bishop & 64'hCC55CC55CC55CC55) != 0 && (white_bishop & 64'h55CC55CC55CC55CC) != 0
        };
    end

    logic signed [15:0] kw_eval;
    logic signed [15:0] kb_eval;
    pst kw_pst(
        .sq_in(king_locs[0][0]),
        .ptype_in(sum_abs_eval[0] <= 27000 ? 3'(KING + 2) : 3'(KING + 1)),
        .eval_out(kw_eval)
    );
    pst kb_pst(
        .sq_in(king_locs[0][1]),
        .ptype_in(sum_abs_eval[0] <= 27000 ? 3'(KING + 2) : 3'(KING + 1)),
        .eval_out(kb_eval)
    );

    logic signed [1:0] legal_pipe;
    move_validator vd(
        .board_in(board_in),
        .last_move_in(last_move_in),
        .legal_out(legal_pipe[1])
    );

    logic signed [15:0] eval_result;
    logic eval_result_valid;
    always_comb begin
        logic signed [15:0] white_eval;

        white_eval = $signed(sum_eval[0]) + (checkmate_pipe[0][0] ? 16'sd0 : kw_eval) - (checkmate_pipe[0][1] ? 16'sd0 : kb_eval);
        white_eval += bishop_pair_pipe[0][1] != bishop_pair_pipe[0][0] ? (bishop_pair_pipe[0][1] ? -16'sd80 : 16'sd80) : 16'sd0;

        eval_result = is_black_pipe[0] ? -white_eval : white_eval;
        eval_result_valid = (no_validate | legal_pipe[0]) & valid_pipe[0];
    end

    assign eval_out = eval_result;
    assign valid_out = eval_result_valid;
    assign move_out = move_pipe[0];

    always_ff @(posedge clk_in) begin
        valid_pipe[0] <= valid_pipe[1] & ~rst_in;

        sum_eval[0] <= sum_eval[1];
        sum_abs_eval[0] <= sum_abs_eval[1];

        move_pipe[0] <= move_pipe[1];
        legal_pipe[0] <= legal_pipe[1];

        checkmate_pipe[0] <= checkmate_pipe[1];
        king_locs[0] <= king_locs[1];
        is_black_pipe[0] <= is_black_pipe[1];
    end
endmodule

`default_nettype wire