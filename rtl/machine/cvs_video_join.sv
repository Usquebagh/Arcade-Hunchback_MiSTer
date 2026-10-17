// SPDX-License-Identifier: BSD-3-Clause
// Joined normalized PVI/character boundary; physical CVS phases are pending.
module cvs_video_join (
    input wire clk, reset, pixel_ce, visible,
    input wire [7:0] pixel_x, pixel_y, scroll,
    input wire [1:0] char_mode,
    input wire vrst, line_start, hsync_in, vsync_in,
    input wire [2:0] intack, chip_select,
    input wire cpu_rd, cpu_wr,
    input wire [7:0] cpu_addr, cpu_din,
    output wire [7:0] cpu_dout,
    output wire [2:0] irq,
    output wire [11:0] object_masks,
    output wire hsync_n, vsync_n,
    input wire collision_clear,
    input wire dl_wr,
    input wire [12:0] dl_addr,
    input wire [7:0] dl_data,
    output wire video_tile_rd,
    output wire [9:0] video_tile_addr,
    output wire [7:0] video_bullet_addr,
    input wire [7:0] video_code, video_attr, video_bullet,
    output wire video_glyph_rd,
    output wire [9:0] video_glyph_addr,
    input wire [23:0] video_glyph,
    output wire video_palette_rd,
    output wire [3:0] video_palette_addr,
    input wire [7:0] video_palette,
    output wire pixel_valid, display_enable,
    output wire [7:0] out_x, out_y, red, green, blue,
    output wire [2:0] raw_pixel,
    output wire [3:0] palette_index,
    output wire bullet_present, background_collision,
    output wire [7:0] collision_events, collision
);

    wire [11:0] sprites;
    reg pending, visible_pending;
    reg [7:0] x_pending, y_pending, scroll_pending;
    reg [1:0] mode_pending;
    reg [5:0] hs_delay, vs_delay;
    always @(posedge clk) begin
        if(reset) begin
            pending<=0;hs_delay<=6'b111111;vs_delay<=6'b111111;
        end else begin
            pending<=pixel_ce;
            hs_delay<={hs_delay[4:0],hsync_in};vs_delay<={vs_delay[4:0],vsync_in};
            if(pixel_ce) begin
                x_pending<=pixel_x;y_pending<=pixel_y;visible_pending<=visible;
                mode_pending<=char_mode;scroll_pending<=scroll;
            end
        end
    end
    assign hsync_n=hs_delay[5];assign vsync_n=vs_delay[5];
    // MAME calls set_offsets(-5,-26); the S2636 API takes (Y,X), so its
    // offsets are Y=-5 and X=-26. This raster's
    // PVI counter starts at VRST fall (y=0), eight lines before that viewport,
    // so translate the effective offset: -5 + 8 = +3. Do not consume object
    // rows during the eight lines suppressed by the composed viewport.
    cvs_s2636_bank #(.Y_OFFSET(3),.X_OFFSET(-26)) pvis(.clk(clk),.reset(reset),.chip_select(chip_select),.cpu_rd(cpu_rd),.cpu_wr(cpu_wr),
        .cpu_addr(cpu_addr),.cpu_din(cpu_din),.cpu_dout(cpu_dout),.vrst(vrst),.line_start(line_start),
        .ce_pixel(pixel_ce),.pixel_x(pixel_x),.intack(intack),.irq(irq),.pixels(sprites),.object_masks(object_masks));
    cvs_character_video characters(.clk(clk),.reset(reset),.pixel_ce(pending),.visible(visible_pending),
        .pixel_x(x_pending),.pixel_y(y_pending),.scroll(scroll_pending),.char_mode(mode_pending),.sprites(sprites),
        .collision_clear(collision_clear),.dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),
        .video_tile_rd(video_tile_rd),.video_tile_addr(video_tile_addr),.video_bullet_addr(video_bullet_addr),
        .video_code(video_code),.video_attr(video_attr),.video_bullet(video_bullet),
        .video_glyph_rd(video_glyph_rd),.video_glyph_addr(video_glyph_addr),.video_glyph(video_glyph),
        .video_palette_rd(video_palette_rd),.video_palette_addr(video_palette_addr),.video_palette(video_palette),
        .pixel_valid(pixel_valid),.display_enable(display_enable),.out_x(out_x),.out_y(out_y),
        .red(red),.green(green),.blue(blue),
        .raw_pixel(raw_pixel),.palette_index(palette_index),.bullet_present(bullet_present),
        .background_collision(background_collision),.collision_events(collision_events),.collision(collision));
endmodule
