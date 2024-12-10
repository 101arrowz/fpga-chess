module cocotb_iverilog_dump();
initial begin
    $dumpfile("C:/Users/disup/Programming/62050/fpga-chess/sim_build/top_level_test.fst");
    $dumpvars(0, top_level_test);
end
endmodule
