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

@cocotb.test()
async def test_a(dut):
    """cocotb test for seven segment controller"""
    dut._log.info("Starting...")
    read_string=[]
    async def wait(cycles):
        for _ in range(cycles):
            await ClockCycles(dut.clk_in, 1)
            if(dut.char_out_ready.value and dut.char_out_valid.value):
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
    async def request_info(info):
        dut.info_in.value=int.from_bytes(info.encode('utf-8'), byteorder='little')
        dut.info_in_valid.value=1
        await wait(1)
        dut.info_in.value=0
        dut.info_in_valid.value=0
        await wait(1)
    async def request_bestmove(src_fil, src_rnk, dst_fil, dst_rnk, special):
        dut.best_move_in.value=special|(dst_fil<<3)|(dst_rnk<<6)|(src_fil<<9)|(src_rnk<<12)
        dut.best_move_in_valid.value=1
        await wait(1)
        # dut.best_move_in.src_fil.value=0
        # dut.best_move_in.src_rnk.value=0
        # dut.best_move_in.dst_fil.value=0
        # dut.best_move_in.dst_rnk.value=0
        dut.best_move_in_valid.value=0
        # dut.best_move_in.special.value=0
        await wait(1)

    await print_command("uci")
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

    await request_bestmove(0, 6, 1, 7, 6)
    await wait(100)

    await print_command("debug off")
    await wait(20)

    await print_command("position startpos moves a1d2 b3c4q f6e3 f6e3r f6e3n f6e3u f6e3 f6e3b")

    print(''.join(read_string), end='')




def uci_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "move_executor.sv", proj_path / "hdl" / "uci_handler.sv"]
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