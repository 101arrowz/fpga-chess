`timescale 1ns / 1ps
`default_nettype none

module stream_sorter #(parameter MAX_LEN = 32, parameter KEY_BITS=8, parameter VALUE_BITS=15)
   (
    input wire 	       clk_in,
    input wire 	       rst_in,

    input wire[(VALUE_BITS-1):0] value_in,
    input wire[(KEY_BITS-1):0] key_in,
    input wire valid_in,
    input wire dequeue_in,

    output logic[(MAX_LEN-1):0][(VALUE_BITS-1):0] array_out,
    output logic[(MAX_LEN-1):0][(KEY_BITS-1):0] keys_out,
    output logic[($clog2(MAX_LEN)-1):0] array_len_out//Will desync if array overflows (so don't do that)
    );
    logic[(MAX_LEN-1):0][(VALUE_BITS-1):0] array_out_reg=0; 
    logic[(MAX_LEN-1):0][(KEY_BITS-1):0] keys_out_reg=0; 
    logic[($clog2(MAX_LEN + 1)-1):0] array_len_out_reg=0;
    logic[MAX_LEN:0] carry; 

    assign array_out = array_out_reg;
    assign keys_out = keys_out_reg;
    assign array_len_out=array_len_out_reg;
    always_comb begin
        carry[MAX_LEN]=1;
        for(integer i=0; i < MAX_LEN; i++) begin
            carry[i]=keys_out_reg[i]<=key_in;
        end
    end
    always_ff @(posedge clk_in) begin
        if(rst_in) begin
            for(integer i=0; i < MAX_LEN; i++) begin
                array_out_reg[i]<=0;
                keys_out_reg[i]<=0;
            end
            array_len_out_reg<=0;
        end else begin
            if(valid_in) begin
                for(integer i=1; i < MAX_LEN; i++) begin
                    if(carry[i-1]) begin
                        array_out_reg[i]<=array_out_reg[i-1];
                        keys_out_reg[i]<=keys_out_reg[i-1];
                    end else if (carry[i]) begin
                        array_out_reg[i]<=value_in;
                        keys_out_reg[i]<=key_in;
                    end
                end
                if(carry[0]) begin
                    array_out_reg[0]<=value_in;
                    keys_out_reg[0]<=key_in;
                end
                if (array_len_out_reg < MAX_LEN) begin
                    array_len_out_reg <= array_len_out_reg+1;
                end
            end else if (dequeue_in && array_len_out_reg > 0) begin
                for (integer i=0; i < MAX_LEN - 1; i++) begin
                    array_out_reg[i] <= array_out_reg[i + 1];
                    keys_out_reg[i] <= keys_out_reg[i + 1];
                end
                keys_out_reg[MAX_LEN - 1] <= 0;
                array_len_out_reg <= array_len_out_reg - 1;
            end
        end
    end
endmodule

`default_nettype wire