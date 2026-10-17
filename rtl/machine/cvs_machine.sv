// SPDX-License-Identifier: BSD-3-Clause
// Provisional main/video assembly, not yet MiSTer or physical-clock qualified.
module cvs_machine (
    input wire clk, reset, reset_na, video_reset, scan_run, ready,
    input wire dl_wr,
    input wire cheat_reset,
    input wire [128:0] cheat_code,
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
    output wire [8:0] v_count
);
    wire ce,irq,vrst,pixel_ce,line_start,visible,hsync_in,vsync_in;
    wire [7:0] pixel_x,pixel_y,scroll;
    wire [1:0] char_mode;
    wire [1:0] unused_char_page;
    wire unused_frame_start,unused_hrst,unused_cbf,scan_pixel_ce_all;
    wire [11:0] unused_object_masks;
    wire [2:0] chip_select;
    wire sprite_rd,sprite_wr,collision_clear;
    wire [7:0] sprite_addr,sprite_dout,sprite_din;
    wire video_tile_rd,video_glyph_rd,video_palette_rd;
    wire [9:0] video_tile_addr,video_glyph_addr;
    wire [7:0] video_bullet_addr,video_code,video_attr,video_bullet,video_palette;
    wire [3:0] video_palette_addr;
    wire [23:0] video_glyph;
    wire unused_main_ce,unused_audio_ce,unused_audio_step;
    cvs_clock clocks(.clk(clk),.reset(reset),.ce_main(unused_main_ce),.ce_audio(unused_audio_ce),
        .ce_main_step(ce),.ce_audio_step(unused_audio_step));
    cvs_scan scan(.clk(clk),.reset(video_reset),.run(scan_run),.pixel_ce(pixel_ce),.pixel_ce_all(scan_pixel_ce_all),
        .line_start(line_start),.frame_start(unused_frame_start),.vrst(vrst),.visible(visible),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.hsync_n(hsync_in),.vsync_n(vsync_in),
        .hrst(unused_hrst),.cbf(unused_cbf),.h_count(h_count),.v_count(v_count));
    cvs_vblank_irq interrupt_latch(.clk(clk),.reset(reset),.vblank(vrst),.intack(intack),.irq(irq));
    cvs_main main(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(ce),.ready(ready),
        .cheat_reset(cheat_reset),.cheat_code(cheat_code),
        .irq(irq),.sense(vrst),.ivec(8'h03),.intack(intack),
        .dl_wr(dl_wr && dl_addr<16'h8000),.dl_addr(dl_addr[14:0]),.dl_data(dl_data),
        .in0(in0),.in1(in1),.in2(in2),.in3(in3),.dsw1(dsw1),.dsw2(dsw2),
        .collision(collision),.char_page(unused_char_page),.char_mode(char_mode),.scroll(scroll),
        .video_fx(video_fx),.audio_command(audio_command),.collision_clear(collision_clear),.audio_trigger(audio_trigger),
        .video_tile_rd(video_tile_rd),.video_tile_addr(video_tile_addr),.video_bullet_addr(video_bullet_addr),
        .video_code(video_code),.video_attr(video_attr),.video_bullet(video_bullet),
        .video_glyph_rd(video_glyph_rd),.video_glyph_addr(video_glyph_addr),.video_glyph(video_glyph),
        .video_palette_rd(video_palette_rd),.video_palette_addr(video_palette_addr),.video_palette(video_palette),
        .sprite_din(sprite_din),.sprite_select(chip_select),.sprite_rd(sprite_rd),.sprite_wr(sprite_wr),
        .sprite_addr(sprite_addr),.sprite_dout(sprite_dout),.req(req),.wr(wr),.memory_space(memory_space),
        .extended(extended),.data_port(data_port),.flag(flag),.address(address),.write_data(write_data),.read_data(read_data),.phase(phase));
    cvs_video_join video(.clk(clk),.reset(video_reset),.pixel_ce(pixel_ce),.visible(visible),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.scroll(scroll),.char_mode(char_mode),.vrst(vrst),.line_start(line_start),
        .hsync_in(hsync_in),.vsync_in(vsync_in),.hsync_n(hsync_n),.vsync_n(vsync_n),
        .intack({3{intack}}),.chip_select(chip_select),.cpu_rd(sprite_rd),.cpu_wr(sprite_wr),
        .cpu_addr(sprite_addr),.cpu_din(sprite_dout),.cpu_dout(sprite_din),.irq(pvi_irq),.object_masks(unused_object_masks),
        .collision_clear(collision_clear),.dl_wr(dl_wr && dl_addr>=16'ha800 && dl_addr<16'hc800),
        .dl_addr(13'(dl_addr-16'ha800)),.dl_data(dl_data),
        .video_tile_rd(video_tile_rd),.video_tile_addr(video_tile_addr),.video_bullet_addr(video_bullet_addr),
        .video_code(video_code),.video_attr(video_attr),.video_bullet(video_bullet),
        .video_glyph_rd(video_glyph_rd),.video_glyph_addr(video_glyph_addr),.video_glyph(video_glyph),
        .video_palette_rd(video_palette_rd),.video_palette_addr(video_palette_addr),.video_palette(video_palette),
        .pixel_valid(pixel_valid),.display_enable(display_enable),.out_x(out_x),.out_y(out_y),.red(red),.green(green),.blue(blue),
        .raw_pixel(raw_pixel),.palette_index(palette_index),.bullet_present(bullet_present),
        .background_collision(background_collision),.collision_events(collision_events),.collision(collision));
    assign pixel_ce_all=scan_pixel_ce_all;
endmodule
