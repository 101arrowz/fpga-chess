`include "1_types.sv"
`timescale 1ns / 1ps
`default_nettype none

typedef enum {READY, DEBUG, 
POSITION_BOARD_TYPE, POSITION_NEXT, POSITION_MOVES, 
GO_PARAM,
GO_PARSEINT,

TRASH} uci_state;
typedef enum {TIME, INC} go_state;
typedef enum {READY_OUT, INFO, BEST_MOVE} uci_output_state;

module uci_handler #(parameter INFO_LEN = 52)//INFO_LEN must be atleast 52 to support full response from UCI command
   (
    input wire 	       clk_in,
    input wire 	       rst_in,

    input wire[7:0]   char_in,
    input wire char_in_valid,
    output logic   char_in_ready,

    input wire[(INFO_LEN-1):0][7:0] info_in,
    input wire info_in_valid,
    output logic info_in_ready,
    
    input move_t best_move_in,
    output logic best_move_in_ready,
    input wire best_move_in_valid,
    
    output board_t board_out,
    output logic board_out_valid,

    output logic go,
    output logic[31:0] go_time,
    output logic[31:0] go_inc,
    output logic in_debug,

    output logic[7:0]   char_out,
    input wire char_out_ready,
    output logic char_out_valid
    );
    localparam new_line = 8'b0000_1010;
    localparam default_time = 32'hFFFF_FFFF;
    localparam default_inc = 32'hFFFF_FFFF;
    localparam board_t start_board = {
        //Pieces
        64'h00ff00000000ff00, //Pawn
        64'h0800000000000008, //Queen
        64'h8100000000000081, //Rook
        64'h2400000000000024, //Bishop
        64'h4200000000000042, //Knight

        64'h000000000000ffff, //pieces_w
        12'h0f04, //kings
        2'h0, //checkmate
        4'h0, //en_passant
        4'hf, //castle
        15'h0000, //ply
        7'h00 //ply50
    };
    uci_state current_state = READY;
    uci_output_state current_output_state = READY_OUT;
    logic in_debug_reg = 0;
    logic[13:0][7:0] best_move_buff=0;
    logic[16:0][7:0] charbuff=0;
    logic[16:0][7:0] charbuff_new=0;
    logic[(INFO_LEN+4):0][7:0] info_in_buff=0;
    board_t temp_board = start_board;
    go_state cur_go;
    logic go_hit_int;

    move_t exec_move_in;
    logic exec_valid_in;
    logic uci_requested=0;
    logic output_board=0;
    move_executor executor(.clk_in(clk_in), .rst_in(rst_in), .board_in(temp_board), .move_in(exec_move_in), .valid_in(exec_valid_in));

    always_comb begin
        if(char_in_valid&&char_in_ready) begin
            integer i;
            charbuff_new[0]=char_in;
            for(i=1; i <= 16; i++) begin
                charbuff_new[i]=charbuff[i-1];
            end
        end else begin
            charbuff_new=charbuff;
        end

        in_debug=in_debug_reg;
        info_in_ready=(current_output_state==READY_OUT)&&(info_in_buff==0)&&(uci_requested==0);
        best_move_in_ready=(current_output_state==READY_OUT)&&(uci_requested==0);
        char_in_ready=1;
    end
    always_ff@(posedge clk_in) begin
        move_t cur_move;
        logic[7:0] best_move_append=0;

        exec_valid_in<=0;
        char_out_valid<=0;
        char_out<=0;
        go<=0;
        board_out_valid<=0;

        if(executor.valid_out) begin
            temp_board<=executor.board_out;
            if(output_board) begin
                board_out<=executor.board_out;
                board_out_valid<=1;
                output_board<=0;
            end
        end
        //ASSUMED THAT MULTIPLE CLOCK CYCLES BETWEEN CHARS (For example, will break if newline comes before move executor finishes)
        //Will also break if bestmove attempts to use executor at the same time as move or position (If this happens, we're doing something wrong)
        if(char_in_valid&&char_in_ready) begin
            charbuff<=charbuff_new;
            case (current_state)
                READY: begin
                    if(charbuff_new[7:0]=="position") begin
                        current_state<=POSITION_BOARD_TYPE;
                        charbuff<=0;
                    end else if(charbuff_new[4:0]=="debug") begin
                        current_state<=DEBUG;
                        charbuff<=0;
                    end else if(charbuff_new[1:0]=="go") begin
                        current_state<=GO_PARAM;
                        go_time<=default_time;
                        go_inc<=default_inc;
                        charbuff<=0;
                    end else if(charbuff_new[4:0]=="move ") begin
                        current_state<=POSITION_MOVES;
                        charbuff<=0;
                    end else if(charbuff_new[2:0]=="uci") begin
                        current_state<=TRASH;
                        charbuff<=0;
                        uci_requested<=1;
                    end  else if(charbuff_new[0]==new_line) begin
                        current_state<=READY;
                        charbuff<=0;
                    end
                end
                DEBUG: begin
                    if(charbuff_new[2:0]==" on") begin
                        current_state<=TRASH;
                        charbuff<=0;
                        in_debug_reg<=1;
                    end else if(charbuff_new[3:0]==" off") begin
                        current_state<=TRASH;
                        charbuff<=0;
                        in_debug_reg<=0;
                    end else if(charbuff_new[0]==new_line) begin
                        current_state<=READY;
                        charbuff<=0;
                    end
                end
                POSITION_BOARD_TYPE: begin
                    if(charbuff_new[8:0]==" startpos") begin
                        current_state<=POSITION_NEXT;
                        charbuff<=0;
                        temp_board<=start_board;
                    end else if(charbuff_new[0]==new_line) begin
                        current_state<=READY;
                        charbuff<=0;
                    end
                end
                POSITION_NEXT: begin
                    if(charbuff_new[6:0]==" moves ") begin
                        current_state<=POSITION_MOVES;
                        charbuff<=0;
                    end else if(charbuff_new[0]==new_line) begin
                        current_state<=READY;
                        charbuff<=0;
                        board_out<=temp_board;
                        board_out_valid<=1;
                    end
                end
                POSITION_MOVES: begin
                    if((charbuff_new[0]==" ")||(charbuff_new[0]==new_line)) begin
                        if(charbuff_new[5]==0) begin
                            cur_move.src.fil = charbuff_new[4]-"a";
                            cur_move.src.rnk = charbuff_new[3]-"1";
                            cur_move.dst.fil = charbuff_new[2]-"a"; 
                            cur_move.dst.rnk = charbuff_new[1]-"1";
                            cur_move.special=SPECIAL_UNKNOWN;
                        end else if(charbuff_new[6]==0) begin
                            cur_move.src.fil = charbuff_new[5]-"a";
                            cur_move.src.rnk = charbuff_new[4]-"1";
                            cur_move.dst.fil = charbuff_new[3]-"a"; 
                            cur_move.dst.rnk = charbuff_new[2]-"1";
                            case (charbuff_new[1])
                                "n": cur_move.special=SPECIAL_PROMOTE_KNIGHT;
                                "b": cur_move.special=SPECIAL_PROMOTE_BISHOP;
                                "r": cur_move.special=SPECIAL_PROMOTE_ROOK;
                                "q": cur_move.special=SPECIAL_PROMOTE_QUEEN;
                                default: cur_move.special=SPECIAL_NONE;
                            endcase
                        end
                        if((charbuff_new[5]==0)||(charbuff_new[6]==0)) begin
                            //$display("(%d, %d)->(%d, %d), %d", cur_move.src.fil, cur_move.src.rnk, cur_move.dst.fil, cur_move.dst.rnk, cur_move.special);
                            charbuff<=0;
                            exec_valid_in<=1;
                            exec_move_in<=cur_move;
                        end
                        if(charbuff_new[0]==new_line) begin
                            current_state<=READY;
                            charbuff<=0;
                            output_board<=(charbuff_new[5]==0)||(charbuff_new[6]==0);
                        end
                    end 
                end
                GO_PARAM:  begin
                    if((charbuff_new[4:0]=="wtime")&&(~board_out.ply[0])) begin
                        current_state<=GO_PARSEINT;
                        cur_go<=TIME;
                        go_time<=0;
                        go_hit_int<=0;
                        charbuff<=0;
                    end else if((charbuff_new[4:0]=="btime")&&(board_out.ply[0])) begin
                        current_state<=GO_PARSEINT;
                        cur_go<=TIME;
                        go_time<=0;
                        go_hit_int<=0;
                        charbuff<=0;
                    end else if((charbuff_new[3:0]=="winc")&&(~board_out.ply[0])) begin
                        current_state<=GO_PARSEINT;
                        cur_go<=INC;
                        go_inc<=0;
                        go_hit_int<=0;
                        charbuff<=0;
                    end else if((charbuff_new[3:0]=="binc")&&(board_out.ply[0])) begin
                        current_state<=GO_PARSEINT;
                        cur_go<=INC;
                        go_inc<=0;
                        go_hit_int<=0;
                        charbuff<=0;
                    end else if(charbuff_new[0]==new_line) begin
                        current_state<=READY;
                        charbuff<=0;
                        go<=1;
                    end
                end
                GO_PARSEINT: begin
                    logic[31:0] new_int;
                    new_int=(((cur_go==TIME) ? go_time : go_inc)*10)+(charbuff_new[0]-"0");
                    if((charbuff_new[0]>="0")&&(charbuff_new[0]<="9")) begin
                        case (cur_go)
                            TIME: go_time<=new_int;
                            INC: go_inc<=new_int;
                        endcase
                        go_hit_int<=1;
                    end else if(((charbuff_new[0]==" ")&&go_hit_int)||(charbuff_new[0]!=" ")) begin
                        if(charbuff_new[0]!=" ") begin
                            current_state<=READY;
                            go<=1;
                        end else begin
                            current_state<=GO_PARAM;
                        end
                        charbuff<=0;
                    end
                end
                TRASH: begin
                    if(charbuff_new[0]==new_line) begin
                        current_state<=READY;
                        charbuff<=0;
                    end
                end
            endcase
            
        end
        case (current_output_state)
            READY_OUT: begin
                if((info_in_buff==0)&&uci_requested) begin
                    current_output_state<=INFO;
                    //I would love to just have a reverse function to make this readable. But IVerilog won't stop complaining, so we need to do this instead.
                    info_in_buff<={"koicu", new_line, "caasI nalyD ,tterraB nujrA rohtua di", new_line, "reviR eman di"};
                    uci_requested<=0;
                end else if((!(best_move_in_valid&&best_move_in_ready))&&(info_in_buff!=0)) begin
                    current_output_state<=INFO;
                end else if(info_in_valid&&info_in_ready) begin
                    current_output_state<=INFO;
                    info_in_buff<={info_in, " ofni"};
                end
                if(best_move_in_valid&&best_move_in_ready) begin
                    current_output_state<=BEST_MOVE;
                    case (best_move_in.special)
                        SPECIAL_PROMOTE_KNIGHT: best_move_append="n";
                        SPECIAL_PROMOTE_BISHOP: best_move_append="b";
                        SPECIAL_PROMOTE_ROOK: best_move_append="r";
                        SPECIAL_PROMOTE_QUEEN: best_move_append="q";
                        default: best_move_append=0;
                    endcase
                    best_move_buff<={best_move_append, 8'("1"+best_move_in.dst.rnk), 8'("a"+best_move_in.dst.fil), 8'("1"+best_move_in.src.rnk), 8'("a"+best_move_in.src.fil), " evomtseb"};
                    //exec_valid_in<=1;
                    //exec_move_in<=best_move_in;
                end
                
            end
            INFO: begin
                char_out_valid<=1;
                if(char_out_ready&&char_out_valid) begin
                    integer i;
                    info_in_buff[INFO_LEN+4]<=0;
                    for(i=0; i < INFO_LEN+4; i++) begin
                        info_in_buff[i]<=info_in_buff[i+1];
                    end
                    if(info_in_buff[0]==0) begin
                        current_output_state<=READY_OUT;
                        info_in_buff<=0;
                        char_out_valid <= 0;
                    end
                    char_out<=info_in_buff[1]==0 ? new_line : info_in_buff[1];
                end else begin
                    char_out<=info_in_buff[0]==0 ? new_line : info_in_buff[0];
                end
            end
            BEST_MOVE: begin
                char_out_valid<=1;
                if(char_out_ready&&char_out_valid) begin
                    integer i;
                    if(best_move_buff[0]==0) begin
                        current_output_state<=READY_OUT;
                        best_move_buff<=0;
                        char_out_valid <= 0;
                    end
                    best_move_buff[13]<=0;
                    for(i=0; i < 13; i++) begin
                        best_move_buff[i]<=best_move_buff[i+1];
                    end
                    char_out<=best_move_buff[1]==0 ? new_line : best_move_buff[1];
                end else begin
                    char_out<=best_move_buff[0]==0 ? new_line : best_move_buff[0];
                end
            end
        endcase

        if(rst_in) begin
            charbuff<=0;
            best_move_buff<=0;
            current_state<=READY;
            current_output_state<=READY_OUT;
            in_debug_reg<=0;
            char_out<=0;
            char_out_valid<=0;
            board_out<=start_board;
            board_out_valid<=0;
            uci_requested<=0;
            output_board<=0;

            go_time<=default_time;
            go_inc<=default_inc;
        end
    end
endmodule

`default_nettype wire
