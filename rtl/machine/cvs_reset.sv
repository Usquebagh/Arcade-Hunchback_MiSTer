// SPDX-License-Identifier: BSD-3-Clause
// Asynchronous assertion, minimum hold, two-clock release, then qualification.
module cvs_reset #(
    parameter integer HOLD_CYCLES = 1_140_000 // 20 ms at the 57 MHz system clock
) (
    input wire clk,
    input wire reset_async,
    input wire pll_locked,
    input wire load_active,
    input wire rom_loaded,
    output wire reset
);
    localparam integer HOLD_WIDTH = $clog2(HOLD_CYCLES + 1);
    reg [HOLD_WIDTH-1:0] hold_count;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] release_pipe;

    always @(posedge clk or posedge reset_async) begin
        if (reset_async) hold_count <= HOLD_CYCLES[HOLD_WIDTH-1:0];
        else if (hold_count != 0) hold_count <= hold_count - 1'b1;
    end

    always @(posedge clk or posedge reset_async) begin
        if (reset_async) release_pipe <= 2'b11;
        else release_pipe <= {release_pipe[0], 1'b0};
    end
    assign reset = (hold_count != 0) || release_pipe[1] || !pll_locked || load_active || !rom_loaded;
endmodule
