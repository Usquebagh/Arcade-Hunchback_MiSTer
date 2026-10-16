// SPDX-License-Identifier: BSD-3-Clause
// CPU read/write and independent display read M10K inference template.
module cvs_sync_ram_2p #(
    parameter integer ADDR_WIDTH = 10,
    parameter integer DEPTH = 1024
) (
    input wire clk,
    input wire a_write,
    input wire [ADDR_WIDTH-1:0] a_address,
    input wire [7:0] a_data,
    input wire a_read,
    output reg [7:0] a_q,
    input wire b_read,
    input wire [ADDR_WIDTH-1:0] b_address,
    output reg [7:0] b_q
);
    (* ramstyle = "M10K" *) reg [7:0] memory [0:DEPTH-1];

    always @(posedge clk) begin
        if (a_write) memory[a_address] <= a_data;
        if (a_read) a_q <= memory[a_address];
        if (b_read) b_q <= memory[b_address];
    end
endmodule
