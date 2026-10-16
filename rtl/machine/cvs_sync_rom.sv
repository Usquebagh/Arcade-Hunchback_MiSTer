// SPDX-License-Identifier: BSD-3-Clause
// Independent loader write and registered CPU read M10K ROM template.
module cvs_sync_rom #(
    parameter integer ADDR_WIDTH = 12,
    parameter integer DEPTH = 4096
) (
    input wire clk,
    input wire write_enable,
    input wire [ADDR_WIDTH-1:0] write_address,
    input wire [7:0] write_data,
    input wire read_enable,
    input wire [ADDR_WIDTH-1:0] read_address,
    output reg [7:0] read_data
);
    (* ramstyle = "M10K" *) reg [7:0] memory [0:DEPTH-1];

    always @(posedge clk) begin
        if (write_enable) memory[write_address] <= write_data;
        if (read_enable) read_data <= memory[read_address];
    end
endmodule
