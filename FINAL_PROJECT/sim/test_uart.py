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
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut._log.info("Holding reset...")
    dut.rst_in.value = 1
    dut._log.info("setting val_in to 'h01234567")
    #dut.val_in.value = 0x01234567
    await ClockCycles(dut.clk_in, 3)
    await  FallingEdge(dut.clk_in)
    dut._log.info("setting reset to 0")
    dut.rst_in.value = 0
    dut.data_byte_in=0x0F
    dut.trigger_in=1
    await ClockCycles(dut.clk_in, 1)
    dut.trigger_in=0
    await ClockCycles(dut.clk_in, 300)
    dut._log.info("Holding reset...")
    #dut.val_in.value = 0x89abcdef
    await ClockCycles(dut.clk_in, 300)

def uart_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "uart_transmit.sv"]
    # sources += [proj_path / "hdl" / "bto7s.sv"] #uncomment this if you make bto7s module its own file
    build_test_args = ["-Wall"]
    parameters = {'BAUD_RATE':10_000_000} #setting parameter to a short amount (for testing)
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="uart_transmit",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale = ('1ns','1ps'),
        waves=True
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="uart_transmit",
        test_module="test_uart",
        test_args=run_test_args,
        waves=True
    )

if __name__ == "__main__":
    uart_runner()