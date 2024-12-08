`timescale 1ns / 1ps
`default_nettype none

module uart_receive
  #(
    parameter INPUT_CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 9600
    )
   (
    input wire 	       clk_in,
    input wire 	       rst_in,
    input wire 	       rx_wire_in,
    output logic       new_data_out,
    output logic [7:0] data_byte_out
    );
  parameter PERIOD = INPUT_CLOCK_FREQ/BAUD_RATE;
  parameter PERIOD2 = PERIOD/2;
   // TODO: module to read UART rx wire
   logic old_val = 1;
   logic running = 0;
   logic[($clog2(PERIOD)-1):0] ind = PERIOD2;
   logic[9:0] data = 10'b1111111111;
   always_ff@(posedge clk_in) begin
    old_val<=rx_wire_in;
    if(rst_in) begin
      data_byte_out<=0;
      new_data_out<=0;
      old_val<=1;
      ind<= PERIOD2;
      data<= 10'b1111111111;
    end
    if(new_data_out) begin
      new_data_out<=0;
    end
    if(~running) begin
      running<=(~rx_wire_in)&&old_val;
      ind <= PERIOD2;
      data<= 10'b1111111111;
    end else begin
      ind<=ind-1;
      if(ind==0) begin
        ind<= PERIOD;
        data<= {rx_wire_in, data[9:1]};
        if((data==10'b1111111111)&&rx_wire_in) begin
          running<=0;
        end
        if(~data[1]) begin
          running<=0;
          if(rx_wire_in) begin
            data_byte_out<= data[9:2];
            new_data_out<=1;
          end
        end
      end
    end
   end

endmodule // uart_receive

`default_nettype wire
