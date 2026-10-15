// SPDX-License-Identifier: BSD-3-Clause
// Actual connected engine and serial ROM; normalized CTL/sample ticks are stimuli.
module cvs_tms5100_engine_rom_tb (
    input wire clk,reset,sample_tick,pdc,cpu_req,cpu_ready,serial_enable,
    input wire [3:0] ctl,
    input wire [14:0] cpu_address,
    input wire [7:0] cpu_data,
    input wire data_dl_wr,
    input wire [11:0] data_dl_addr,
    input wire [7:0] dl_data,
    output wire [3:0] ctl_read,
    output wire ctl_output,talk_status,sample_valid,protocol_error,
    output wire signed [15:0] pcm,
    output wire decoded_frame,
    output wire [3:0] energy_index,
    output wire [4:0] pitch_index,
    output wire [49:0] coefficient_indices,
    output wire parameter_valid,active_sample,
    output wire [6:0] parameter_energy,
    output wire [7:0] parameter_pitch,
    output wire [99:0] parameter_coefficients,
    output wire signed [7:0] excitation,
    output wire [2:0] interpolation_period,
    output wire [3:0] parameter_counter,
    output wire [1:0] subcycle,
    output wire [12:0] rng,
    output wire [8:0] pitch_count,
    output wire bit_req,bit_ready,bit_valid,bit_data,
    output wire [15:0] bit_address,
    output wire cpu_ack,
    output wire [7:0] cpu_read_data,
    output wire [2:0] bus_latches,
    output wire [3:0] bus_ctl,
    output wire bus_pdc,bus_ctl_wr,bus_pdc_wr
);
    cvs_tms5100_engine engine(.*);
    wire boundary_ready;
    assign bit_ready=boundary_ready && serial_enable;
    cvs_speech_bus rom_boundary(.clk(clk),.reset(reset),.ready(cpu_ready),
        .req(cpu_req),.wr(1'b1),.memory_space(1'b1),.address(cpu_address),.din(cpu_data),
        .command(7'd0),.ctl_status(1'b0),.ack(cpu_ack),.dout(cpu_read_data),
        .program_dl_wr(1'b0),.program_dl_addr(11'd0),.data_dl_wr(data_dl_wr),
        .data_dl_addr(data_dl_addr),.dl_data(dl_data),.control_latches(bus_latches),
        .ctl(bus_ctl),.pdc(bus_pdc),.ctl_wr(bus_ctl_wr),.pdc_wr(bus_pdc_wr),.bit_req(bit_req && serial_enable),
        .bit_ready(boundary_ready),.bit_valid(bit_valid),.bit_data(bit_data),.bit_address(bit_address));
endmodule
