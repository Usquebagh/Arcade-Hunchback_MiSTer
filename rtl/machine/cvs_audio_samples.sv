// SPDX-License-Identifier: BSD-3-Clause
// Explicit raw digital scaling; physical DAC/filter/mixer/speech unresolved.
module cvs_audio_samples (
    input wire clk, reset,
    input wire [7:0] dac8,
    input wire [3:0] dac4,
    output reg sample_ce,
    output reg signed [15:0] pcm8, pcm4
);
    reg [25:0] accumulator;
    wire [26:0] next_sum={1'b0,accumulator}+27'd48000;
    always @(posedge clk) begin
        if(reset)begin
            accumulator<=26'd0;sample_ce<=1'b0;pcm8<=16'sd0;pcm4<=16'sd0;
        end else begin
            sample_ce<=1'b0;
            if(next_sum>=27'd57272724)begin
                accumulator<=26'(next_sum-27'd57272724);
                sample_ce<=1'b1;
                pcm8<={~dac8[7],dac8[6:0],8'd0};
                pcm4<={~dac4[3],dac4[2:0],12'd0};
            end else accumulator<=next_sum[25:0];
        end
    end
endmodule
