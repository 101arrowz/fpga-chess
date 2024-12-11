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
import random

def get_move(num):
    sq = lambda v: chr((v & 7) + ord('a')) + chr(((v >> 3) & 7) + ord('1'))

    return sq(num >> 9) + sq(num >> 3)

@cocotb.test()
async def test_a(dut):
    """cocotb test for seven segment controller"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut.rst_in.value = 1
    dut.go_in.value = 0
    await ClockCycles(dut.clk_in, 5)
    dut.rst_in.value = 0
    dut.depth_in.value = 2

    occupancies = {
        'knight': 0x0000240000040040,
        'bishop': 0x2400000000000024,
        'rook': 0x8100000000000081,
        'queen': 0x0800000040000000,
        'pawn': 0x00ef00101000ef00,

        'white': 0x000000005004eff5
    }

    # occupancies['queen'] |= 1 << 36
    # occupancies['white'] |= 1 << 36

    king_w = 0x04
    king_b = 0x3c
    checkmate = 0x0
    en_passant = 0x0
    castle = 0xf

    ply = 6
    ply50 = 3

    board_init = (occupancies['pawn'] << 364) | (occupancies['queen'] << 300) | (occupancies['rook'] << 236) | (occupancies['bishop'] << 172) | (occupancies['knight'] << 108) | \
        (occupancies['white'] << 44) | (king_b << 38) | (king_w << 32) | (checkmate << 30) | (en_passant << 26) | (castle << 22) | (ply << 7) | (ply50)
    board_init = 412501506796877871857922973576509435005244377754612855066526626439514056746161977768388018264037940730202487495364458655521156

    dut.board_in.value = board_init
    dut.board_valid_in.value = 1
    await ClockCycles(dut.clk_in, 1)
    dut.board_valid_in.value = 0
    await ClockCycles(dut.clk_in, 10)
    dut.go_in.value = 1
    await ClockCycles(dut.clk_in, 1)
    dut.go_in.value = 0

    # await ClockCycles(dut.clk_in, 10000)

    await RisingEdge(dut.valid_out)
    await ReadOnly()
    print('bestmove:', get_move(dut.bestmove_out.value.integer))
def coord_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v",
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_2_clock_ram.v",
        proj_path / "hdl" / "stream_sorter.sv",
        proj_path / "hdl" / "synchronizer.sv",
        proj_path / "hdl" / "move_generator.sv",
        proj_path / "hdl" / "move_evaluator.sv",
        proj_path / "hdl" / "move_executor.sv",
        proj_path / "hdl" / "engine_coordinator.sv"
    ]
    build_test_args = ["-Wall"]
    parameters = {'MAX_DEPTH': 4}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="engine_coordinator",
        includes=[proj_path / "hdl"],
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="engine_coordinator",
        test_module="test_engine_coordinator",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    coord_runner()