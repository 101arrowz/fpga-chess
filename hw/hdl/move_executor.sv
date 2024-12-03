`timescale 1ns / 1ps
`default_nettype none

module move_executor
   (
   input move_t   move_in,
   input board_t   board_in,
   input wire   valid_in,
   output board_t   board_out,
   output logic  valid_out
   );
   assign valid_out = valid_in;
   assign board_out = board_in;//Placeholder

endmodule

`default_nettype wire