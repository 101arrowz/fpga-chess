`timescale 1ns / 1ps
`default_nettype none

module uart_transmit 
  #(
    parameter INPUT_CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 9600
    )
   (
    input wire 	     clk_in,
    input wire 	     rst_in,
    input wire [7:0] data_byte_in,
    input wire 	     trigger_in,
    output logic     busy_out,
    output logic     tx_wire_out
    );
    parameter PERIOD=INPUT_CLOCK_FREQ/BAUD_RATE;
   // TODO: module to transmit on UART
   logic [9:0] transmitting=1;
   logic [($clog2(PERIOD-1)-1): 0] t;
   assign tx_wire_out = transmitting[0];
   always_ff @(posedge clk_in) begin
    if(trigger_in&(~busy_out)) begin
      busy_out<=1;
      transmitting<={1'b1, data_byte_in, 1'b0};
      t<=0;
    end else if(busy_out) begin
      t<=t+1;
      if(t==(PERIOD-1)) begin
        t<=0;
        if(transmitting==1) begin
          busy_out<=0;
        end else begin
          transmitting<=transmitting>>1;
        end
      end
    end
    if(rst_in) begin
      transmitting<=1;
      busy_out<=0;
    end
   end
   
endmodule // uart_transmit

`default_nettype wire
