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
    output wire [7:0] cpu_dout,
    input wire video_tile_rd,
    input wire [9:0] video_tile_addr,
    input wire [7:0] video_bullet_addr,
    output wire [7:0] video_code, video_attr, video_bullet,
    input wire video_glyph_rd,
    input wire [9:0] video_glyph_addr,
    output wire [23:0] video_glyph,
    input wire video_palette_rd,
    input wire [3:0] video_palette_addr,
    output wire [7:0] video_palette,
    input wire [7:0] sprite_din,
    output wire [2:0] sprite_select,
    output wire sprite_rd,
    output wire sprite_wr,
    output wire [7:0] sprite_addr,
    output wire [7:0] sprite_dout
);
    wire selected = cpu_addr[12:10] == 3'b101 || cpu_addr[12:10] == 3'b110;
    wire sprite_window = selected && !cpu_flag && cpu_addr[12:8] < 5'h18 && cpu_addr[9:8] != 2'd0;
    assign sprite_select = sprite_window && (cpu_rd || cpu_wr) ?
                           (3'b100 >> (cpu_addr[9:8] - 2'd1)) : 3'b000;
    assign sprite_rd = sprite_window && cpu_rd;
    assign sprite_wr = sprite_window && cpu_wr;
    assign sprite_addr = cpu_addr[7:0];
    assign sprite_dout = cpu_din;

    wire [9:0] char_addr = {char_page,cpu_addr[7:0]};
    wire write_bullet = cpu_wr && selected && !cpu_flag && cpu_addr[12:8]==5'h14;
    wire write_palette = cpu_wr && selected && cpu_flag && cpu_addr[12:8]==5'h14;
    wire write_screen = cpu_wr && cpu_flag && cpu_addr[12:10]==3'b110;
    wire write_attr = cpu_wr && !cpu_flag && cpu_addr[12:10]==3'b110;
    wire write_char2 = cpu_wr && cpu_flag && cpu_addr[12:8]==5'h15;
    wire write_char1 = cpu_wr && cpu_flag && cpu_addr[12:8]==5'h16;
    wire write_char0 = cpu_wr && cpu_flag && cpu_addr[12:8]==5'h17;

    wire cpu_video_read = cpu_rd && !cpu_wr && selected && cpu_addr[12:10]==3'b110;
    wire cpu_banked_read = cpu_rd && !cpu_wr && selected && cpu_addr[12:10]==3'b101 &&
                           !sprite_window && cpu_addr[9:8]==2'd0;
    wire cpu_screen_read = cpu_video_read && cpu_flag;
    wire cpu_attr_read = cpu_video_read && !cpu_flag;
    wire cpu_palette_read = cpu_banked_read && cpu_flag;
    wire cpu_bullet_read = cpu_banked_read && !cpu_flag;
    wire cpu_char2_read = cpu_rd && !cpu_wr && selected && cpu_flag &&
                          cpu_addr[12:10]==3'b101 && cpu_addr[9:8]==2'd1;
    wire cpu_char1_read = cpu_rd && !cpu_wr && selected && cpu_flag &&
                          cpu_addr[12:10]==3'b101 && cpu_addr[9:8]==2'd2;
    wire cpu_char0_read = cpu_rd && !cpu_wr && selected && cpu_flag &&
                          cpu_addr[12:10]==3'b101 && cpu_addr[9:8]==2'd3;

    wire [7:0] screen_cpu_q, attr_cpu_q, bullet_cpu_q, palette_cpu_q;
    wire [7:0] char0_cpu_q, char1_cpu_q, char2_cpu_q;
    wire [7:0] screen_video_q, attr_video_q, bullet_video_q, palette_video_q;
    wire [7:0] char0_video_q, char1_video_q, char2_video_q;

    cvs_sync_ram_2p #(.ADDR_WIDTH(10),.DEPTH(1024)) screen_ram (
        .clk(clk),.a_write(write_screen),.a_address(cpu_addr[9:0]),.a_data(cpu_din),
        .a_read(cpu_screen_read),.a_q(screen_cpu_q),.b_read(video_tile_rd),
        .b_address(video_tile_addr),.b_q(screen_video_q));
    cvs_sync_ram_2p #(.ADDR_WIDTH(10),.DEPTH(1024)) attr_ram (
        .clk(clk),.a_write(write_attr),.a_address(cpu_addr[9:0]),.a_data(cpu_din),
        .a_read(cpu_attr_read),.a_q(attr_cpu_q),.b_read(video_tile_rd),
        .b_address(video_tile_addr),.b_q(attr_video_q));
    cvs_sync_ram_2p #(.ADDR_WIDTH(8),.DEPTH(256)) bullet_ram (
        .clk(clk),.a_write(write_bullet),.a_address(cpu_addr[7:0]),.a_data(cpu_din),
        .a_read(cpu_bullet_read),.a_q(bullet_cpu_q),.b_read(video_tile_rd),
        .b_address(video_bullet_addr),.b_q(bullet_video_q));
    cvs_sync_ram_2p #(.ADDR_WIDTH(4),.DEPTH(16)) palette_ram (
        .clk(clk),.a_write(write_palette),.a_address(cpu_addr[3:0]),.a_data(cpu_din),
        .a_read(cpu_palette_read),.a_q(palette_cpu_q),.b_read(video_palette_rd),
        .b_address(video_palette_addr),.b_q(palette_video_q));
    cvs_sync_ram_2p #(.ADDR_WIDTH(10),.DEPTH(1024)) char0_ram (
        .clk(clk),.a_write(write_char0),.a_address(char_addr),.a_data(cpu_din),
        .a_read(cpu_char0_read),.a_q(char0_cpu_q),.b_read(video_glyph_rd),
        .b_address(video_glyph_addr),.b_q(char0_video_q));
    cvs_sync_ram_2p #(.ADDR_WIDTH(10),.DEPTH(1024)) char1_ram (
        .clk(clk),.a_write(write_char1),.a_address(char_addr),.a_data(cpu_din),
        .a_read(cpu_char1_read),.a_q(char1_cpu_q),.b_read(video_glyph_rd),
        .b_address(video_glyph_addr),.b_q(char1_video_q));
    cvs_sync_ram_2p #(.ADDR_WIDTH(10),.DEPTH(1024)) char2_ram (
        .clk(clk),.a_write(write_char2),.a_address(char_addr),.a_data(cpu_din),
        .a_read(cpu_char2_read),.a_q(char2_cpu_q),.b_read(video_glyph_rd),
        .b_address(video_glyph_addr),.b_q(char2_video_q));

    reg [2:0] cpu_result_kind;
    reg [7:0] cpu_special_q;
    localparam [2:0] CPU_SPECIAL=3'd0, CPU_SCREEN=3'd1, CPU_ATTR=3'd2,
                     CPU_PALETTE=3'd3, CPU_BULLET=3'd4, CPU_CHAR2=3'd5,
                     CPU_CHAR1=3'd6, CPU_CHAR0=3'd7;
    always @(posedge clk) begin
        if (cpu_rd) begin
            if (!selected) begin
                cpu_result_kind <= CPU_SPECIAL;
                cpu_special_q <= 8'hff;
            end else if (cpu_addr[12:10]==3'b110) begin
                if (cpu_wr) begin
                    cpu_result_kind <= CPU_SPECIAL;
                    cpu_special_q <= cpu_din;
                end else if (cpu_flag) cpu_result_kind <= CPU_SCREEN;
                else cpu_result_kind <= CPU_ATTR;
            end else if (sprite_window) begin
                cpu_result_kind <= CPU_SPECIAL;
                cpu_special_q <= sprite_din;
            end else if (cpu_wr) begin
                cpu_result_kind <= CPU_SPECIAL;
                cpu_special_q <= cpu_din;
            end else case (cpu_addr[9:8])
                2'd0: if (cpu_flag) cpu_result_kind <= CPU_PALETTE;
                       else cpu_result_kind <= CPU_BULLET;
                2'd1: cpu_result_kind <= CPU_CHAR2;
                2'd2: cpu_result_kind <= CPU_CHAR1;
                2'd3: cpu_result_kind <= CPU_CHAR0;
            endcase
        end
    end
    assign cpu_dout = cpu_result_kind==CPU_SCREEN ? screen_cpu_q :
                      cpu_result_kind==CPU_ATTR ? attr_cpu_q :
                      cpu_result_kind==CPU_PALETTE ? palette_cpu_q :
                      cpu_result_kind==CPU_BULLET ? bullet_cpu_q :
                      cpu_result_kind==CPU_CHAR2 ? char2_cpu_q :
                      cpu_result_kind==CPU_CHAR1 ? char1_cpu_q :
                      cpu_result_kind==CPU_CHAR0 ? char0_cpu_q : cpu_special_q;

    reg video_code_forward_q, video_attr_forward_q, video_bullet_forward_q;
    reg video_palette_forward_q;
    reg [2:0] video_glyph_forward_q;
    reg [7:0] video_tile_forward_data_q, video_glyph_forward_data_q;
    reg [7:0] video_palette_forward_data_q;
    always @(posedge clk) begin
        if (video_tile_rd) begin
            video_code_forward_q <= write_screen && cpu_addr[9:0]==video_tile_addr;
            video_attr_forward_q <= write_attr && cpu_addr[9:0]==video_tile_addr;
            video_bullet_forward_q <= write_bullet && cpu_addr[7:0]==video_bullet_addr;
            if ((write_screen && cpu_addr[9:0]==video_tile_addr) ||
                (write_attr && cpu_addr[9:0]==video_tile_addr) ||
                (write_bullet && cpu_addr[7:0]==video_bullet_addr))
                video_tile_forward_data_q <= cpu_din;
        end
        if (video_glyph_rd) begin
            video_glyph_forward_q[0] <= write_char0 && char_addr==video_glyph_addr;
            video_glyph_forward_q[1] <= write_char1 && char_addr==video_glyph_addr;
            video_glyph_forward_q[2] <= write_char2 && char_addr==video_glyph_addr;
            if ((write_char0 && char_addr==video_glyph_addr) ||
                (write_char1 && char_addr==video_glyph_addr) ||
                (write_char2 && char_addr==video_glyph_addr))
                video_glyph_forward_data_q <= cpu_din;
        end
        if (video_palette_rd) begin
            video_palette_forward_q <= write_palette && cpu_addr[3:0]==video_palette_addr;
            if (write_palette && cpu_addr[3:0]==video_palette_addr)
                video_palette_forward_data_q <= cpu_din;
        end
    end

    assign video_code = video_code_forward_q ? video_tile_forward_data_q : screen_video_q;
    assign video_attr = video_attr_forward_q ? video_tile_forward_data_q : attr_video_q;
    assign video_bullet = video_bullet_forward_q ? video_tile_forward_data_q : bullet_video_q;
    assign video_glyph[7:0] = video_glyph_forward_q[0] ? video_glyph_forward_data_q : char0_video_q;
    assign video_glyph[15:8] = video_glyph_forward_q[1] ? video_glyph_forward_data_q : char1_video_q;
    assign video_glyph[23:16] = video_glyph_forward_q[2] ? video_glyph_forward_data_q : char2_video_q;
    assign video_palette = video_palette_forward_q ? video_palette_forward_data_q : palette_video_q;
endmodule
