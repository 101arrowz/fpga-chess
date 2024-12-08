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
    arr=list(range(20))
    random.shuffle(arr)
    for i in arr:
        dut.value_in=i
        dut.key_in=i
        dut.valid_in=1
        await ClockCycles(dut.clk_in, 1)
    dut.valid_in=0
    await ClockCycles(dut.clk_in, 10)
    b=[]
    for i in range(dut.array_len_out.value):
        b.append((dut.array_out.value>>(i*15))&(2**15-1))
    print(arr)
    print(b)




def sorter_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "stream_sorter.sv"]
    # sources += [proj_path / "hdl" / "bto7s.sv"] #uncomment this if you make bto7s module its own file
    build_test_args = ["-Wall"]
    parameters = {} #setting parameter to a short amount (for testing)
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        includes=[proj_path / "hdl"],
        hdl_toplevel="stream_sorter",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="stream_sorter",
        test_module="test_stream_sorter",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    sorter_runner()