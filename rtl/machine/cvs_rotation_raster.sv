// SPDX-License-Identifier: BSD-3-Clause
// Preserve native CVS pixel cadence and add only the low-DE row separator
// required by screen_rotate.
module cvs_rotation_raster (
    input wire clk, reset,
    input wire pixel_ce, pixel_valid,
    input wire [7:0] x,
    output wire rotate_pixel_ce, rotate_de
);
    parameter LAST_X = 8'd243;
    reg line_end_pending=1'b0;
    reg line_gap=1'b0;
    always @(posedge clk) begin
        if(reset) begin
            line_end_pending<=1'b0;
            line_gap<=1'b0;
        end else begin
            if(pixel_ce && pixel_valid) begin
                if(x==LAST_X) line_end_pending<=1'b1;
            end

            // Insert a low-DE event between adjacent rows without changing
            // the number or spacing of source pixels.
            if(line_gap) begin
                line_gap<=1'b0;
                line_end_pending<=1'b0;
            end else line_gap<=line_end_pending;
        end
    end
    assign rotate_pixel_ce=pixel_ce || line_gap;
    assign rotate_de=pixel_valid && !line_gap;
endmodule
