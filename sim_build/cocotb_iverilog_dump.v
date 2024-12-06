module cocotb_iverilog_dump();
initial begin
    $dumpfile("C:/Users/disup/Programming/62050/fpga-chess/sim_build/uci_handler.fst");
    $dumpvars(0, uci_handler);
end
endmodule
