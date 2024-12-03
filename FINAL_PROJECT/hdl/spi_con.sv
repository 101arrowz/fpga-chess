module spi_con
     #(parameter DATA_WIDTH = 8,
       parameter DATA_CLK_PERIOD = /*100*/10
      )
      (input wire   clk_in, //system clock (100 MHz)
       input wire   rst_in, //reset in signal
       input wire   [DATA_WIDTH-1:0] data_in, //data to send
       input wire   trigger_in, //start a transaction
       output logic [DATA_WIDTH-1:0] data_out, //data received!
       output logic data_valid_out, //high when output data is present.
 
       output logic chip_data_out, //(COPI)
       input wire   chip_data_in, //(CIPO)
       output logic chip_clk_out, //(DCLK)
       output logic chip_sel_out // (CS)
      );
  parameter DATA_CLK_PERIOD2 = /*$floor*/(DATA_CLK_PERIOD/2);
  //your code here
  logic[$clog2(DATA_WIDTH)-1:0] ind=0;
  logic[$clog2(DATA_CLK_PERIOD)-1:0] sub_clock_ind=0;
  logic[DATA_WIDTH-1:0] held_data_in=0;
  logic[DATA_WIDTH-1:0] held_data_out=0;
  logic[DATA_WIDTH-1:0] held_data_out2;
  logic running=0;
  logic cur_in;
  logic[$clog2(DATA_WIDTH)-1:0] cur_ind;
  logic[$clog2(DATA_CLK_PERIOD)-1:0] sub_clock_ind2;
  always_ff@(posedge clk_in) begin
    data_valid_out<=0;
    if(rst_in) begin
        ind<=0;
        running<=0;
        sub_clock_ind<=0;
        chip_data_out=0;
        chip_clk_out=0;
        chip_sel_out=1;
        held_data_in<=0;
        held_data_out<=0;
        held_data_out2=0;
        sub_clock_ind2=0;
    end else begin
        if((!running)&trigger_in) begin
            running<=1;
            sub_clock_ind<=0;
            cur_in=data_in[0];
            //held_data_in<=data_in;
            for (int i = 0; i < DATA_WIDTH; i=i+1) begin
                held_data_in[i] <= data_in[DATA_WIDTH-i-1];
            end
            sub_clock_ind2=0;
        end else if(running) begin
            if(sub_clock_ind==(DATA_CLK_PERIOD)) begin
                held_data_out <= {held_data_out[DATA_WIDTH-2:0],chip_data_in};
                cur_in=held_data_in[1];
                held_data_in<=(held_data_in>>1);
                sub_clock_ind<=0;
                ind<=ind+1;
                sub_clock_ind2=0;
            end else begin
                cur_in=held_data_in[0];
                sub_clock_ind2=sub_clock_ind;
                sub_clock_ind<=sub_clock_ind+1;
            end
        end
        if(running|trigger_in) begin
            chip_data_out=cur_in;
            chip_clk_out=(sub_clock_ind2>=DATA_CLK_PERIOD2);
            if((ind==(DATA_WIDTH-1))&(sub_clock_ind==(DATA_CLK_PERIOD))) begin
                ind<=0;
                running<=0;
                data_valid_out<=1;
                held_data_out2={held_data_out[(DATA_WIDTH-2):0],chip_data_in};
                /*for (int i = 0; i < DATA_WIDTH; i=i+1) begin
                    data_out[i] <= held_data_out2[DATA_WIDTH-i-1];
                end*/
                data_out<=held_data_out2;
                chip_sel_out=1;
            end else begin
                held_data_out2=0;
                chip_sel_out=0;
            end
        end else begin
            chip_sel_out=1;
            chip_clk_out=0;
        held_data_out2=0;
        end
    end
  end
endmodule