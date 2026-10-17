// SPDX-License-Identifier: BSD-3-Clause
// Digital AC coupling approximation for the MiSTer audio output.
// The schematic output coupling network is not legible enough to derive a
// measured corner; 20 Hz is an explicit engineering assumption.
module cvs_audio_dc_blocker (
    input  wire clk,
    input  wire reset,
    input  wire sample_ce,
    input  wire signed [15:0] x,
    output wire signed [15:0] y
);
    reg signed [15:0] previous_x;
    reg signed [31:0] previous_y;
    wire signed [33:0] previous_y_ext = {{2{previous_y[31]}},previous_y};
    wire signed [32:0] delta = {{17{x[15]}},x} - {{17{previous_x[15]}},previous_x};
    // alpha = 4084/4096 ~= exp(-2*pi*22.4/48000). Express the leak as
    // 12/4096 = 3/1024 to avoid a wide constant multiplier in the core clock.
    wire signed [33:0] abs_y = previous_y < 0 ? -previous_y_ext : previous_y_ext;
    wire [33:0] leak_product = abs_y + (abs_y << 1);
    wire [33:0] leak_magnitude = leak_product >> 10;
    wire signed [33:0] leak = previous_y > 0 ? (leak_magnitude == 0 ? 34'sd1 : $signed(leak_magnitude)) :
                                previous_y < 0 ? -(leak_magnitude == 0 ? 34'sd1 : $signed(leak_magnitude)) : 34'sd0;
    wire signed [33:0] next_y = {{1{delta[32]}},delta} + previous_y_ext - leak;

    assign y = previous_y > 32'sd32767 ? 16'sh7fff :
               previous_y < -32'sd32768 ? 16'sh8000 : previous_y[15:0];

    always @(posedge clk) begin
        if (reset) begin
            previous_x <= 16'sd0;
            previous_y <= 32'sd0;
        end else if (sample_ce) begin
            previous_x <= x;
            previous_y <= next_y[31:0];
        end
    end
endmodule
