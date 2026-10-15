// SPDX-License-Identifier: BSD-3-Clause
// Actual S2650/control ROMs/normalized TMC0281 engine at nominal shared clocks.
module cvs_speech_machine (
    input wire clk,reset,reset_na,ready,sense,
    input wire dl_wr,
    input wire [15:0] dl_addr,
    input wire [7:0] dl_data,
    input wire [6:0] command,
    output wire ce,sample_tick,sample_valid,protocol_error,
    output wire signed [15:0] pcm,
    output wire ctl_output,talk_status,
    output wire [3:0] ctl_read,
    output wire bit_req,bit_ready,bit_valid,bit_data,
    output wire [15:0] bit_address,
    output wire [2:0] control_latches,
    output wire [3:0] ctl,
    output wire pdc,ctl_wr,pdc_wr,intack,
    output wire req,wr,memory_space,extended,data_port,flag,
    output wire [14:0] address,
    output wire [7:0] write_data,read_data,
    output wire [1:0] phase,
    output wire decoded_frame,
    output wire [3:0] energy_index,
    output wire [4:0] pitch_index,
    output wire [49:0] coefficient_indices
);
    wire unused_main_ce,unused_audio_ce,unused_main_step;
    cvs_clock clocks(.clk(clk),.reset(reset),.ce_main(unused_main_ce),.ce_audio(unused_audio_ce),
        .ce_main_step(unused_main_step),.ce_audio_step(ce));
    cvs_tms5100_rate rate(.clk(clk),.reset(reset),.sample_tick(sample_tick));
    cvs_speech_cpu cpu_boundary(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(ce),.ready(ready),.sense(sense),
        .program_dl_wr(dl_wr && dl_addr>=16'h9000 && dl_addr<16'h9800),.program_dl_addr(dl_addr[10:0]),
        .data_dl_wr(dl_wr && dl_addr>=16'h9800 && dl_addr<16'ha800),.data_dl_addr(12'(dl_addr-16'h9800)),
        .dl_data(dl_data),.command(command),.ctl_status(ctl_read[0]),
        .bit_req(bit_req),.bit_ready(bit_ready),.bit_valid(bit_valid),.bit_data(bit_data),.bit_address(bit_address),
        .control_latches(control_latches),.ctl(ctl),.pdc(pdc),.ctl_wr(ctl_wr),.pdc_wr(pdc_wr),.intack(intack),
        .req(req),.wr(wr),.memory_space(memory_space),.extended(extended),.data_port(data_port),.flag(flag),
        .address(address),.write_data(write_data),.read_data(read_data),.phase(phase));
    wire unused_parameter_valid,unused_active_sample;
    wire [6:0] unused_parameter_energy;
    wire [7:0] unused_parameter_pitch;
    wire [99:0] unused_parameter_coefficients;
    wire signed [7:0] unused_excitation;
    wire [2:0] unused_interpolation_period;
    wire [3:0] unused_parameter_counter;
    wire [1:0] unused_subcycle;
    wire [12:0] unused_rng;
    wire [8:0] unused_pitch_count;
    cvs_tms5100_engine engine(.clk(clk),.reset(reset),.sample_tick(sample_tick),.ctl(ctl),.pdc(pdc),
        .ctl_read(ctl_read),.ctl_output(ctl_output),.talk_status(talk_status),
        .bit_req(bit_req),.bit_ready(bit_ready),.bit_valid(bit_valid),.bit_data(bit_data),
        .sample_valid(sample_valid),.protocol_error(protocol_error),.pcm(pcm),
        .decoded_frame(decoded_frame),.energy_index(energy_index),.pitch_index(pitch_index),
        .coefficient_indices(coefficient_indices),.parameter_valid(unused_parameter_valid),
        .active_sample(unused_active_sample),.parameter_energy(unused_parameter_energy),
        .parameter_pitch(unused_parameter_pitch),.parameter_coefficients(unused_parameter_coefficients),
        .excitation(unused_excitation),.interpolation_period(unused_interpolation_period),
        .parameter_counter(unused_parameter_counter),.subcycle(unused_subcycle),.rng(unused_rng),.pitch_count(unused_pitch_count));
endmodule
