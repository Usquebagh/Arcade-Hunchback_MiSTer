// SPDX-License-Identifier: BSD-3-Clause
// Keep AC coupling ahead of the final channel sum and saturation. The
// resistor/DAC path is modeled here; speech remains an independent channel.
module cvs_audio_output (
    input wire clk,
    input wire reset,
    input wire sample_ce,
    input wire signed [15:0] speech_pcm,
    input wire signed [15:0] discrete_pcm,
    output wire signed [15:0] audio_pcm
);
    wire signed [15:0] discrete_ac;
    cvs_audio_dc_blocker coupling(
        .clk(clk),.reset(reset),.sample_ce(sample_ce),
        .x(discrete_pcm),.y(discrete_ac));

    wire signed [17:0] mix_sum = {{2{speech_pcm[15]}},speech_pcm} +
                                  {{2{discrete_ac[15]}},discrete_ac};
    assign audio_pcm = mix_sum > 18'sd32767 ? 16'sh7fff :
                       mix_sum < -18'sd32768 ? 16'sh8000 : mix_sum[15:0];
endmodule
