`default_nettype none
module seven_segment_controller #(parameter COUNT_PERIOD = 100000)
  (input wire           clk_in,
   input wire           rst_in,
   input wire [31:0]    val_in,
   output logic[6:0]    cat_out,
   output logic[7:0]    an_out
  );
 
  logic [7:0]   segment_state;
  logic [31:0]  segment_counter;
  logic [3:0]   sel_values;
  logic [6:0]   led_out;
  //TODO: wire up sel_values (-> x_in) with your input, val_in
  //Note that x_in is a 4 bit input, and val_in is 32 bits wide
  //Adjust accordingly, based on what you know re. which digits
  //are displayed when...
  logic[7:0][3:0] temp;
  assign temp = val_in;
  assign sel_values = segment_state[0] ? temp[0] : 
  segment_state[1] ? temp[1] : 
  segment_state[2] ? temp[2] : 
  segment_state[3] ? temp[3] : 
  segment_state[4] ? temp[4] : 
  segment_state[5] ? temp[5] : 
  segment_state[6] ? temp[6] : 
  temp[7];
  bto7s mbto7s (.x_in(sel_values), .s_out(led_out));
  assign cat_out = ~led_out; //<--note this inversion is needed
  assign an_out = ~segment_state; //note this inversion is needed
 
  always_ff @(posedge clk_in)begin
    if (rst_in)begin
      segment_state <= 8'b0000_0001;
      segment_counter <= 32'b0;
    end else begin
      if (segment_counter == COUNT_PERIOD) begin
        segment_counter <= 32'd0;
        segment_state <= {segment_state[6:0],segment_state[7]};
      end else begin
        segment_counter <= segment_counter +1;
      end
    end
  end
endmodule // seven_segment_controller
module bto7s(
        input wire [3:0]   x_in,
        output logic[6:0] s_out
        );


        //now make your sum:
        /* assign the seven output segments, sa through sg, using a "sum of products"
         * approach and the diagram above.
         *
         * 
         */
  logic [3:0] x;
  assign x = x_in;
  assign s_out[0] = (x==0)||(x==2)||(x==3)||(x==5)||(x==6)||(x==7)||(x==8)||(x==9)||(x==10)||(x==12)||(x==14)||(x==15);
  assign s_out[1] =(x==0)||(x==1)||(x==2)||(x==3)||(x==4)||(x==7)||(x==8)||(x==9)||(x==10)||(x==13);
  assign s_out[2] =(x==0)||(x==1)||(x==3)||(x==4)||(x==5)||(x==6)||(x==7)||(x==8)||(x==9)||(x==10)||(x==11)||(x==13);
  assign s_out[3] =(x==0)||(x==2)||(x==3)||(x==5)||(x==6)||(x==8)||(x==9)||(x==11)||(x==12)||(x==13)||(x==14);
  assign s_out[4] =(x==0)||(x==2)||(x==6)||(x==8)||(x==10)||(x==11)||(x==12)||(x==13)||(x==14)||(x==15);
  assign s_out[5] =(x==0)||(x==4)||(x==5)||(x==6)||(x==8)||(x==9)||(x==10)||(x==11)||(x==12)||(x==14)||(x==15);
  assign s_out[6] =(x==2)||(x==3)||(x==4)||(x==5)||(x==6)||(x==8)||(x==9)||(x==10)||(x==11)||(x==13)||(x==14)||(x==15);
endmodule
`default_nettype wire