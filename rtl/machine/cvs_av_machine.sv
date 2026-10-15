// SPDX-License-Identifier: BSD-3-Clause
// Provisional shared-master assembly; analog, speech and physical CDC pending.
module cvs_av_machine (
    input wire clk, reset, reset_na, video_reset, scan_run, ready,
    input wire audio_ready, audio_sense,
    input wire dl_wr,
    input wire [15:0] dl_addr,
    input wire [7:0] dl_data,
    input wire [7:0] in0, in1, in2, in3, dsw1, dsw2,
    output wire pixel_valid, pixel_ce_all, display_enable,
    output wire [7:0] out_x, out_y, red, green, blue,
    output wire [2:0] raw_pixel, pvi_irq,
    output wire [3:0] palette_index,
    output wire bullet_present, background_collision, hsync_n, vsync_n,
    output wire [7:0] collision_events, collision, video_fx, audio_command,
    output wire audio_trigger, intack,
    output wire req, wr, memory_space, extended, data_port, flag,
    output wire [14:0] address,
    output wire [7:0] write_data, read_data,
    output wire [1:0] phase,
    output wire [7:0] h_count,
    output wire [8:0] v_count,
    output wire audio_intack, audio_irq,
    output wire [7:0] dac8,
    output wire [3:0] dac4, discrete,
    output wire dac8_wr, dac4_wr, discrete_wr,
    output wire audio_req, audio_wr, audio_memory_space, audio_extended, audio_data_port, audio_flag,
    output wire [14:0] audio_address,
    output wire [7:0] audio_write_data, audio_read_data,
    output wire [1:0] audio_phase,
    output wire sample_ce,
    output wire signed [15:0] pcm8, pcm4
);
    // Preserve the independently checked main/video assembly and debug ports.
    cvs_machine main_video(.*);
    wire audio_ce,unused_main_ce,unused_audio_ce,unused_main_step;
    // Same reset/master contract as main_video. Separate board clocks are not
    // modeled by this synchronous implementation; SENSE stays external.
    cvs_clock audio_clocks(.clk(clk),.reset(reset),.ce_main(unused_main_ce),
        .ce_audio(unused_audio_ce),.ce_main_step(unused_main_step),.ce_audio_step(audio_ce));
    cvs_audio_cpu audio(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(audio_ce),
        .ready(audio_ready),.sense(audio_sense),
        .dl_wr(dl_wr && dl_addr>=16'h8000 && dl_addr<16'h9000),
        .dl_addr(dl_addr[11:0]),.dl_data(dl_data),
        .command(audio_command),.command_trigger(audio_trigger),
        .intack(audio_intack),.irq(audio_irq),.dac8(dac8),.dac4(dac4),.discrete(discrete),
        .dac8_wr(dac8_wr),.dac4_wr(dac4_wr),.discrete_wr(discrete_wr),
        .req(audio_req),.wr(audio_wr),.memory_space(audio_memory_space),
        .extended(audio_extended),.data_port(audio_data_port),.flag(audio_flag),
        .address(audio_address),.write_data(audio_write_data),.read_data(audio_read_data),.phase(audio_phase));
    cvs_audio_samples samples(.clk(clk),.reset(reset),.dac8(dac8),.dac4(dac4),
        .sample_ce(sample_ce),.pcm8(pcm8),.pcm4(pcm4));
endmodule
