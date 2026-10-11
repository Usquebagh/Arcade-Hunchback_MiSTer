// SPDX-License-Identifier: BSD-3-Clause
// CVS CPU-side FLAG views. MAME-compatible map, checked against supplied PAL
// equations. Sprite register semantics and display-side arbitration are external.
module cvs_banked (
    input wire clk,
    input wire [12:0] cpu_addr,
    input wire cpu_flag,
    input wire [1:0] char_page,
    input wire cpu_rd,
    input wire cpu_wr,
    input wire [7:0] cpu_din,
    output reg [7:0] cpu_dout,
    input wire video_tile_rd,
    input wire [9:0] video_tile_addr,
    input wire [7:0] video_bullet_addr,
    output reg [7:0] video_code, video_attr, video_bullet,
    input wire video_glyph_rd,
    input wire [9:0] video_glyph_addr,
    output reg [23:0] video_glyph,
    input wire video_palette_rd,
    input wire [3:0] video_palette_addr,
    output reg [7:0] video_palette,
    input wire [7:0] sprite_din,
    output wire [2:0] sprite_select,
    output wire sprite_rd,
    output wire sprite_wr,
    output wire [7:0] sprite_addr,
    output wire [7:0] sprite_dout
);
    reg [7:0] bullet [0:255];
    reg [7:0] palette [0:15];
    reg [7:0] attributes [0:1023];
    reg [7:0] screen [0:1023];
    reg [7:0] char0 [0:1023];
    reg [7:0] char1 [0:1023];
    reg [7:0] char2 [0:1023];
    wire selected = cpu_addr[12:10] == 3'b101 || cpu_addr[12:10] == 3'b110;
    wire sprite_window = selected && !cpu_flag && cpu_addr[12:8] < 5'h18 && cpu_addr[9:8] != 2'd0;
    assign sprite_select = sprite_window && (cpu_rd || cpu_wr) ?
                           (3'b100 >> (cpu_addr[9:8] - 2'd1)) : 3'b000;
    assign sprite_rd = sprite_window && cpu_rd;
    assign sprite_wr = sprite_window && cpu_wr;
    assign sprite_addr = cpu_addr[7:0];
    assign sprite_dout = cpu_din;
    wire [9:0] char_addr = {char_page,cpu_addr[7:0]};
    // Explicit display write-through; synchronous independent read ports.
    // Quartus dual-port inference/arbitration still requires qualification.
    wire write_bullet = cpu_wr && selected && !cpu_flag && cpu_addr[12:8]==5'h14;
    wire write_palette = cpu_wr && selected && cpu_flag && cpu_addr[12:8]==5'h14;
    wire write_screen = cpu_wr && cpu_flag && cpu_addr[12:10]==3'b110;
    wire write_attr = cpu_wr && !cpu_flag && cpu_addr[12:10]==3'b110;
    always @(posedge clk) begin
        if (video_tile_rd) begin
            video_code <= write_screen && cpu_addr[9:0]==video_tile_addr ? cpu_din : screen[video_tile_addr];
            video_attr <= write_attr && cpu_addr[9:0]==video_tile_addr ? cpu_din : attributes[video_tile_addr];
            video_bullet <= write_bullet && cpu_addr[7:0]==video_bullet_addr ? cpu_din : bullet[video_bullet_addr];
        end
        if (video_glyph_rd) begin
            video_glyph[7:0] <= cpu_wr && cpu_flag && cpu_addr[12:8]==5'h17 && char_addr==video_glyph_addr ? cpu_din : char0[video_glyph_addr];
            video_glyph[15:8] <= cpu_wr && cpu_flag && cpu_addr[12:8]==5'h16 && char_addr==video_glyph_addr ? cpu_din : char1[video_glyph_addr];
            video_glyph[23:16] <= cpu_wr && cpu_flag && cpu_addr[12:8]==5'h15 && char_addr==video_glyph_addr ? cpu_din : char2[video_glyph_addr];
        end
        if (video_palette_rd)
            video_palette <= write_palette && cpu_addr[3:0]==video_palette_addr ? cpu_din : palette[video_palette_addr];
    end
    always @(posedge clk) begin
        if (cpu_wr && selected) begin
            if (cpu_addr[12:10] == 3'b110) begin
                if (cpu_flag) screen[cpu_addr[9:0]] <= cpu_din;
                else attributes[cpu_addr[9:0]] <= cpu_din;
            end else case (cpu_addr[9:8])
                2'd0: if (cpu_flag) palette[cpu_addr[3:0]] <= cpu_din;
                       else bullet[cpu_addr[7:0]] <= cpu_din;
                2'd1: if (cpu_flag) char2[char_addr] <= cpu_din;
                2'd2: if (cpu_flag) char1[char_addr] <= cpu_din;
                2'd3: if (cpu_flag) char0[char_addr] <= cpu_din;
            endcase
        end
        if (cpu_rd) begin
            if (!selected) cpu_dout <= 8'hff;
            else if (cpu_addr[12:10] == 3'b110) begin
                if (cpu_wr) cpu_dout <= cpu_din;
                else if (cpu_flag) cpu_dout <= screen[cpu_addr[9:0]];
                else cpu_dout <= attributes[cpu_addr[9:0]];
            end else if (sprite_window) cpu_dout <= sprite_din;
            else if (cpu_wr) cpu_dout <= cpu_din;
            else case (cpu_addr[9:8])
                2'd0: if (cpu_flag) cpu_dout <= palette[cpu_addr[3:0]];
                       else cpu_dout <= bullet[cpu_addr[7:0]];
                2'd1: cpu_dout <= char2[char_addr];
                2'd2: cpu_dout <= char1[char_addr];
                2'd3: cpu_dout <= char0[char_addr];
            endcase
        end
    end
endmodule
