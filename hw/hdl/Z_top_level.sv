`include "1_types.sv"
`default_nettype none // prevents system from inferring an undeclared logic (good practice)

module top_level
  (
   input wire          clk_100mhz, //100 MHz onboard clock
   //input wire clk_40mhz,
   input wire [15:0]   sw, //all 16 input slide switches
   //input wire [3:0]    btn, //all four momentary button switches
   input wire btnd,
   input wire btnc,
   output logic [15:0] led, //16 green output LEDs (located right above switches)
   //output logic [2:0]  rgb0, //RGB channels of RGB LED0
   //output logic [2:0]  rgb1, //RGB channels of RGB LED1
   //output logic        spkl, spkr, // left and right channels of line out port
   //input wire          cipo, // SPI controller-in peripheral-out
   //output logic        copi, dclk, cs, // SPI controller output signals
	 input wire 				 uart_txd_in, // UART computer-FPGA
	 output logic 			 uart_rxd_out // UART FPGA-computer
  //output logic [3:0] ss0_an,//anode control for upper four digits of seven-seg display
  //output logic [3:0] ss1_an,//anode control for lower four digits of seven-seg display
  //output logic [6:0] ss0_c, //cathode controls for the segments of upper four digits
  //output logic [6:0] ss1_c //cathode controls for the segments of lower four digits
   );
    //have btnd control system reset
    logic               sys_rst;
    assign sys_rst = btnd;

    //assign rgb0 = 0; //set to 0.
    //assign rgb1 = 0; //set to 0.

    localparam CLOCK_FREQ = 40_000_000;
    wire clk_game;

    clk_wiz_0_clk_wiz clkw(
      .clk_in1(clk_100mhz),
      .clk_out1(clk_game)
    );

    uart_receive #(.INPUT_CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(115200)) reciever (.clk_in(clk_game),
    .rst_in(sys_rst),
    .rx_wire_in(uart_txd_in));
    
    uart_transmit #(.INPUT_CLOCK_FREQ(CLOCK_FREQ), .BAUD_RATE(115200)) transmitter(.clk_in(clk_game), 
    .rst_in(sys_rst),
    .tx_wire_out(uart_rxd_out));

    board_t board;
    logic board_valid;
    logic go;

    move_t move;
    logic move_valid;
    logic ec_ready;
    logic did_go;
    logic [31:0] p_time;
    logic [31:0] p_inc;
    assign p_time = 32'sd60000;
    assign p_inc = 32'sd1000;

    logic [31:0] coord_time;

    uci_handler uci
    (.clk_in(clk_game), 
    .rst_in(sys_rst),
    .char_in(reciever.data_byte_out),
    .char_in_valid(reciever.new_data_out),
    .info_in(0),
    .info_in_valid(0),
    .best_move_in(move),
    .best_move_in_valid(move_valid),
    .char_out(transmitter.data_byte_in),
    .char_out_ready(~transmitter.busy_out),
    .char_out_valid(transmitter.trigger_in),
    //.go_time(p_time),
    //.go_inc(p_inc),
    .board_out(board),
    .board_out_valid(board_valid),
    .go(go)
    );

    always_ff @(posedge clk_game) begin
      if (sys_rst) begin
        did_go <= 0;
        coord_time <= 0;
      end else begin
        did_go <= did_go | go;
        if (go) begin
          coord_time <= (p_inc < (p_time >> 3) ? p_inc : (p_time >> 3)) * (CLOCK_FREQ / 1000);
        end else if (coord_time > 0) begin
          coord_time <= coord_time - 1;
        end
      end
    end

    assign led[0] = btnc;
    assign led[1] = ec_ready;
    assign led[2] = did_go;

    engine_coordinator ec(
      .clk_in(clk_game),
      .rst_in(sys_rst),
      .board_in(board),
      .board_valid_in(board_valid),
      .go_in(go),
      .time_in(sw[8] ? 32'b1 : coord_time),
      .depth_in(sw[4:0]),
      .ready_out(ec_ready), // TODO
      .bestmove_out(move),
      .valid_out(move_valid),
      .info_buf(),
      .info_valid_out()
    );
endmodule // top_level

`default_nettype wire