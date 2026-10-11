// SPDX-License-Identifier: BSD-3-Clause
// First boundary: main program ROM and 1 KiB system RAM only.
// FLAG-banked video/sprite/palette memory is deliberately not implemented here.
// CPU samples read data one master edge after request. Download wins a ROM
// collision; CPU writes cannot alter program ROM. RAM is not reset-cleared.
module cvs_memory (
    input wire clk,
    input wire [14:0] cpu_addr,
    input wire cpu_rd,
    input wire cpu_wr,
    input wire [7:0] cpu_din,
    output reg [7:0] cpu_dout,
    input wire dl_wr,
    input wire [14:0] dl_addr,
    input wire [7:0] dl_data
);
    reg [7:0] program_rom [0:32767];
    reg [7:0] system_ram [0:1023];
    wire rom_selected = cpu_addr[12:0] < 13'h1400;
    wire ram_selected = cpu_addr[12:10] == 3'b111;
    always @(posedge clk) begin
        if (dl_wr) program_rom[dl_addr] <= dl_data;
        if (cpu_wr && ram_selected) system_ram[cpu_addr[9:0]] <= cpu_din;
        if (cpu_rd) begin
            if (rom_selected) begin
                if (dl_wr && dl_addr == cpu_addr) cpu_dout <= dl_data;
                else cpu_dout <= program_rom[cpu_addr];
            end else if (ram_selected) begin
                // Explicit write-through for same-address RAM read/write.
                if (cpu_wr) cpu_dout <= cpu_din;
                else cpu_dout <= system_ram[cpu_addr[9:0]];
            end else cpu_dout <= 8'hff;
        end
    end
endmodule
