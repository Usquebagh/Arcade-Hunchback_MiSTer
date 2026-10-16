// SPDX-License-Identifier: BSD-3-Clause
// Adapt the CVS full-width active raster to screen_rotate's per-line DE framing.
module cvs_rotation_raster (
    input wire clk, reset,
    input wire pixel_ce, pixel_valid,
    input wire [7:0] x,
    output wire rotate_pixel_ce, rotate_de
);
    parameter LAST_X = 8'd226;
    reg line_gap=1'b0;
    always @(posedge clk) begin
        if(reset) line_gap<=1'b0;
        else line_gap<=pixel_ce && pixel_valid && x==LAST_X;
    end
    assign rotate_pixel_ce=pixel_ce || line_gap;
    assign rotate_de=pixel_valid && !line_gap;
endmodule
