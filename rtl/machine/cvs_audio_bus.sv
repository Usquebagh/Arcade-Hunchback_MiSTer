// SPDX-License-Identifier: BSD-3-Clause
// Digital MAME compatibility boundary; physical latch-bit/alias audit pending.
module cvs_audio_bus (
    input wire clk, reset, ready,
    input wire req, wr, memory_space,
    input wire [14:0] address,
    input wire [7:0] din,
    output wire ack,
    output wire [7:0] dout,
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
    reg previous_ack;
    wire accepted = req && ready;
    wire write_transfer = accepted && wr && memory_space && !reset;
    wire ram_selected = address>=15'h1000 && address<15'h1080;
    wire rom_collision = dl_wr && dl_addr==address[11:0];
    wire rom_read = accepted && !wr && memory_space && address<15'h1000 && !rom_collision;
    wire ram_read = accepted && !wr && memory_space && ram_selected;
    wire [7:0] program_q, work_q;
    reg [1:0] response_kind_q;
    reg [7:0] response_data_q;

    cvs_sync_rom #(.ADDR_WIDTH(12),.DEPTH(4096)) program_rom (
        .clk(clk),.write_enable(dl_wr),.write_address(dl_addr),.write_data(dl_data),
        .read_enable(rom_read),.read_address(address[11:0]),.read_data(program_q));
    cvs_sync_ram_1p #(.ADDR_WIDTH(7),.DEPTH(128)) work_ram (
        .clk(clk),.write_enable(write_transfer && ram_selected),.address(address[6:0]),
        .write_data(din),.read_enable(ram_read),.read_data(work_q));

    assign dout = response_kind_q==2'd1 ? program_q :
                  response_kind_q==2'd2 ? work_q : response_data_q;

    assign ack = ready;
    always @(posedge clk) begin
        if (accepted && !wr) begin
            if (!memory_space) begin response_kind_q<=2'd0;response_data_q<=8'hff;end
            else if (address<15'h1000) begin
                if (rom_collision) begin response_kind_q<=2'd0;response_data_q<=dl_data;end
                else response_kind_q<=2'd1;
            end else if (ram_selected) response_kind_q<=2'd2;
            else if (address==15'h1800) begin response_kind_q<=2'd0;response_data_q<=command;end
            else begin response_kind_q<=2'd0;response_data_q<=8'hff;end
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
