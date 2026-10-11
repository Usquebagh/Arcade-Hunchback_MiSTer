// SPDX-License-Identifier: BSD-3-Clause
// Normalized MAME-compatible pixel pipeline; physical CVS phases are pending.
module cvs_character_video (
    input wire clk, reset, pixel_ce, visible,
    input wire [7:0] pixel_x, pixel_y, scroll,
    input wire [1:0] char_mode,
    input wire [11:0] sprites,
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
    output reg pixel_valid,
    output reg [7:0] out_x, out_y, red, green, blue,
    output reg [2:0] raw_pixel,
    output reg [3:0] palette_index,
    output reg bullet_present, background_collision,
    output reg [7:0] collision_events, collision
);
    reg [7:0] rom0 [0:2047], rom1 [0:2047], rom2 [0:2047];
    reg [2:0] lookup [0:2047];
    reg [7:0] rom_byte0, rom_byte1, rom_byte2;
    reg [2:0] lookup_pixel;
    reg v0, v1, v2, v3, visible0, visible1, visible2, visible3;
    reg [7:0] x0, x1, x2, x3, y0, y1, y2, y3;
    reg [2:0] row0, column1, raw2, raw3;
    reg [1:0] mode0;
    reg [7:0] attr1;
    reg ram1, bullet1, bullet2, bullet3, bg2, bg3;
    reg [11:0] sprites0, sprites1, sprites2;
    reg [2:0] presence3;
    reg [3:0] pen3;
    wire [7:0] source_y = pixel_x>=8'd32 && pixel_x<8'd192 ? pixel_y-scroll : pixel_y;
    assign video_tile_rd = pixel_ce && !reset;
    assign video_tile_addr = {source_y[7:3],pixel_x[7:3]};
    assign video_bullet_addr = pixel_y;
    assign video_glyph_rd = v0 && !reset;
    assign video_glyph_addr = {video_code[6:0],row0};
    assign video_palette_rd = v2 && !reset;
    wire ram_select = mode0==2'd0 ? video_code>=8'he0 :
                      mode0==2'd1 ? video_code>=8'hc0 :
                      mode0==2'd3 ? video_code>=8'h80 : 1'b0;
    wire [10:0] rom_address = {video_code,row0};
    wire [7:0] plane0 = ram1 ? video_glyph[7:0] : rom_byte0;
    wire [7:0] plane1 = ram1 ? video_glyph[15:8] : rom_byte1;
    wire [7:0] plane2 = ram1 ? video_glyph[23:16] : rom_byte2;
    wire [2:0] glyph_pixel = {plane0[3'd7-column1],plane1[3'd7-column1],plane2[3'd7-column1]};
    wire foreground = attr1[7] ? |(glyph_pixel & 3'd6) :
                      attr1[1:0]==2'd3 ? glyph_pixel[2] :
                      !attr1[0] ? glyph_pixel[1] : 1'b0;
    wire [8:0] bullet_sum = {1'b0,x0}+{1'b0,video_bullet};
    wire bullet_hit = y0>=8'd8 && video_bullet!=0 && bullet_sum>=9'd245 && bullet_sum<=9'd248;
    wire any_sprite2 = sprites2[3] || sprites2[7] || sprites2[11];
    wire [2:0] sprite_colour2 = sprites2[2:0] | sprites2[6:4] | sprites2[10:8];
    wire [3:0] pen_next = any_sprite2 ? {1'b1,sprite_colour2} :
                          bullet2 ? 4'd7 : {1'b0,lookup_pixel[0],lookup_pixel[1],lookup_pixel[2]};
    assign video_palette_addr = pen_next;
    wire [7:0] events_next = {bullet3 && bg3, presence3[2] && bg3,
        presence3[1] && bg3,presence3[0] && bg3,bullet3 && |presence3,
        presence3[0] && presence3[2],presence3[1] && presence3[2],presence3[0] && presence3[1]};
    wire [7:0] active_palette = ~video_palette;
    always @(posedge clk) begin
        if (dl_wr) begin
            case (dl_addr[12:11])
                2'd0: rom0[dl_addr[10:0]]<=dl_data;
                2'd1: rom1[dl_addr[10:0]]<=dl_data;
                2'd2: rom2[dl_addr[10:0]]<=dl_data;
                2'd3: lookup[dl_addr[10:0]]<=dl_data[2:0];
            endcase
        end
        if (reset) begin
            v0<=0;v1<=0;v2<=0;v3<=0;pixel_valid<=0;
            out_x<=0;out_y<=0;red<=0;green<=0;blue<=0;
            raw_pixel<=0;palette_index<=0;bullet_present<=0;background_collision<=0;
            collision_events<=0;collision<=0;
        end else begin
            v0<=pixel_ce;v1<=v0;v2<=v1;v3<=v2;pixel_valid<=v3;
            if (pixel_ce) begin
                x0<=pixel_x;y0<=pixel_y;row0<=source_y[2:0];mode0<=char_mode;
                sprites0<=sprites;visible0<=visible;
            end
            if (v0) begin
                x1<=x0;y1<=y0;column1<=x0[2:0];attr1<=video_attr;ram1<=ram_select;
                rom_byte0<=rom0[rom_address];rom_byte1<=rom1[rom_address];rom_byte2<=rom2[rom_address];
                bullet1<=bullet_hit;sprites1<=sprites0;visible1<=visible0;
            end
            if (v1) begin
                lookup_pixel<=lookup[{glyph_pixel,attr1}];
                raw2<=glyph_pixel;bg2<=foreground;bullet2<=bullet1;
                x2<=x1;y2<=y1;sprites2<=sprites1;visible2<=visible1;
            end
            if (v2) begin
                raw3<=raw2;bg3<=bg2;bullet3<=bullet2;pen3<=pen_next;
                x3<=x2;y3<=y2;presence3<={sprites2[11],sprites2[7],sprites2[3]};visible3<=visible2;
            end
            collision <= (collision_clear ? 8'd0 : collision) |
                         (v3 && visible3 ? events_next : 8'd0);
            if (v3) begin
                out_x<=x3;out_y<=y3;raw_pixel<=raw3;palette_index<=pen3;
                bullet_present<=visible3 && bullet3;background_collision<=visible3 && bg3;
                collision_events<=visible3 ? events_next : 8'd0;
                red<=visible3 ? {4{active_palette[1:0]}} : 8'd0;
                green<=visible3 ? {active_palette[4:2],active_palette[4:2],active_palette[4:3]} : 8'd0;
                blue<=visible3 ? {active_palette[7:5],active_palette[7:5],active_palette[7:6]} : 8'd0;
            end
        end
    end
endmodule
