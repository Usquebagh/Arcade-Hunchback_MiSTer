// SPDX-License-Identifier: BSD-3-Clause
// Release async CPU reset first, then prime opcode zero through registered buses.
module cvs_cpu_reset #(
    parameter integer PRIME_CYCLES = 4
) (
    input wire clk, reset_in,
    output wire reset, reset_na
);
    localparam integer COUNT_WIDTH = PRIME_CYCLES < 1 ? 1 : $clog2(PRIME_CYCLES + 1);
    reg [COUNT_WIDTH-1:0] prime_count;

    // Load synchronously: reset_in is a combinational OR in cvs_reset, so it
    // must not drive an asynchronous preset. Assertion is still immediate
    // through the direct term below; the core reset is held far longer than
    // one clock, so the counter always loads before reset_in falls.
    always @(posedge clk) begin
        if (reset_in) prime_count <= PRIME_CYCLES[COUNT_WIDTH-1:0];
        else if (prime_count != 0) prime_count <= prime_count - 1'b1;
    end
    assign reset_na = !reset_in;
    // The direct term preserves immediate assertion, even between clock edges.
    assign reset = reset_in || (prime_count != 0);
endmodule
