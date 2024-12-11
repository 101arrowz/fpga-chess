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

@cocotb.test()
async def test_a(dut):
    """cocotb test for seven segment controller"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 5)
    dut.rst_in.value = 0
    dut.no_validate.value = 1

    occupancies = {
        'knight': 0x4200000000000042,
        'bishop': 0x2400000000000024,
        'rook': 0x8100000000000081,
        'queen': 0x0800000000000008,
        'pawn': 0x00ff00000000ff00,

        'white': 0x000000000000ffff
    }

    occupancies['queen'] |= 1 << 36
    # occupancies['white'] |= 1 << 36

    king_w = 0x04
    king_b = 0x3c
    checkmate = 0x0
    en_passant = 0x0
    castle = 0xf

    ply = 0
    ply50 = 0

    board_init = (occupancies['pawn'] << 364) | (occupancies['queen'] << 300) | (occupancies['rook'] << 236) | (occupancies['bishop'] << 172) | (occupancies['knight'] << 108) | \
        (occupancies['white'] << 44) | (king_b << 38) | (king_w << 32) | (checkmate << 30) | (en_passant << 26) | (castle << 22) | (ply << 7) | (ply50)

    dut.board_in.value = board_init
    dut.last_move_in.value = (16 << 9) | (1 << 3) | 0
    dut.valid_in.value = 1
    await ClockCycles(dut.clk_in, 1)
    dut.valid_in.value = 0

    await ClockCycles(dut.clk_in, 40)

def movegen_runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "move_generator.sv", proj_path / "hdl" / "move_evaluator.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="move_evaluator",
        includes=[proj_path / "hdl"],
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="move_evaluator",
        test_module="test_move_evaluator",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    movegen_runner()