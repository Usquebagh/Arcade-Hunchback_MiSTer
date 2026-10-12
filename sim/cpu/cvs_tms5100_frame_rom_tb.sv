// SPDX-License-Identifier: BSD-3-Clause
// Real serial memory boundary and frame parser; CPU pointer writes are stimuli.
module cvs_tms5100_frame_rom_tb (
    input wire clk,reset,frame_req,cpu_req,cpu_ready,
    input wire [14:0] cpu_address,
    input wire [7:0] cpu_data,
    input wire data_dl_wr,
    input wire [11:0] data_dl_addr,
    input wire [7:0] dl_data,
    output wire frame_ready,busy,frame_valid,protocol_error,
    output wire [3:0] energy_index,
    output wire [4:0] pitch_index,
    output wire repeat_frame,unvoiced_mask,stop_frame,
    output wire [49:0] coefficient_indices,
    output wire serial_req,serial_ready,serial_valid,serial_bit,
    output wire [15:0] bit_address,
    output wire cpu_ack,
    output wire [7:0] cpu_read_data,
    output wire [2:0] control_latches,
    output wire [3:0] ctl,
    output wire pdc,ctl_wr,pdc_wr
);
    cvs_speech_bus rom_boundary(.clk(clk),.reset(reset),.ready(cpu_ready),
        .req(cpu_req),.wr(1'b1),.memory_space(1'b1),.address(cpu_address),.din(cpu_data),
        .command(7'd0),.ctl_status(1'b0),.ack(cpu_ack),.dout(cpu_read_data),
        .program_dl_wr(1'b0),.program_dl_addr(11'd0),.data_dl_wr(data_dl_wr),
        .data_dl_addr(data_dl_addr),.dl_data(dl_data),.control_latches(control_latches),
        .ctl(ctl),.pdc(pdc),.ctl_wr(ctl_wr),.pdc_wr(pdc_wr),.bit_req(serial_req),
        .bit_ready(serial_ready),.bit_valid(serial_valid),.bit_data(serial_bit),.bit_address(bit_address));
    cvs_tms5100_frames frame_parser(.clk(clk),.reset(reset),.clear(1'b0),
        .frame_req(frame_req),.frame_ready(frame_ready),.busy(busy),.bit_req(serial_req),
        .bit_ready(serial_ready),.bit_valid(serial_valid),
        .bit_data(serial_bit),.frame_valid(frame_valid),.protocol_error(protocol_error),
        .energy_index(energy_index),.pitch_index(pitch_index),.repeat_frame(repeat_frame),
        .unvoiced_mask(unvoiced_mask),.stop_frame(stop_frame),.coefficient_indices(coefficient_indices));
endmodule
