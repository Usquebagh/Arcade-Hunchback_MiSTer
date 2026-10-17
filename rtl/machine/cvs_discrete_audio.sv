// SPDX-License-Identifier: BSD-3-Clause
// Schematic-derived digital approximation of the CVS analog sound board.
// This is not a transistor-level or calibrated model; see docs/audio-circuits.md.
module cvs_discrete_audio (
    input  wire clk,
    input  wire reset,
    input  wire sample_ce,
    input  wire [7:0] dac8,
    input  wire [3:0] dac4,
    input  wire [3:0] discrete,
    output reg signed [15:0] pcm,
    output wire ne555_square,
    output wire icl8038_square,
    output wire signed [15:0] icl8038_triangle,
    output wire [11:0] icl8038_frequency_hz,
    output wire byte_dac_to_mix,
    output wire [15:0] envelope_22_q16,
    output wire [15:0] envelope_10_q16
);
    localparam [63:0] SAMPLE_RATE = 64'd48000;
    localparam [31:0] NE555_STEP = 32'((64'd304440 * 64'd4294967296 + 64'd24000000) / (SAMPLE_RATE * 64'd1000));
    localparam [31:0] NE555_DUTY = 32'((64'd253 * 64'd4294967296) / 64'd473);
    // With no FM input, the ICL8038 sheet's timing capacitor and 270 kOhm
    // timing resistor imply about 0.33/(R*C) = 55.6 Hz. The DAC-to-FM
    // transfer is not specified well enough on the reverse-engineered sheet;
    // the 8 Hz/code sweep is an explicit engineering assumption.
    localparam [11:0] ICL_BASE_HZ = 12'd56;
    localparam [11:0] ICL_SWEEP_HZ_PER_CODE = 12'd8;
    localparam [31:0] ICL_BASE_STEP = 32'd5010795; // round(56 * 2^32 / 48000)
    localparam [27:0] ICL_CODE_STEP = 28'd715828; // round(8 * 2^32 / 48000)
    localparam [23:0] ENV_ALPHA_22_Q24 = 24'd159;
    localparam [23:0] ENV_ALPHA_10_Q24 = 24'd350;
    localparam signed [31:0] RATIO_TRI_Q15  = 32'sd5699; // 4.7k / 27k
    localparam signed [31:0] RATIO_SQUARE_Q15 = 32'sd1026; // 4.7k / 150k
    localparam signed [31:0] RATIO_555_Q15 = 32'sd6991; // 4.7k / 22k

    reg [31:0] ne555_phase;
    reg [31:0] icl_phase;
    reg [23:0] envelope_22_q24;
    reg [23:0] envelope_10_q24;
    reg [15:0] noise_lfsr;
    wire [11:0] icl_hz = ICL_BASE_HZ + (discrete[0] ? dac8 * ICL_SWEEP_HZ_PER_CODE : 12'd0);
    wire [27:0] dac8_step = {20'd0,dac8} * ICL_CODE_STEP;
    wire [31:0] icl_step = ICL_BASE_STEP + (discrete[0] ? {4'd0,dac8_step} : 32'd0);
    // Preserve the schematic's resistor ratios, then use the available
    // positive signed range for the full four-bit ladder. The previous raw
    // conductance scale plus a further divide-by-four left SP_LAT2 at only
    // about 512 counts (1.6% of full scale). Absolute analog gain is not
    // specified by the schematic, so this normalization is an explicit
    // engineering gain choice, not a calibrated board level.
    wire [14:0] nibble_weighted =
        (dac4[0] ? 15'd17057 : 15'd0) + // 12k branch, strongest
        (dac4[1] ? 15'd9303  : 15'd0) + // 22k branch
        (dac4[2] ? 15'd4355  : 15'd0) + // 47k branch
        (dac4[3] ? 15'd2046  : 15'd0); // 100k branch, weakest
    wire signed [15:0] dac4_mix = {1'b0,nibble_weighted};
    wire signed [15:0] triangle_now = icl_phase[31]
        ? $signed({1'b0,icl_phase[30:16]}) - 16'sd16384
        : 16'sd16383 - $signed({1'b0,icl_phase[30:16]});
    wire signed [15:0] square_now = icl_phase[31] ? 16'sd16384 : -16'sd16384;
    wire signed [15:0] ne555_now = ne555_square ? 16'sd16384 : -16'sd16384;
    wire signed [15:0] noise_now = noise_lfsr[0] ? 16'sd16384 : -16'sd16384;
    wire signed [15:0] byte_sample16 = $signed({~dac8[7],dac8[6:0],8'b0});
    wire signed [31:0] byte_sample = {{16{byte_sample16[15]}},byte_sample16};
    wire signed [31:0] tri_term = (triangle_now * RATIO_TRI_Q15) >>> 15;
    wire signed [31:0] square_term = (square_now * RATIO_SQUARE_Q15) >>> 15;
    wire signed [31:0] env555_level = (32'sd32767 * $signed({1'b0,envelope_22_q24[23:9]})) >>> 15;
    wire signed [31:0] envnoise_level = (32'sd32767 * $signed({1'b0,envelope_10_q24[23:9]})) >>> 15;
    wire signed [31:0] env555_term = ((ne555_now * env555_level) >>> 15) * RATIO_555_Q15 >>> 15;
    wire signed [31:0] noise_term = ((noise_now * envnoise_level) >>> 15) * RATIO_555_Q15 >>> 15;
    wire signed [31:0] byte_mix = byte_dac_to_mix ? byte_sample : 32'sd0;
    wire signed [31:0] nibble_mix = {{16{dac4_mix[15]}},dac4_mix};
    wire signed [31:0] square_mix = discrete[1] ? square_term : 32'sd0;
    wire signed [31:0] envelope_mix = discrete[2] ? env555_term : 32'sd0;
    wire signed [31:0] noise_mix = discrete[3] ? noise_term : 32'sd0;
    // Break the long multiply-and-sum path at the six independently generated
    // sources. These registers track each core clock; the 48 kHz sample edge
    // then sums their latest values, adding only one master-clock of latency.
    reg signed [31:0] byte_mix_q, nibble_mix_q, tri_term_q;
    reg signed [31:0] square_mix_q, envelope_mix_q, noise_mix_q;
    wire signed [31:0] mix_ab = byte_mix_q + nibble_mix_q;
    wire signed [31:0] mix_cd = tri_term_q + square_mix_q;
    wire signed [31:0] mix_ef = envelope_mix_q + noise_mix_q;
    wire signed [31:0] mix_sum = (mix_ab + mix_cd) + mix_ef;
    // A signed 16-bit result is representable exactly when bits 31:15 are
    // all copies of bit 15. This avoids two wide magnitude comparators on
    // the sample-to-output path while preserving signed saturation.
    wire mix_overflow = |(mix_sum[31:16] ^ {16{mix_sum[15]}});

    assign ne555_square = ne555_phase < NE555_DUTY;
    assign icl8038_square = icl_phase[31];
    assign icl8038_triangle = triangle_now;
    assign icl8038_frequency_hz = icl_hz;
    assign byte_dac_to_mix = !discrete[0];
    assign envelope_22_q16 = envelope_22_q24[23:8];
    assign envelope_10_q16 = envelope_10_q24[23:8];

    function automatic [23:0] rc_step(input [23:0] value, input [23:0] alpha, input gate);
        reg [24:0] error;
        reg [48:0] product;
        reg [23:0] change;
        begin
            if (gate) error = {1'b0,24'hffffff} - {1'b0,value};
            else      error = {1'b0,value};
            // Extend both operands: otherwise some HDL front ends size the
            // multiplication to the wider input (25 bits) before assignment.
            product = {24'd0,error} * {25'd0,alpha};
            change = 24'(product >> 24);
            if (gate) rc_step = value + change;
            else      rc_step = value - change;
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            ne555_phase <= 32'd0;
            icl_phase <= 32'd0;
            envelope_22_q24 <= 24'd0;
            envelope_10_q24 <= 24'd0;
            noise_lfsr <= 16'h1;
            pcm <= 16'sd0;
            byte_mix_q <= 32'sd0;
            nibble_mix_q <= 32'sd0;
            tri_term_q <= 32'sd0;
            square_mix_q <= 32'sd0;
            envelope_mix_q <= 32'sd0;
            noise_mix_q <= 32'sd0;
        end else begin
            byte_mix_q <= byte_mix;
            nibble_mix_q <= nibble_mix;
            tri_term_q <= tri_term;
            square_mix_q <= square_mix;
            envelope_mix_q <= envelope_mix;
            noise_mix_q <= noise_mix;
        end
        if (!reset && sample_ce) begin
            ne555_phase <= ne555_phase + NE555_STEP;
            icl_phase <= icl_phase + icl_step;
            envelope_22_q24 <= rc_step(envelope_22_q24, ENV_ALPHA_22_Q24, discrete[2]);
            envelope_10_q24 <= rc_step(envelope_10_q24, ENV_ALPHA_10_Q24, discrete[3]);
            noise_lfsr <= {noise_lfsr[14:0],noise_lfsr[15]^noise_lfsr[13]^noise_lfsr[12]^noise_lfsr[10]};
            if (mix_overflow) pcm <= mix_sum[31] ? 16'sh8000 : 16'sh7fff;
            else pcm <= mix_sum[15:0];
        end
    end
endmodule
