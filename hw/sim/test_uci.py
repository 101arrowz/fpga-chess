import cocotb
import os
import random
import sys
from math import log
import logging
from pathlib import Path
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly
from cocotb.utils import get_sim_time as gst
from cocotb.runner import get_runner
import chess
from chess.pgn import read_game

@cocotb.test()
async def test_a(dut):
    """cocotb test for seven segment controller"""
    dut._log.info("Starting...")
    read_string=[]
    def print_board(brd=None):
        val=""
        if brd is None:
            brd = dut.board_out.value.integer
            print(brd)
        pieces=brd>>108
        pieces_w=(brd>>44)&(0xFFFF_FFFF_FFFF_FFFF)
        kings=(brd>>32)&4095
        ind=0
        for row in range(8):
            for col in range(8):
                piece='_'
                esc=""
                if((pieces_w>>ind)&1):
                    esc="\033[90m"
                else:
                    esc="\033[34m"
                if((pieces>>(ind))&1):
                    piece="N"
                elif((pieces>>(ind)>>64)&1):
                    piece="B"
                elif((pieces>>(ind)>>128)&1):
                    piece="R"
                elif((pieces>>(ind)>>192)&1):
                    piece="Q"
                elif((pieces>>(ind)>>256)&1):
                    piece="P"
                elif((kings&63==ind) or ((kings>>6)&63==ind)):
                    piece="K"
                else:
                    esc="\033[0m"
                val=val+esc+piece
                ind+=1
            val=val+"\n"
        print(val, "\033[0m")
    async def wait(cycles):
        while(cycles):
            await ClockCycles(dut.clk_in, 1)
            cycles-=1
            if(dut.char_out_ready and dut.char_out_valid):
                read_string.append(chr(dut.char_out.value))
            if(dut.board_out_valid.value):
                print_board()
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 5)
    dut.rst_in.value = 0
    dut.char_out_ready.value=1
    await wait(5)
    async def print_command(command):
        for i in (command+"\n"):
            dut.char_in.value=ord(i)
            dut.char_in_valid.value=1
            await wait(1)
            dut.char_in.value=0
            dut.char_in_valid.value=0
            await wait(4)
    async def request_info(info):
        dut.info_in.value=int.from_bytes(info.encode('utf-8'), byteorder='little')
        dut.info_in_valid.value=1
        await wait(1)
        dut.info_in.value=0
        dut.info_in_valid.value=0
        await wait(1)
    async def request_bestmove(src_col, src_row, dst_col, dst_row, special):
        dut.best_move_in.value=special|(dst_col<<3)|(dst_row<<6)|(src_col<<9)|(src_row<<12)
        dut.best_move_in_valid.value=1
        await wait(1)
        dut.best_move_in.src_col=0
        dut.best_move_in.src_row=0
        dut.best_move_in.dst_col=0
        dut.best_move_in.dst_row=0
        dut.best_move_in_valid.value=0
        dut.best_move_in.special=0
        await wait(1)

    """await print_command("uci")
    await wait(100)

    await print_command("debug on")
    await wait(10)

    await request_info("ABC")
    await wait(100)
    await request_info("Yada")
    await wait(100)
    await request_info("Error: Test")
    await wait(100)

    await print_command("go")

    await request_bestmove(0, 0, 3, 4, 6)
    await wait(100)

    await print_command("debug off")
    await wait(20)

    await print_command("position startpos moves a1d2 b3c4q f6e3 f6e3r f6e3n f6e3u f6e3 f6e3b")
    await wait(20)

    
    print(''.join(read_string))"""
    # proj_path = Path(__file__).resolve().parent.parent
    # with open(proj_path / "sim" / "test.pgn") as pgn:
    #     game = read_game(pgn)
    #     board = game.board()
    #     moves = [move.uci() for move in game.mainline_moves()]
    #     for i in range(len(moves)):
    #         print("Move", i, ":", moves[i])
    #         await print_command("move " + moves[i])
    #         await wait(20)
    #         if(i==10):
    #             break
    # await print_command("move b1c3 b8c6")
    # await wait(20)
    
    # print_board(0x00ff00000000ff000800000000000008810000000000008124000000000000244200000000000042000000000000fffff0403c00000)
    # print_board(0x00ff00000000ff000800000000000008810000000000008124000000000000244200000000200002000000000020fffff0417c00081)
    # print_board(0x00ff00000000ff000800000000000008810000000000008124000000000000244200000000200002000000000020fffff0417c00081)
    # print_board(0x00ff00000000ff000800000000000008810000000000008124000000000000244200000000040040000000000004fffff040bc00081)
    # print_board(0x00ff00001000ef000800000000000008810000000000008124000000000000244200000000000042000000001000fffff0413c00080)
    # print_board(0x00ff00000000ff000800000000000008810000000000008124000000000000244200000000000042000000000000fffff0403c00000)
    # print_board(0x00ef00100000ff000800000000000008810000000000008124000000000000244200000000200002000000000020fffff0413c00100)
    # print_board(0x00e700101000ef000000000800000008810000000000008124000000000000044200000000000042000000001400efdff040fc00300)
    # print_board(0x00e700180000ef000800000000000008810000000000008124000000040000044200000000000042000000081400efdff040fc00280)
    # print_board(0x00e700100000ef000000000800000008810000000000008124000000040000044200000000000042000000001400efdff040fc00300)
    # print_board(0x00e700100000ef000000000000000008810000000000008124000008000000044200000000000042000000081400efdff040fc00380)
    # print_board(0x00e700100000ef000000000800000008810000000000008124000000040000044200000000000042000000001400efdff040fc00300)
    # print_board(0x00e700180000ef000800000000000008810000000000008124000000040000040200200000000042000000081400efdff0417c00301)
    # print_board(0x00e700181000ef000800000000000008810000000000008124000000040000044200000000200002000000001420efdff0417c00281)
    await print_command("position startpos moves e2e4 b8c6 g1e2 g8f6 e2c3 d7d5 e4d5 f6d5 c3d5 d8d5 b1c3 d5d7 d2d3 e7e5 c1e3 f8d6 d1f3 c6d4 f3g3 d4c2 e1d2 c2a1 g3g7 h8f8 f1e2 d7c6 h1a1 c8e6 e2f3 c6a6 f3d5 e6d5 c3d5 a6c6 d5f6 e8d8 a1c1 c6a4 e3c5 d6c5 c1c5 a4b4 c5c3 b4d6 g7g5 h7h5 f6h5 d8e8 h5g7 e8d7 g7f5")
    await wait(20)
    print_board()

def uci_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "1_types.sv", proj_path / "hdl" / "move_executor.sv", proj_path / "hdl" / "uci_handler.sv"]
    # sources += [proj_path / "hdl" / "bto7s.sv"] #uncomment this if you make bto7s module its own fileb
    build_test_args = ["-Wall"]
    parameters = {} #setting parameter to a short amount (for testing)
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        includes=[proj_path / "hdl"],
        hdl_toplevel="uci_handler",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="uci_handler",
        test_module="test_uci",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    uci_runner()