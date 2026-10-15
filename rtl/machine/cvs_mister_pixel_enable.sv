// SPDX-License-Identifier: BSD-3-Clause
// MiSTer CE_PIXEL aligned to the normalized RGB/sync pipeline.
module cvs_mister_pixel_enable (
    input wire clk, reset, pixel_ce_in,
    output wire pixel_ce_out
);
    reg [5:0] delay;
    always @(posedge clk) begin
        if(reset)delay<=6'd0;
        else delay<={delay[4:0],pixel_ce_in};
    end
    assign pixel_ce_out=delay[5];
endmodule
