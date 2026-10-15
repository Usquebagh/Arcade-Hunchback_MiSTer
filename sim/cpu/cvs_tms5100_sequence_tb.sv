// SPDX-License-Identifier: BSD-3-Clause
// Actual sequencer and TMC0281 chirp ROM; decoded frame targets are fixtures.
module cvs_tms5100_sequence_tb (
    input wire clk,reset,clear,start,slow,sample_tick,frame_valid,
    input wire [3:0] frame_energy_index,
    input wire [4:0] frame_pitch_index,
    input wire [6:0] frame_energy,
    input wire [7:0] frame_pitch,
    input wire [99:0] frame_coefficients,
    input wire frame_unvoiced_mask,
    output wire frame_req,frame_ready,busy,talk_status,parameter_valid,active_sample,protocol_error,
    output wire [6:0] parameter_energy,table_energy,
    output wire [7:0] parameter_pitch,table_pitch,
    output wire [99:0] parameter_coefficients,
    output wire signed [7:0] excitation,
    output wire [2:0] interpolation_period,
    output wire [3:0] parameter_counter,
    output wire [1:0] subcycle,table_shift,
    output wire [12:0] rng,
    output wire [8:0] pitch_count,
    output wire inhibit,pitch_zero,old_silence,old_unvoiced,zero_all,zero_high,
    output wire [5:0] chirp_address,
    output wire signed [9:0] table_coefficient
);
    wire signed [7:0] chirp_data;
    cvs_tms5100_sequence sequencer(.*);
    cvs_tms5100_tables tables(.energy_address(4'd0),.pitch_address(5'd0),.k_slot(4'd0),.k_index(5'd0),
        .chirp_address(chirp_address),.interpolation_address(interpolation_period),
        .energy(table_energy),.pitch(table_pitch),.coefficient(table_coefficient),
        .chirp(chirp_data),.interpolation_shift(table_shift));
endmodule
