// SPDX-License-Identifier: BSD-3-Clause
// Normalized software speaker-path quantization; not calibrated analog gain.
module cvs_tms5100_pcm (
    input wire signed [14:0] raw_sample,
    output reg signed [15:0] pcm_sample
);
    always @* begin
        if(raw_sample>15'sd2047)pcm_sample=16'sh7fff;
        else if(raw_sample< -15'sd2048)pcm_sample=16'sh8000;
        else pcm_sample={raw_sample[11:4],raw_sample[10:4],raw_sample[10]};
    end
endmodule
