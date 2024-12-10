`include "1_types.sv"
`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module top_level_test
  (
    input wire 	       clk_in,
    input wire 	       rst_in,

    input wire[7:0]   char_in,
    input wire char_in_valid,
    output logic   char_in_ready,

    output logic[7:0]   char_out,
    input wire char_out_ready,
    output logic char_out_valid
   );

    board_t board;
    logic board_valid;
    logic go;

    move_t move;
    logic move_valid;
    logic ec_ready;
    logic did_go;

    uci_handler uci
    (.clk_in(clk_in), 
    .rst_in(rst_in),
    .char_in(char_in),
    .char_in_valid(char_in_valid),
    .info_in(0),
    .info_in_valid(0),
    .best_move_in(move),
    .best_move_in_valid(move_valid),
    .char_out(char_out),
    .char_out_ready(char_out_ready),
    .char_out_valid(char_out_valid),
    .board_out(board),
    .board_out_valid(board_valid),
    .go(go)
    );

    move_generator movegen(
        .clk_in(clk_in),
        .rst_in(rst_in),
        .board_in(board),
        .valid_in(go)
        //.move_out(movegen_pipe[1]),
        //.valid_out(movegen_valid_pipe[1]),
        //.ready_out(movegen_ready)
    );
endmodule // top_level

`default_nettype wire