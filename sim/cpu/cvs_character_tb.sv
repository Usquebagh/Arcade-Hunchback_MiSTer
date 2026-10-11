// SPDX-License-Identifier: BSD-3-Clause
// Real shared FLAG RAM and normalized renderer; no mock display memory.
module cvs_character_tb (
    input wire clk, reset, pixel_ce, visible, collision_clear,
    input wire [7:0] pixel_x, pixel_y, scroll,
    input wire [1:0] char_mode,
    input wire [11:0] sprites,
    input wire cpu_rd, cpu_wr, cpu_flag,
    input wire [12:0] cpu_addr,
    input wire [1:0] char_page,
    input wire [7:0] cpu_din,
    output wire [7:0] cpu_dout,
    input wire dl_wr,
    input wire [12:0] dl_addr,
    input wire [7:0] dl_data,
    output wire pixel_valid,
    output wire [7:0] out_x, out_y, red, green, blue,
    output wire [2:0] raw_pixel,
    output wire [3:0] palette_index,
    output wire bullet_present, background_collision,
    output wire [7:0] collision_events, collision
);
    wire video_tile_rd, video_glyph_rd, video_palette_rd;
    wire [9:0] video_tile_addr, video_glyph_addr;
    wire [7:0] video_bullet_addr, video_code, video_attr, video_bullet, video_palette;
    wire [3:0] video_palette_addr;
    wire [23:0] video_glyph;
    wire [2:0] unused_sprite_select;
    wire unused_sprite_rd, unused_sprite_wr;
    wire [7:0] unused_sprite_addr, unused_sprite_dout;
    cvs_banked memory_boundary(.*,.sprite_din(8'hff),.sprite_select(unused_sprite_select),
        .sprite_rd(unused_sprite_rd),.sprite_wr(unused_sprite_wr),.sprite_addr(unused_sprite_addr),.sprite_dout(unused_sprite_dout));
    cvs_character_video renderer(.*);
endmodule
