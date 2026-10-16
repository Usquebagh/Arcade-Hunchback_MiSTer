// SPDX-License-Identifier: BSD-3-Clause
// Single-port synchronous M10K inference template for Cyclone V.
module cvs_sync_ram_1p #(
    parameter integer ADDR_WIDTH = 10,
    parameter integer DEPTH = 1024
) (
    input wire clk,
    input wire write_enable,
    input wire [ADDR_WIDTH-1:0] address,
    input wire [7:0] write_data,
    input wire read_enable,
    output reg [7:0] read_data
);
    (* ramstyle = "M10K" *) reg [7:0] memory [0:DEPTH-1];

    always @(posedge clk) begin
        if (write_enable) memory[address] <= write_data;
        if (read_enable) read_data <= memory[address];
    end
endmodule
