// SPDX-License-Identifier: BSD-3-Clause
// Actual audio CPU and digital bus; analog/speech/machine integration pending.
module cvs_audio_cpu (
    input wire clk, reset, reset_na, ce, ready, sense,
    input wire dl_wr,
    input wire [11:0] dl_addr,
    input wire [7:0] dl_data, command,
    input wire command_trigger,
    output wire intack, irq,
    output wire [7:0] dac8,
    output wire [3:0] dac4, discrete,
    output wire dac8_wr, dac4_wr, discrete_wr,
    output wire req, wr, memory_space, extended, data_port, flag,
    output wire [14:0] address,
    output wire [7:0] write_data, read_data,
    output wire [1:0] phase
);
    wire ack;
    sgs2650 cpu(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(ce),.ack(ack),
        .req(req),.wr(wr),.mio(memory_space),.ene(extended),.dc(data_port),
        .ad(address),.dw(write_data),.dr(read_data),.ph(phase),.flag(flag),
        .\int (irq),.intack(intack),.ivec(8'h03),.sense(sense));
    cvs_audio_bus bus_boundary(.clk(clk),.reset(reset),.ready(ready),.req(req),.wr(wr),
        .memory_space(memory_space),.address(address),.din(write_data),.ack(ack),.dout(read_data),
        .dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),.command(command),
        .command_trigger(command_trigger),.intack(intack),.irq(irq),
        .dac8(dac8),.dac4(dac4),.discrete(discrete),
        .dac8_wr(dac8_wr),.dac4_wr(dac4_wr),.discrete_wr(discrete_wr));
endmodule
