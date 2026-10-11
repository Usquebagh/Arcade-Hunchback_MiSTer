// SPDX-License-Identifier: BSD-3-Clause
// Asynchronous assertion, two-clock release, then loader/PLL qualification.
module cvs_reset (
    input wire clk,
    input wire reset_async,
    input wire pll_locked,
    input wire load_active,
    input wire rom_loaded,
    output wire reset
);
    (* async_reg = "true" *) reg [1:0] release_pipe;
    always @(posedge clk or posedge reset_async) begin
        if (reset_async) release_pipe <= 2'b11;
        else release_pipe <= {release_pipe[0], 1'b0};
    end
    assign reset = release_pipe[1] || !pll_locked || load_active || !rom_loaded;
endmodule
