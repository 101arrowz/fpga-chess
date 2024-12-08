module counter(     input wire clk_in,
                    input wire rst_in,
                    input wire [31:0] period_in,
                    output logic [31:0] count_out
              );
  always_ff @(posedge clk_in) begin
    if(rst_in) begin
      count_out<=0;
    end else if(count_out>=period_in) begin
      count_out<=0;
    end else begin 
      count_out<=(count_out+1);
    end
  end
    //your code here
endmodule