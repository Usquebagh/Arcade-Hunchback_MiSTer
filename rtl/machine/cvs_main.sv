// SPDX-License-Identifier: BSD-3-Clause
// Main CPU assembly; physical reset/PLL/video/input/audio integration is pending.
module cvs_main (
    input wire clk, reset, reset_na, ce, ready,
    input wire irq, sense,
    input wire [7:0] ivec,
    output wire intack,
    input wire dl_wr,
    input wire [14:0] dl_addr,
    input wire [7:0] dl_data,
    input wire [7:0] in0, in1, in2, in3, dsw1, dsw2, collision,
    output wire [1:0] char_page, char_mode,
    output wire [7:0] scroll, video_fx, audio_command,
    output wire collision_clear, audio_trigger,
    input wire [7:0] sprite_din,
    output wire [2:0] sprite_select,
    output wire sprite_rd, sprite_wr,
    output wire [7:0] sprite_addr, sprite_dout,
    output wire req, wr, memory_space, extended, data_port, flag,
    output wire [14:0] address,
    output wire [7:0] write_data, read_data,
    output wire [1:0] phase
);
    wire ack;
    sgs2650 cpu(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(ce),.ack(ack),
        .req(req),.wr(wr),.mio(memory_space),.ene(extended),.dc(data_port),
        .ad(address),.dw(write_data),.dr(read_data),.ph(phase),.flag(flag),
        .\int (irq),.intack(intack),.ivec(ivec),.sense(sense));
    cvs_main_bus bus_boundary(.clk(clk),.reset(reset),.ready(ready),.ack(ack),
        .req(req),.wr(wr),.memory_space(memory_space),.extended(extended),
        .data_port(data_port),.flag(flag),.address(address),.din(write_data),.dout(read_data),
        .dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),
        .in0(in0),.in1(in1),.in2(in2),.in3(in3),.dsw1(dsw1),.dsw2(dsw2),
        .collision(collision),.char_page(char_page),.char_mode(char_mode),.scroll(scroll),
        .video_fx(video_fx),.audio_command(audio_command),.collision_clear(collision_clear),
        .audio_trigger(audio_trigger),.sprite_din(sprite_din),.sprite_select(sprite_select),
        .sprite_rd(sprite_rd),.sprite_wr(sprite_wr),.sprite_addr(sprite_addr),.sprite_dout(sprite_dout));
endmodule
