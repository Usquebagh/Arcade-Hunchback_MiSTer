// SPDX-License-Identifier: BSD-3-Clause
// Digital MAME compatibility boundary; physical latch-bit/alias audit pending.
module cvs_audio_bus (
    input wire clk, reset, ready,
    input wire req, wr, memory_space,
    input wire [14:0] address,
    input wire [7:0] din,
    output wire ack,
    output reg [7:0] dout,
    input wire dl_wr,
    input wire [11:0] dl_addr,
    input wire [7:0] dl_data,
    input wire [7:0] command,
    input wire command_trigger, intack,
    output reg irq,
    output reg [7:0] dac8,
    output reg [3:0] dac4, discrete,
    output reg dac8_wr, dac4_wr, discrete_wr
);
    reg [7:0] program_rom [0:4095];
    reg [7:0] work_ram [0:127];
    reg previous_ack;
    wire accepted = req && ready;
    wire write_transfer = accepted && wr && memory_space && !reset;
    wire ram_selected = address>=15'h1000 && address<15'h1080;
    assign ack = ready;
    always @(posedge clk) begin
        if (dl_wr) program_rom[dl_addr] <= dl_data;
        if (write_transfer && ram_selected) work_ram[address[6:0]] <= din;
        if (accepted && !wr) begin
            if (!memory_space) dout <= 8'hff;
            else if (address<15'h1000)
                dout <= dl_wr && dl_addr==address[11:0] ? dl_data : program_rom[address[11:0]];
            else if (ram_selected) dout <= work_ram[address[6:0]];
            else if (address==15'h1800) dout <= command;
            else dout <= 8'hff;
        end
        dac8_wr<=1'b0;dac4_wr<=1'b0;discrete_wr<=1'b0;
        if (reset) begin
            previous_ack<=1'b0;irq<=1'b0;
            dac8<=8'd0;dac4<=4'd0;discrete<=4'd0;
        end else begin
            previous_ack<=intack;
            if (command_trigger) irq<=1'b1;
            else if (intack && !previous_ack) irq<=1'b0;
            if (write_transfer) begin
                if (address==15'h1840) begin dac8<=din;dac8_wr<=1'b1;end
                else if (address>=15'h1880 && address<=15'h1883) begin
                    dac4[address[1:0]]<=din[7];dac4_wr<=1'b1;
                end else if (address>=15'h1884 && address<=15'h1887) begin
                    discrete[address[1:0]]<=din[0];discrete_wr<=1'b1;
                end
            end
        end
    end
endmodule
