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
    """def print_board():
        val=""
        pieces=dut.board_out.value>>108
        pieces_w=(dut.board_out.value>>44)&(0xFFFF_FFFF_FFFF_FFFF)
        kings=(dut.board_out.value>>32)&4095
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
        print(val, "\033[0m")"""
    async def wait(cycles):
        while(cycles):
            await ClockCycles(dut.clk_in, 1)
            cycles-=1
            if(dut.char_out_ready and dut.char_out_valid):
                read_string.append(chr(dut.char_out.value))
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

    with open(proj_path / "sim" / "test.pgn") as pgn:
        game = read_game(pgn)
        board = game.board()
        moves = [move.uci() for move in game.mainline_moves()]
        move = moves[0]
        for i in range(len(moves)):
            print("Move", i, ":", moves[i])
            await print_command("move " + moves[i])
            await wait(20)
            if(i==10):
                break
    await print_command("go")
    await wait(20)



def uci_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "1_types.sv", 
               proj_path / "hdl" / "move_generator.sv", 
               proj_path / "hdl" / "move_executor.sv", 
               proj_path / "hdl" / "move_evaluator.sv", 
               proj_path / "hdl" / "stream_sorter.sv", 
               proj_path / "hdl" / "synchronizer.sv", 
               proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v", 
               proj_path / "hdl" / "engine_coordinator_sim.sv", 
               proj_path / "hdl" / "uci_handler.sv", 
               proj_path / "hdl" / "Z_top_level_test.sv"]
    # sources += [proj_path / "hdl" / "bto7s.sv"] #uncomment this if you make bto7s module its own file
    build_test_args = ["-Wall"]
    parameters = {} #setting parameter to a short amount (for testing)
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        includes=[proj_path / "hdl"],
        hdl_toplevel="top_level_test",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="top_level_test",
        test_module="test_system",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    uci_runner()