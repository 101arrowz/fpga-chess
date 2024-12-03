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
        while(cycles):
            await ClockCycles(dut.clk_in, 1)
            cycles-=1
            if(dut.char_out_ready and dut.char_out_valid):
                read_string.append(chr(dut.char_out.value))
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 5)
    dut.rst_in.value = 0
    dut.char_out_ready=1
    await wait(5)
    async def print_command(command):
        for i in (command+"\n"):
            dut.char_in=ord(i)
            dut.char_in_valid=1
            await wait(1)
            dut.char_in=0
            dut.char_in_valid=0
            await wait(4)
    async def request_info(info):
        dut.info_in=int.from_bytes(info.encode('utf-8'), byteorder='little')
        dut.info_in_valid=1
        await wait(1)
        dut.info_in=0
        dut.info_in_valid=0
        await wait(1)
    async def request_bestmove(src_col, src_row, dst_col, dst_row, special):
        dut.best_move_in=special|(dst_row<<3)|(dst_col<<6)|(src_row<<9)|(src_col<<12)
        dut.best_move_in_valid=1
        await wait(1)
        dut.best_move_in.src_col=0
        dut.best_move_in.src_row=0
        dut.best_move_in.dst_col=0
        dut.best_move_in.dst_row=0
        dut.best_move_in_valid=0
        dut.best_move_in.special=0
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

    await request_bestmove(0, 0, 3, 4, 6)
    await wait(100)

    await print_command("debug off")
    await wait(20)

    await print_command("position startpos moves a1d2 b3c4q f6e3 f6e3r f6e3n f6e3u f6e3 f6e3b")

    
    print(''.join(read_string))




def uci_runner():
    """Simulate the counter using the Python runner."""
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "types_1.sv", proj_path / "hdl" / "move_executor.sv", proj_path / "hdl" / "cocotb_only" / "uci_handler.sv"]
    # sources += [proj_path / "hdl" / "bto7s.sv"] #uncomment this if you make bto7s module its own file
    build_test_args = ["-Wall"]
    parameters = {} #setting parameter to a short amount (for testing)
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
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