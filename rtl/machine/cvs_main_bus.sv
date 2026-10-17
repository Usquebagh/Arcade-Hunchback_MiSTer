// SPDX-License-Identifier: BSD-3-Clause
// Accepted reads have one master-edge latency, held until another read.
module cvs_main_bus (
    input wire clk, reset, ready,
    input wire req, wr, memory_space, extended, data_port, flag,
    input wire [14:0] address,
    input wire [7:0] din,
    input wire cheat_reset,
    input wire [128:0] cheat_code,
    output wire ack,
    output wire [7:0] dout,
    input wire dl_wr,
    input wire [14:0] dl_addr,
    input wire [7:0] dl_data,
    input wire [7:0] in0, in1, in2, in3, dsw1, dsw2, collision,
    output wire [1:0] char_page, char_mode,
    output wire [7:0] scroll, video_fx, audio_command,
    output wire collision_clear, audio_trigger,
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
    output wire sprite_rd, sprite_wr,
    output wire [7:0] sprite_addr, sprite_dout
);
    assign ack = ready;
    wire accepted = req && ready;
    wire read_transfer = accepted && !wr;
    wire write_transfer = accepted && wr && !reset;
    wire [7:0] memory_data, io_data;
    reg response_io;
    always @(posedge clk) begin
        if (reset) response_io <= 1'b0;
        else if (read_transfer) response_io <= !memory_space;
    end
    wire [7:0] cheat_memory_data;
    // The shipped Pugsy Hunchback byte codes have no data-compare condition;
    // omit the optional comparator from this CPU read path for timing.
    cvs_cheat_engine #(.SUPPORTS_COMPARE(0)) cheat_engine(.clk(clk),.reset(cheat_reset),.code(cheat_code),
        .capture(read_transfer && memory_space),.address(address),
        .data_in(memory_data),.data_out(cheat_memory_data));
    assign dout = response_io ? io_data : cheat_memory_data;
    cvs_main_memory memory_boundary(.clk(clk),.cpu_addr(address),.cpu_flag(flag),
        .char_page(char_page),.cpu_rd(read_transfer && memory_space),
        .cpu_wr(write_transfer && memory_space),.cpu_din(din),.cpu_dout(memory_data),
        .dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),
        .video_tile_rd(video_tile_rd),.video_tile_addr(video_tile_addr),.video_bullet_addr(video_bullet_addr),
        .video_code(video_code),.video_attr(video_attr),.video_bullet(video_bullet),
        .video_glyph_rd(video_glyph_rd),.video_glyph_addr(video_glyph_addr),.video_glyph(video_glyph),
        .video_palette_rd(video_palette_rd),.video_palette_addr(video_palette_addr),.video_palette(video_palette),
        .sprite_din(sprite_din),
        .sprite_select(sprite_select),.sprite_rd(sprite_rd),.sprite_wr(sprite_wr),
        .sprite_addr(sprite_addr),.sprite_dout(sprite_dout));
    cvs_main_io io_boundary(.clk(clk),.reset(reset),
        .io_rd(read_transfer && !memory_space),.io_wr(write_transfer && !memory_space),
        .extended(extended),.data_port(data_port),.address(address[7:0]),.din(din),
        .dout(io_data),.in0(in0),.in1(in1),.in2(in2),.in3(in3),.dsw1(dsw1),.dsw2(dsw2),
        .collision(collision),.char_page(char_page),.char_mode(char_mode),.scroll(scroll),
        .video_fx(video_fx),.audio_command(audio_command),.collision_clear(collision_clear),
        .audio_trigger(audio_trigger));
endmodule
