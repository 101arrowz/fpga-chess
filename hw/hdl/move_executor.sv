`include "1_types.sv"

`timescale 1ns / 1ps
`default_nettype none

module move_executor
   (
   input wire clk_in,
   input wire rst_in,
   input move_t   move_in,
   input board_t   board_in,
   input wire   valid_in,
   output board_t   board_out,
   output logic  captured_out,
   output logic  valid_out
   );
   function logic[63:0] coord_to_mask(coord_t coord);
      integer i;
      for(i=0; i<64; i++) begin
         coord_to_mask[i] = (coord==i) ? 1 : 0;
      end
   endfunction
   function logic[5:0] abs_diff(logic[6:0] val1, logic[6:0] val2);
      //iVerilog giving syntax error when using signed, so have to do it the scuffed way :)
      logic[6:0] ret;
      ret = val1-val2;
      if(ret[6]) begin
         abs_diff=-ret;
      end else begin
         abs_diff=ret;
      end
   endfunction

   integer i;
   move_t   move;
   board_t   board;
   assign move = move_in;
   assign board = board_in;
   always_ff@(posedge clk_in) begin
      logic[(`NB_PIECES-1):0] captured_piece;
      logic[(`NB_PIECES-1):0] is_piece;
      logic captured;
      logic[1:0] king_captured;
      logic [63:0] move_mask;
      logic [63:0] src_mask;
      logic is_b;
      board_t ret_board;
      ret_board=board;
      ret_board.ply=board.ply+1;
      is_b = board_in.ply[0];
      
      src_mask=coord_to_mask(move.src);
      move_mask=coord_to_mask(move.dst);
      for(i=0; i<`NB_PIECES; i=i+1) begin
         logic[63:0] pieces;//doing this because of iVerilog
         pieces = board.pieces;
         is_piece[i]= (pieces[i]&src_mask)!=0;
      end
      ret_board.pieces_w = is_b ? (board.pieces_w & ~move_mask) : (board.pieces_w | move_mask);
      //
      for(i=0; i<`NB_PIECES; i=i+1) begin
         logic[63:0] pieces;//doing this because of iVerilog
         logic[63:0] pieces2;
         pieces = board.pieces;
         pieces2 = ret_board.pieces;
         captured_piece[i]= (pieces[i]&move_mask)!=0;
         pieces2[i] = pieces[i]&(~move_mask);
         ret_board.pieces=pieces2;
      end
      king_captured={move.dst==board.kings[1], move.dst==board.kings[0]};

      captured = (|captured_piece)|king_captured[0]|king_captured[1];
      ret_board.checkmate=board.checkmate|king_captured;
      //
      ret_board.ply50 = (captured || is_piece[4]) ? 0 : (board.ply50 + 1);

      if ((move.src == board.kings[0]) || (move.src == board.kings[1])) begin
         //iVerilog giving syntax error when using signed, so have to do it the scuffed way :)
         logic[3:0] dx;
         dx = move.dst.fil - move.src.fil;
         if(dx[3]) begin
            dx=-dx;
         end
         ret_board.en_passant = 0;
         if(is_b) begin
            ret_board.kings[1] = move.dst;
            ret_board.castle[1]=0;
         end else begin
            ret_board.kings[0] = move.dst;
            ret_board.castle[0]=0;
         end

         if (move.special == SPECIAL_CASTLE || (move.special == SPECIAL_UNKNOWN && (dx > 1))) begin
               coord_t rook_src;
               coord_t rook_dst;
               logic [63:0] rook_dst_mask;
               logic [63:0] rook_src_mask;
               rook_src = (move.src & 56) | ((move.dst < move.src) ? 0 : 7);
               rook_dst = (move.src & 56) | ((move.dst < move.src) ? 3 : 5);
               
               rook_src_mask=coord_to_mask(rook_src);
               rook_dst_mask=coord_to_mask(rook_dst);

               ret_board.pieces[2] = (board.pieces[2] & ~rook_src_mask) | rook_dst_mask;
               ret_board.pieces_w = is_b ? (ret_board.pieces_w & ~rook_dst_mask) : (ret_board.pieces_w | rook_dst_mask);
         end
      end

      if(is_b) begin
         ret_board.castle[1] &= ~((is_piece[2] && (move.src.rnk==7)) ? {(move.src.fil == 0), (move.src.fil == 7)}: 0);
      end else begin
         ret_board.castle[0] &= ~((is_piece[2] && (move.src.rnk==0)) ? {(move.src.fil == 0), (move.src.fil == 7)}: 0);
      end
      ret_board.en_passant = {(is_piece[4] && (abs_diff(move.dst, move.src) == 16)), move.dst.fil};
      case (move.special)
         SPECIAL_PROMOTE_KNIGHT: is_piece=4'b0001;
         SPECIAL_PROMOTE_BISHOP: is_piece=4'b0010;
         SPECIAL_PROMOTE_ROOK: is_piece=4'b0100;
         SPECIAL_PROMOTE_QUEEN: is_piece=4'b1000;
      endcase
      if (move.special == SPECIAL_EN_PASSANT || ((move.special == SPECIAL_UNKNOWN) && is_piece[4] && (move.dst.fil != move.src.fil) && !captured)) begin
         logic [63:0] en_passant_mask;
         en_passant_mask=coord_to_mask(is_b ? (move.dst + 8) : (move.dst - 8));
         for(i=0; i<`NB_PIECES; i++) begin
            logic[63:0] pieces;//doing this because of iVerilog
            logic[63:0] pieces2;
            pieces = board.pieces;
            pieces2 = ret_board.pieces;
            captured_piece[i]= (pieces[i]&en_passant_mask)!=0;
            pieces2[i] = pieces2[i]&(~en_passant_mask);
            ret_board.pieces=pieces2;
         end
         captured=captured|(|captured_piece);
      end
      for(i=0; i<`NB_PIECES; i++) begin
         logic[63:0] pieces;//doing this because of iVerilog
         pieces = ret_board.pieces;
         if(is_piece[i]) begin
            pieces[i] = pieces[i] | move_mask;
         end
         ret_board.pieces=pieces;
      end
      valid_out <= valid_in;
      board_out <= ret_board;
      captured_out <= captured;
   end

    

endmodule

`default_nettype wire