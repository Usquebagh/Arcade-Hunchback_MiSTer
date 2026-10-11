// SPDX-License-Identifier: BSD-3-Clause
// One-edge memory boundary. Register the response selector with the read,
// so changing the next bus address/FLAG cannot switch an outstanding response.
module cvs_main_memory (
    input wire clk,
    input wire [14:0] cpu_addr,
    input wire cpu_flag,
    input wire [1:0] char_page,
    input wire cpu_rd, cpu_wr,
    input wire [7:0] cpu_din,
    output wire [7:0] cpu_dout,
    input wire dl_wr,
    input wire [14:0] dl_addr,
    input wire [7:0] dl_data,
    input wire [7:0] sprite_din,
    output wire [2:0] sprite_select,
    output wire sprite_rd, sprite_wr,
    output wire [7:0] sprite_addr, sprite_dout
);
    wire [7:0] fixed_data, banked_data;
    wire banked = cpu_addr[12:10] == 3'b101 || cpu_addr[12:10] == 3'b110;
    reg response_banked;
    always @(posedge clk) if (cpu_rd) response_banked <= banked;
    assign cpu_dout = response_banked ? banked_data : fixed_data;
    cvs_memory fixed_mem(.clk(clk),.cpu_addr(cpu_addr),.cpu_rd(cpu_rd),.cpu_wr(cpu_wr),
        .cpu_din(cpu_din),.cpu_dout(fixed_data),.dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data));
    cvs_banked banked_mem(.clk(clk),.cpu_addr(cpu_addr[12:0]),.cpu_flag(cpu_flag),.char_page(char_page),
        .cpu_rd(cpu_rd),.cpu_wr(cpu_wr),.cpu_din(cpu_din),.cpu_dout(banked_data),
        .sprite_din(sprite_din),.sprite_select(sprite_select),.sprite_rd(sprite_rd),
        .sprite_wr(sprite_wr),.sprite_addr(sprite_addr),.sprite_dout(sprite_dout));
endmodule
