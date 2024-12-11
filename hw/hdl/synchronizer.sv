`default_nettype none

module synchronizer#(parameter COUNT = 0, parameter WIDTH = 1)(
    input wire                 clk_in,
    input wire                 rst_in,
    input wire   [WIDTH - 1:0] data_in,
    output logic [WIDTH - 1:0] data_out
);

    generate
        if (COUNT == 0) begin
            assign data_out = data_in;
        end else if (COUNT == 1) begin
            always_ff @(posedge clk_in) begin
                data_out <= data_in;
            end
        end else begin
            logic [WIDTH - 1:0] buffer [COUNT - 2:0];

            always_ff @(posedge clk_in) begin
                data_out <= rst_in ? data_in : buffer[0];
                for (integer i = 0; i < COUNT - 2; i = i + 1) begin
                    buffer[i] <= rst_in ? data_in : buffer[i + 1];
                end
                buffer[COUNT - 2] <= data_in;
            end
        end
    endgenerate
endmodule

`default_nettype wire
