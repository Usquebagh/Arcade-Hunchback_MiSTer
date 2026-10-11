// SPDX-License-Identifier: BSD-3-Clause
// Actual speech S2650 and digital control/ROM boundary; LPC engine pending.
module cvs_speech_cpu (
    input wire clk,reset,reset_na,ce,ready,sense,
    input wire program_dl_wr,
    input wire [10:0] program_dl_addr,
    input wire data_dl_wr,
    input wire [11:0] data_dl_addr,
    input wire [7:0] dl_data,
    input wire [6:0] command,
    input wire ctl_status,bit_req,
    output wire bit_ready,bit_valid,bit_data,
    output wire [15:0] bit_address,
    output wire [2:0] control_latches,
    output wire [3:0] ctl,
    output wire pdc,ctl_wr,pdc_wr,intack,
    output wire req,wr,memory_space,extended,data_port,flag,
    output wire [14:0] address,
    output wire [7:0] write_data,read_data,
    output wire [1:0] phase
);
    wire ack;
    sgs2650 cpu(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(ce),.ack(ack),
        .req(req),.wr(wr),.mio(memory_space),.ene(extended),.dc(data_port),
        .ad(address),.dw(write_data),.dr(read_data),.ph(phase),.flag(flag),
        .\int (1'b0),.intack(intack),.ivec(8'h03),.sense(sense));
    cvs_speech_bus bus_boundary(.clk(clk),.reset(reset),.ready(ready),.req(req),.wr(wr),
        .memory_space(memory_space),.address(address),.din(write_data),.command(command),.ctl_status(ctl_status),
        .ack(ack),.dout(read_data),.program_dl_wr(program_dl_wr),.program_dl_addr(program_dl_addr),
        .data_dl_wr(data_dl_wr),.data_dl_addr(data_dl_addr),.dl_data(dl_data),
        .control_latches(control_latches),.ctl(ctl),.pdc(pdc),.ctl_wr(ctl_wr),.pdc_wr(pdc_wr),
        .bit_req(bit_req),.bit_ready(bit_ready),.bit_valid(bit_valid),.bit_data(bit_data),.bit_address(bit_address));
endmodule
