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
    output wire [7:0] cpu_dout,
    input wire dl_wr,
    input wire [14:0] dl_addr,
    input wire [7:0] dl_data
);
    wire rom_selected = cpu_addr[12:0] < 13'h1400;
    wire ram_selected = cpu_addr[12:10] == 3'b111;
    wire rom_collision = dl_wr && dl_addr == cpu_addr;
    wire [7:0] rom_q, ram_q;
    wire rom_read = cpu_rd && rom_selected && !rom_collision;
    wire ram_read = cpu_rd && ram_selected && !cpu_wr;
    reg [1:0] response_q;
    reg [7:0] response_data_q;

    cvs_sync_rom #(.ADDR_WIDTH(15), .DEPTH(32768)) program_rom (
        .clk(clk), .write_enable(dl_wr), .write_address(dl_addr), .write_data(dl_data),
        .read_enable(rom_read), .read_address(cpu_addr), .read_data(rom_q));
    cvs_sync_ram_1p #(.ADDR_WIDTH(10), .DEPTH(1024)) system_ram (
        .clk(clk), .write_enable(cpu_wr && ram_selected), .address(cpu_addr[9:0]),
        .write_data(cpu_din), .read_enable(ram_read), .read_data(ram_q));

    assign cpu_dout = response_q == 2'd1 ? rom_q :
                      response_q == 2'd2 ? ram_q : response_data_q;

    always @(posedge clk) begin
        if (cpu_rd) begin
            if (rom_selected) begin
                if (rom_collision) begin
                    response_q <= 2'd0;
                    response_data_q <= dl_data;
                end else response_q <= 2'd1;
            end else if (ram_selected) begin
                if (cpu_wr) begin
                    response_q <= 2'd0;
                    response_data_q <= cpu_din;
                end else response_q <= 2'd2;
            end else begin
                response_q <= 2'd0;
                response_data_q <= 8'hff;
            end
        end
    end
endmodule
