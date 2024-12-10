`include "1_types.sv"
`timescale 1ns / 1ps
`default_nettype none

module king_moves(
    input coord_t sq_in,
    output logic [63:0] mask_out
);
    logic [99:0] full_mask;

    always_comb begin
        logic [7:0] shift_amt;
        shift_amt = sq_in.rnk * 7'd10 + sq_in.fil;

        full_mask = (100'h701C07 << shift_amt);
    end

    generate
        for (genvar rnk = 0; rnk < 8; rnk = rnk + 1) begin
            assign mask_out[rnk * 8 + 7:rnk * 8] = full_mask[rnk * 10 + 18:rnk * 10 + 11];
        end
    endgenerate
endmodule

module knight_moves(
    input coord_t sq_in,
    output logic [63:0] mask_out
);
    logic [143:0] full_mask;

    always_comb begin
        logic [7:0] shift_amt;
        shift_amt = sq_in.rnk * 7'd12 + sq_in.fil;

        full_mask = (144'ha01100001100a << shift_amt);
    end

    generate
        for (genvar rnk = 0; rnk < 8; rnk = rnk + 1) begin
            assign mask_out[rnk * 8 + 7:rnk * 8] = full_mask[rnk * 12 + 33:rnk * 12 + 26];
        end
    endgenerate
endmodule

module rook_moves(
    input coord_t sq_in,
    input wire [63:0] occ_in,
    output logic [63:0] mask_out
);
    function [7:0] rev8(logic [7:0] data);
        logic [7:0] out;

        // can't use loops again
        out[0] = data[7];
        out[1] = data[6];
        out[2] = data[5];
        out[3] = data[4];
        out[4] = data[3];
        out[5] = data[2];
        out[6] = data[1];
        out[7] = data[0];

        return out;
    endfunction

    logic [63:0] gen_result;
    always_comb begin
        logic [5:0] src;
        logic [63:0] other_occ;

        logic [63:0] rnk_shift;
        logic [63:0] fil_shift;
        logic [7:0] rnk_occ;
        logic [7:0] fil_occ;

        logic [63:0] diag_mask;
        logic [63:0] antidiag_mask;

        logic [7:0] e_atk;
        logic [7:0] w_atk;
        logic [7:0] n_atk;
        logic [7:0] s_atk;

        logic [7:0] rnk_atk;
        logic [7:0] fil_atk;

        src = {sq_in.rnk, sq_in.fil};
        other_occ = occ_in & ~(64'b1 << src);

        rnk_shift = other_occ >> (src & 6'h38);
        rnk_occ = rnk_shift[7:0];

        fil_shift = other_occ >> (src & 6'h07);
        fil_occ = {fil_shift[56], fil_shift[48], fil_shift[40], fil_shift[32], fil_shift[24], fil_shift[16], fil_shift[8], fil_shift[0]};

        e_atk = rnk_occ - (8'b1 << (src & 6'h07));
        w_atk = rev8(rnk_occ) - rev8(8'b1 << (src & 6'h07));

        n_atk = fil_occ - (8'b1 << (src >> 3'h3));
        s_atk = rev8(fil_occ) - rev8(8'b1 << (src >> 3'h3));

        rnk_atk = e_atk ^ rev8(w_atk);
        fil_atk = n_atk ^ rev8(s_atk);
        
        gen_result = ({56'b0, rnk_atk} << (src & 6'h38)) | ({7'b0, fil_atk[7], 7'b0, fil_atk[6], 7'b0, fil_atk[5], 7'b0, fil_atk[4], 7'b0, fil_atk[3], 7'b0, fil_atk[2], 7'b0, fil_atk[1], 7'b0, fil_atk[0]} << (src & 6'h07));
    end

    assign mask_out = gen_result;
endmodule

module bishop_moves(
    input coord_t sq_in,
    input wire [63:0] occ_in,
    output logic [63:0] mask_out
);
    // note: diag/antidiag definitions swapped from software model (as sw model definitions were unconventional)

    function [63:0] bs64(logic [63:0] data);
        logic [63:0] out;

        // can't use loops here unfortunately per iVerilog
        out[7:0]   = data[63:56];
        out[15:8]  = data[55:48];
        out[23:16] = data[47:40];
        out[31:24] = data[39:32];
        out[39:32] = data[31:24];
        out[47:40] = data[23:16];
        out[55:48] = data[15:8];
        out[63:56] = data[7:0];

        return out;
    endfunction

    logic [63:0] gen_result;
    always_comb begin
        logic [5:0] src;
        logic [63:0] other_occ;

        logic [4:0] diag;
        logic [4:0] antidiag;
        logic [119:0] diag_im;
        logic [119:0] antidiag_im;
        logic [63:0] diag_mask;
        logic [63:0] antidiag_mask;

        logic [63:0] ne_atk;
        logic [63:0] sw_atk;
        logic [63:0] nw_atk;
        logic [63:0] se_atk;

        src = {sq_in.rnk, sq_in.fil};
        other_occ = occ_in & ~(64'b1 << src);

        diag = {1'b0, sq_in.rnk} + {1'b0, ~sq_in.fil};
        antidiag = {1'b0, sq_in.rnk} + {1'b0, sq_in.fil};

        diag_im = 120'h8040201008040201 << {diag, 3'b0};
        antidiag_im = 120'h0102040810204080 << {antidiag, 3'b0};

        diag_mask = diag_im[119:56];
        antidiag_mask = antidiag_im[119:56];

        ne_atk = (other_occ & diag_mask) - (64'b1 << src);
        sw_atk = bs64(other_occ & diag_mask) - bs64(64'b1 << src);
        nw_atk = (other_occ & antidiag_mask) - (64'b1 << src);
        se_atk = bs64(other_occ & antidiag_mask) - bs64(64'b1 << src);

        gen_result = ((ne_atk ^ bs64(sw_atk)) & diag_mask) | ((nw_atk ^ bs64(se_atk)) & antidiag_mask);
    end

    assign mask_out = gen_result;
endmodule

// TODO: widen pipeline
module move_generator(
    input wire    clk_in,
    input wire    rst_in,
    input board_t board_in,
    input wire    valid_in,
    output move_t move_out,
    output logic  valid_out,
    output logic  ready_out
);
    board_t board_reg;
    board_t board;
    logic processing;

    assign ready_out = ~processing;

    assign board = valid_in ? board_in : board_reg;

    logic [63:0] occupied;
    logic [63:0] allies;
    logic [63:0] enemies;

    logic [63:0] occupied_next;
    logic [63:0] allies_next;
    logic [63:0] enemies_next;

    logic is_black;

    function [5:0] ctz64(logic [63:0] data);
        logic [5:0] tz;
        logic [63:0] onehot;

        tz = 6'b000000;
        onehot = data & -data;

        for (integer i = 0; i < 64; i = i + 1) begin
            tz = tz | ({6{onehot[i]}} & i);
        end

        return tz;
    endfunction

    always_comb begin
        logic [63:0] ours;

        is_black = board.ply[0];
        ours = is_black ? ~board.pieces_w : board.pieces_w;

        occupied_next = 0;
        for (integer i = 0; i < `NB_PIECES; i = i + 1) begin
            // iVerilog hack
            logic [4:0][63:0] pieces;
            pieces = board.pieces;

            occupied_next = occupied_next | pieces[i];
        end
        occupied_next = occupied_next | (64'b1 << board.kings[0]) | (64'b1 << board.kings[1]);

        allies_next = occupied_next & ours;
        enemies_next = occupied_next & ~ours;
    end

    // king movegen
    coord_t king_sq;
    logic [63:0] king_all_dst;
    king_moves king_m(.sq_in(king_sq), .mask_out(king_all_dst));
    logic [63:0] king_pl_dst;
    logic [63:0] king_pl_dst_cur;
    move_t king_move;
    logic [1:0] king_castle;
    logic [1:0] king_castle_state;
    logic [1:0] king_castle_state_cur;
    logic [1:0] king_castle_state_next;
    logic king_move_valid;

    // can't use dynamic indexing...
    assign king_sq = is_black ? board.kings[1] : board.kings[0];
    assign king_castle = is_black ? board.castle[1] : board.castle[0];
    //assign king_castle_state_cur = valid_in ? 0 : king_castle_state;
    assign king_castle_state_cur = king_castle_state;

    //assign king_pl_dst_cur = valid_in ? king_all_dst & ~allies : king_pl_dst;
    assign king_pl_dst_cur = king_pl_dst;

    always_comb begin
        logic [7:0] king_rank_occ;

        king_move = 'x;
        king_castle_state_next = king_castle_state_cur;

        king_rank_occ = is_black ? occupied[63:56] : occupied[7:0];

        if (king_pl_dst_cur != 0) begin
            king_move_valid = 1;
            king_move.src = king_sq;
            king_move.dst = ctz64(king_pl_dst_cur);
            king_move.special = SPECIAL_NONE;
        end else if (king_castle_state_cur == 2'b00 && king_castle[0] && king_rank_occ[6:5] == 2'b0) begin
            king_move_valid = 1;
            king_move.src = king_sq;
            king_move.dst = (king_sq & 6'h38) | (6'h06);
            king_move.special = SPECIAL_CASTLE;
            king_castle_state_next = 2'b1;
        end else if (king_castle_state_cur < 2'b10 && king_castle[1] && king_rank_occ[3:1] == 3'b0) begin
            king_move_valid = 1;
            king_move.src = king_sq;
            king_move.dst = (king_sq & 6'h38) | (6'h02);
            king_move.special = SPECIAL_CASTLE;
            king_castle_state_next = 2'b10;
        end else begin
            king_move_valid = 0;
        end
    end

    // knight movegen
    logic [63:0] knight_avail;
    logic [63:0] knight_avail_cur;
    logic [5:0] knight_gen;
    logic [63:0] knight_all_dst;
    knight_moves knight_m(.sq_in(knight_gen), .mask_out(knight_all_dst));
    logic [63:0] knight_pl_dst;
    logic [63:0] knight_pl_dst_cur;
    move_t knight_move;
    logic knight_move_valid;
    logic knight_go_next;
    logic knight_new;

    //assign knight_avail_cur = valid_in ? board.pieces[KNIGHT] & allies : knight_avail;
    assign knight_avail_cur = knight_avail;
    assign knight_gen = ctz64(knight_avail_cur);

    //assign knight_pl_dst_cur = (valid_in | knight_new) ? knight_all_dst & ~allies : knight_pl_dst;
    assign knight_pl_dst_cur = knight_pl_dst;

    always_comb begin
        knight_move = 'x;

        if (knight_avail_cur != 0 && knight_pl_dst_cur != 0) begin
            logic [5:0] knight_dst;
            knight_dst = ctz64(knight_pl_dst_cur);

            knight_move_valid = 1;
            knight_move.src = knight_gen;
            knight_move.dst = knight_dst;
            knight_move.special = SPECIAL_NONE;
            knight_go_next = (knight_pl_dst_cur & (knight_pl_dst_cur - 64'b1)) == 0;
        end else begin
            knight_move_valid = 0;
            knight_go_next = 1;
        end
    end

    // bishop/queen movegen
    logic [63:0] bishop_avail;
    logic [63:0] bishop_avail_cur;
    logic [5:0] bishop_gen;
    logic [63:0] bishop_all_dst;
    bishop_moves bishop_m(.sq_in(bishop_gen), .occ_in(occupied), .mask_out(bishop_all_dst));
    logic [63:0] bishop_pl_dst;
    logic [63:0] bishop_pl_dst_cur;
    move_t bishop_move;
    logic bishop_move_valid;
    logic bishop_go_next;
    logic bishop_new;

    //assign bishop_avail_cur = valid_in ? (board.pieces[BISHOP] | board.pieces[QUEEN]) & allies : bishop_avail;
    assign bishop_avail_cur = bishop_avail;
    assign bishop_gen = ctz64(bishop_avail_cur);

    //assign bishop_pl_dst_cur = (valid_in | bishop_new) ? bishop_all_dst & ~allies : bishop_pl_dst;
    assign bishop_pl_dst_cur = bishop_pl_dst;

    always_comb begin
        bishop_move = 'x;

        if (bishop_avail_cur != 0 && bishop_pl_dst_cur != 0) begin
            logic [5:0] bishop_dst;
            bishop_dst = ctz64(bishop_pl_dst_cur);

            bishop_move_valid = 1;
            bishop_move.src = bishop_gen;
            bishop_move.dst = bishop_dst;
            bishop_move.special = SPECIAL_NONE;
            bishop_go_next = (bishop_pl_dst_cur & (bishop_pl_dst_cur - 64'b1)) == 0;
        end else begin
            bishop_move_valid = 0;
            bishop_go_next = 1;
        end
    end

    // rook/queen movegen
    logic [63:0] rook_avail;
    logic [63:0] rook_avail_cur;
    logic [5:0] rook_gen;
    logic [63:0] rook_all_dst;
    rook_moves rook_m(.sq_in(rook_gen), .occ_in(occupied), .mask_out(rook_all_dst));
    logic [63:0] rook_pl_dst;
    logic [63:0] rook_pl_dst_cur;
    move_t rook_move;
    logic rook_move_valid;
    logic rook_go_next;
    logic rook_new;

    //assign rook_avail_cur = valid_in ? (board.pieces[ROOK] | board.pieces[QUEEN]) & allies : rook_avail;
    assign rook_avail_cur = rook_avail;
    assign rook_gen = ctz64(rook_avail_cur);

    //assign rook_pl_dst_cur = (valid_in | rook_new) ? rook_all_dst & ~allies : rook_pl_dst;
    assign rook_pl_dst_cur = rook_pl_dst;

    always_comb begin
        rook_move = 'x;

        if (rook_avail_cur != 0 && rook_pl_dst_cur != 0) begin
            logic [5:0] rook_dst;
            rook_dst = ctz64(rook_pl_dst_cur);

            rook_move_valid = 1;
            rook_move.src = rook_gen;
            rook_move.dst = rook_dst;
            rook_move.dst = ctz64(rook_pl_dst_cur);
            rook_move.special = SPECIAL_NONE;
            rook_go_next = (rook_pl_dst_cur & (rook_pl_dst_cur - 64'b1)) == 0;
        end else begin
            rook_move_valid = 0;
            rook_go_next = 1;
        end
    end

    // pawn movegen
    logic [63:0] pawn_avail;
    logic [63:0] pawn_avail_cur;
    logic [5:0] pawn_gen;
    logic [3:0] pawn_move_state;
    logic [3:0] pawn_move_state_cur;
    logic [3:0] pawn_move_state_next;

    move_t pawn_move;
    logic pawn_move_valid;
    logic pawn_go_next;
    logic pawn_new;

    //assign pawn_avail_cur = valid_in ? board.pieces[PAWN] & allies : pawn_avail;
    assign pawn_avail_cur = pawn_avail;
    assign pawn_gen = ctz64(pawn_avail_cur);

    //assign pawn_move_state_cur = (valid_in | pawn_new) ? 0 : pawn_move_state;
    assign pawn_move_state_cur = pawn_move_state;

    function [63:0] bs64(logic [63:0] data);
        logic [63:0] out;

        // can't use loops here unfortunately per iVerilog
        out[7:0]   = data[63:56];
        out[15:8]  = data[55:48];
        out[23:16] = data[47:40];
        out[31:24] = data[39:32];
        out[39:32] = data[31:24];
        out[47:40] = data[23:16];
        out[55:48] = data[15:8];
        out[63:56] = data[7:0];

        return out;
    endfunction

    always_comb begin
        pawn_move = 'x;
        pawn_move_state_next = pawn_move_state_cur;

        if (pawn_avail_cur != 0) begin
            logic [63:0] local_occ;
            logic [63:0] local_opp;
            logic [5:0] fw_inc;
            logic is_start_rank;
            logic can_ep;
            logic is_promote_rank;

            logic has_fw;
            logic has_fw2;
            logic has_lcap;
            logic has_rcap;

            local_occ = is_black ? bs64(occupied) >> {~pawn_gen[5:3], pawn_gen[2:0]} : occupied >> pawn_gen;
            local_opp = is_black ? bs64(occupied & board.pieces_w) >> {~pawn_gen[5:3], pawn_gen[2:0]} : (occupied & ~board.pieces_w) >> pawn_gen;

            fw_inc = is_black ? 6'b111000 : 6'b001000;
            is_start_rank = pawn_gen[5:3] == (is_black ? 3'b110 : 3'b001);
            can_ep = (pawn_gen[5:3] == (is_black ? 3'b011 : 3'b100)) && board.en_passant[3];
            is_promote_rank = pawn_gen[5:3] == (is_black ? 3'b001 : 3'b110);

            has_fw = ~local_occ[8];
            has_fw2 = has_fw && ~local_occ[16] && is_start_rank;
            has_lcap = (pawn_gen[2:0] != 3'b000) && (local_opp[7] || (pawn_gen[2:0] == board.en_passant[2:0] + 3'b001 && can_ep));
            has_rcap = (pawn_gen[2:0] != 3'b111) && (local_opp[9] || (pawn_gen[2:0] == board.en_passant[2:0] - 3'b001 && can_ep));

            if (pawn_move_state_cur <= 4'b0011 && has_fw) begin
                logic [5:0] pawn_dst;
                pawn_dst = pawn_gen + fw_inc;

                pawn_move_valid = 1;
                pawn_move.src = pawn_gen;
                pawn_move.dst = pawn_dst;
                pawn_move.special = is_promote_rank ? move_special_t'(`SPECIAL_PROMOTE + pawn_move_state_cur[2:0]) : SPECIAL_NONE;
                pawn_move_state_next = is_promote_rank ? pawn_move_state_cur + 4'b1 : 4'b1101;
                pawn_go_next = ~has_fw2 & ~has_lcap & ~has_rcap & (~is_promote_rank || pawn_move_state_cur == 4'b0011);
            end else if (pawn_move_state_cur == 4'b1101 && has_fw2) begin
                logic [5:0] pawn_dst;
                pawn_dst = pawn_gen + (fw_inc << 1);

                pawn_move_valid = 1;
                pawn_move.src = pawn_gen;
                pawn_move.dst = pawn_dst;
                pawn_move.special = SPECIAL_NONE;
                pawn_move_state_next = 4'b0100;
                pawn_go_next = ~has_lcap & ~has_rcap;
            end else if (pawn_move_state_cur <= 4'b0111 && has_lcap) begin
                logic [5:0] pawn_dst;
                pawn_dst = pawn_gen + fw_inc - 1;

                pawn_move_valid = 1;
                pawn_move.src = pawn_gen;
                pawn_move.dst = pawn_dst;
                pawn_move.special = is_promote_rank ? move_special_t'(`SPECIAL_PROMOTE + pawn_move_state_cur[2:0]) : SPECIAL_NONE;
                pawn_move_state_next = is_promote_rank ? pawn_move_state_cur + 4'b1 : 4'b1000;
                pawn_go_next = ~has_rcap & (~is_promote_rank || pawn_move_state_cur == 4'b0111);
            end else if (pawn_move_state_cur <= 4'b1011 && has_rcap) begin
                logic [5:0] pawn_dst;
                pawn_dst = pawn_gen + fw_inc + 1;

                pawn_move_valid = 1;
                pawn_move.src = pawn_gen;
                pawn_move.dst = pawn_dst;
                pawn_move.special = is_promote_rank ? move_special_t'(`SPECIAL_PROMOTE + pawn_move_state_cur[2:0]) : SPECIAL_NONE;
                pawn_move_state_next = is_promote_rank ? pawn_move_state_cur + 4'b1 : 4'b1100;
                pawn_go_next = ~is_promote_rank || pawn_move_state_cur == 4'b1011;
            end else begin
                pawn_move_state_next = pawn_move_state_cur;
                pawn_move_valid = 0;
                pawn_go_next = 1;
            end
        end else begin
            pawn_move_valid = 0;
            pawn_go_next = 1;
        end
    end

    assign processing = (
        king_pl_dst_cur != 0 ||
        knight_avail_cur != 0 ||
        bishop_avail_cur != 0 ||
        rook_avail_cur != 0 ||
        pawn_avail_cur != 0
    );

    logic skip_knight;
    logic skip_bishop;
    logic skip_rook;
    logic skip_pawn;

    assign skip_knight = king_move_valid;
    assign skip_bishop = skip_knight | (~knight_new & knight_move_valid);
    assign skip_rook = skip_bishop | (~bishop_new & bishop_move_valid);
    assign skip_pawn = skip_rook | (~rook_new & rook_move_valid);

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            king_pl_dst <= 0;
            knight_avail <= 0;
            bishop_avail <= 0;
            rook_avail <= 0;
            pawn_avail <= 0;

            valid_out <= 1'b0;
        end else begin
            if (valid_in) begin
                board_reg <= board_in;

                occupied <= occupied_next;
                allies <= allies_next;
                enemies <= enemies_next;

                king_pl_dst <= king_all_dst & ~allies_next;
                knight_avail <= board.pieces[KNIGHT] & allies_next;
                bishop_avail <= (board.pieces[BISHOP] | board.pieces[QUEEN]) & allies_next;
                rook_avail <= (board.pieces[ROOK] | board.pieces[QUEEN]) & allies_next;
                pawn_avail <= board.pieces[PAWN] & allies_next;

                king_castle_state <= 0;

                knight_new <= 1;
                bishop_new <= 1;
                rook_new <= 1;
                pawn_new <= 1;

                valid_out <= 1'b0;
            end else begin
                valid_out <= 1'b0;
                knight_new <= 0;
                bishop_new <= 0;
                rook_new <= 0;
                pawn_new <= 0;

                if (king_move_valid) begin
                    move_out <= king_move;
                    valid_out <= 1'b1;
                    king_pl_dst <= king_pl_dst & (king_pl_dst - 64'b1);
                    king_castle_state <= king_castle_state_next;
                end

                if (knight_new) begin
                    knight_pl_dst <= knight_all_dst & ~allies;
                    knight_new <= 0;
                end else begin
                    if (knight_move_valid & ~skip_knight) begin
                        move_out <= knight_move;
                        valid_out <= 1'b1;

                        knight_pl_dst <= knight_pl_dst_cur & (knight_pl_dst_cur - 64'b1);
                    end

                    if (~(knight_move_valid & skip_knight) & knight_go_next) begin
                        knight_new <= 1;
                        knight_avail <= knight_avail_cur & (knight_avail_cur - 64'b1);
                    end
                end

                if (bishop_new) begin
                    bishop_pl_dst <= bishop_all_dst & ~allies;
                    bishop_new <= 0;
                end else begin
                    if (bishop_move_valid & ~skip_bishop) begin
                        move_out <= bishop_move;
                        valid_out <= 1'b1;

                        bishop_pl_dst <= bishop_pl_dst_cur & (bishop_pl_dst_cur - 64'b1);
                    end

                    if (~(bishop_move_valid & skip_bishop) & bishop_go_next) begin
                        bishop_new <= 1;
                        bishop_avail <= bishop_avail_cur & (bishop_avail_cur - 64'b1);
                    end
                end
    
                if (rook_new) begin
                    rook_pl_dst <= rook_all_dst & ~allies;
                    rook_new <= 0;
                end else begin
                    if (rook_move_valid & ~skip_rook) begin
                        move_out <= rook_move;
                        valid_out <= 1'b1;

                        rook_pl_dst <= rook_pl_dst_cur & (rook_pl_dst_cur - 64'b1);
                    end

                    if (~(rook_move_valid & skip_rook) & rook_go_next) begin
                        rook_new <= 1;
                        rook_avail <= rook_avail_cur & (rook_avail_cur - 64'b1);
                    end
                end

                if (pawn_new) begin
                    pawn_move_state <= 0;
                    pawn_new <= 0;
                end else begin
                    if (pawn_move_valid & ~skip_pawn) begin
                        move_out <= pawn_move;
                        valid_out <= 1'b1;

                        pawn_move_state <= pawn_move_state_next;
                    end

                    if (~(pawn_move_valid & skip_pawn) &  & pawn_go_next) begin
                        pawn_new <= 1;
                        pawn_avail <= pawn_avail_cur & (pawn_avail_cur - 64'b1);
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire