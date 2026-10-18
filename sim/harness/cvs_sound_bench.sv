// SPDX-License-Identifier: BSD-3-Clause
// Stage 1: actual audio section; command writes replace only the main CPU.
module cvs_sound_bench (
    input wire clk, reset, reset_na,
    input wire dl_wr,
    input wire [15:0] dl_addr,
    input wire [7:0] dl_data,
    input wire command_wr,
    input wire [7:0] command_data,
    output reg [7:0] command,
    output reg trigger,
    output wire audio_ce, irq, intack, ii,
    output wire req, wr, memory_space,
    output wire [14:0] address,
    output wire [7:0] write_data,
    output wire sample_ce,
    output wire signed [15:0] pcm8, pcm4, audio_pcm
);
    wire unused_main_ce, unused_audio_ce, unused_main_step;
    cvs_clock clocks(.clk(clk),.reset(reset),.ce_main(unused_main_ce),
        .ce_audio(unused_audio_ce),.ce_main_step(unused_main_step),.ce_audio_step(audio_ce));

    reg [16:0] sense_divider;
    reg sense_380;
    always @(posedge clk) begin
        if(reset) begin sense_divider<=0;sense_380<=0;end
        else if(sense_divider==17'd75359) begin sense_divider<=0;sense_380<=~sense_380;end
        else sense_divider<=sense_divider+17'd1;
        trigger<=1'b0;
        if(reset) command<=8'd0;
        else if(command_wr) begin
            command<=command_data;
            trigger<=!command[7] && command_data[7];
        end
    end

    wire [7:0] dac8, unused_read_data;
    wire [3:0] dac4, discrete;
    wire unused_sample, unused_dac8_wr, unused_dac4_wr, unused_discrete_wr;
    wire unused_extended, unused_data_port, unused_flag;
    wire [1:0] unused_phase;
    cvs_audio_cpu audio(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(audio_ce),
        .ready(1'b1),.sense(sense_380),
        .dl_wr(dl_wr && dl_addr>=16'h8000 && dl_addr<16'h9000),
        .dl_addr(dl_addr[11:0]),.dl_data(dl_data),
        .command(command),.command_trigger(trigger),.intack(intack),.irq(irq),
        .interrupt_inhibit(ii),.interrupt_sample(unused_sample),
        .dac8(dac8),.dac4(dac4),.discrete(discrete),
        .dac8_wr(unused_dac8_wr),.dac4_wr(unused_dac4_wr),.discrete_wr(unused_discrete_wr),
        .req(req),.wr(wr),.memory_space(memory_space),.extended(unused_extended),
        .data_port(unused_data_port),.flag(unused_flag),.address(address),
        .write_data(write_data),.read_data(unused_read_data),.phase(unused_phase));
    cvs_audio_samples samples(.clk(clk),.reset(reset),.dac8(dac8),.dac4(dac4),
        .sample_ce(sample_ce),.pcm8(pcm8),.pcm4(pcm4));

    wire signed [15:0] discrete_pcm, unused_triangle;
    wire unused_ne555, unused_icl, unused_byte_mix;
    wire [11:0] unused_frequency;
    wire [15:0] unused_envelope22, unused_envelope10;
    cvs_discrete_audio discrete_audio(.clk(clk),.reset(reset),.sample_ce(sample_ce),
        .dac8(dac8),.dac4(dac4),.discrete(discrete),.pcm(discrete_pcm),
        .ne555_square(unused_ne555),.icl8038_square(unused_icl),.icl8038_triangle(unused_triangle),
        .icl8038_frequency_hz(unused_frequency),.byte_dac_to_mix(unused_byte_mix),
        .envelope_22_q16(unused_envelope22),.envelope_10_q16(unused_envelope10));
    cvs_audio_output audio_output(.clk(clk),.reset(reset),.sample_ce(sample_ce),
        .speech_pcm(16'sd0),.discrete_pcm(discrete_pcm),.audio_pcm(audio_pcm));
endmodule
