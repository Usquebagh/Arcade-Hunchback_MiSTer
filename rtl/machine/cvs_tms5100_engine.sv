// SPDX-License-Identifier: BSD-3-Clause
// Connected normalized components; external logical sample ticks/serial ROM.
module cvs_tms5100_engine (
    input wire clk,reset,sample_tick,
    input wire [3:0] ctl,
    input wire pdc,
    output wire [3:0] ctl_read,
    output wire ctl_output,talk_status,
    output wire bit_req,
    input wire bit_ready,bit_valid,bit_data,
    output reg sample_valid,protocol_error,
    output reg signed [15:0] pcm,
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
    output wire [8:0] pitch_count
);
    localparam [1:0] NONE=0,CONTROL=1,FRAME=2;
    reg [1:0] owner;
    wire control_req,control_ready,control_valid,frame_bit_req,frame_bit_ready,frame_bit_valid;
    wire start,slow,datapath_reset,control_error,unused_address_load,unused_branch,unused_control_busy;
    wire [3:0] unused_address_nibble;
    wire hard_clear=reset || datapath_reset;
    assign bit_req=!hard_clear && owner==NONE && (control_req || frame_bit_req);
    assign control_ready=!hard_clear && owner==NONE && bit_ready;
    assign frame_bit_ready=!hard_clear && owner==NONE && !control_req && bit_ready;
    assign control_valid=!hard_clear && owner==CONTROL && bit_valid;
    assign frame_bit_valid=!hard_clear && owner==FRAME && bit_valid;
    cvs_tms5100_control control(.clk(clk),.reset(reset),.ctl(ctl),.pdc(pdc),.talk_status(talk_status),
        .ctl_read(ctl_read),.ctl_output(ctl_output),.start(start),.slow(slow),.datapath_reset(datapath_reset),
        .address_load(unused_address_load),.branch(unused_branch),.address_nibble(unused_address_nibble),
        .bit_req(control_req),.bit_ready(control_ready),.bit_valid(control_valid),.bit_data(bit_data),
        .busy(unused_control_busy),.protocol_error(control_error));
    wire unused_frame_ready,frame_busy,frame_error,unused_repeat_frame,unvoiced_mask,unused_stop_frame;
    wire frame_req;
    cvs_tms5100_frames frames(.clk(clk),.reset(reset),.clear(datapath_reset),.frame_req(frame_req),
        .frame_ready(unused_frame_ready),.busy(frame_busy),.bit_req(frame_bit_req),
        .bit_ready(frame_bit_ready),.bit_valid(frame_bit_valid),.bit_data(bit_data),
        .frame_valid(decoded_frame),.protocol_error(frame_error),.energy_index(energy_index),
        .pitch_index(pitch_index),.repeat_frame(unused_repeat_frame),.unvoiced_mask(unvoiced_mask),
        .stop_frame(unused_stop_frame),.coefficient_indices(coefficient_indices));
    reg loading,target_valid;
    reg [3:0] k_slot;
    reg [6:0] target_energy;
    reg [7:0] target_pitch;
    reg [99:0] target_coefficients;
    wire [6:0] table_energy;
    wire [7:0] table_pitch;
    wire signed [9:0] table_coefficient;
    wire signed [7:0] chirp_data;
    wire [5:0] chirp_address;
    wire [1:0] unused_shift;
    cvs_tms5100_tables tables(.energy_address(energy_index),.pitch_address(pitch_index),
        .k_slot(k_slot),.k_index(coefficient_indices[k_slot*5+:5]),.chirp_address(chirp_address),
        .interpolation_address(interpolation_period),.energy(table_energy),.pitch(table_pitch),
        .coefficient(table_coefficient),.chirp(chirp_data),.interpolation_shift(unused_shift));
    wire target_ready,sequence_busy,sequence_error;
    wire unused_inhibit,unused_pitch_zero,unused_old_silence,unused_old_unvoiced,unused_zero_all,unused_zero_high;
    cvs_tms5100_sequence sequence_unit(.clk(clk),.reset(reset),.clear(datapath_reset),.start(start),.slow(slow),
        .sample_tick(sample_tick),.frame_req(frame_req),.frame_ready(target_ready),.busy(sequence_busy),
        .talk_status(talk_status),.frame_valid(target_valid),.frame_energy_index(energy_index),
        .frame_pitch_index(pitch_index),.frame_energy(target_energy),.frame_pitch(target_pitch),
        .frame_coefficients(target_coefficients),.frame_unvoiced_mask(unvoiced_mask),
        .chirp_address(chirp_address),.chirp_data(chirp_data),.parameter_valid(parameter_valid),
        .active_sample(active_sample),.protocol_error(sequence_error),.parameter_energy(parameter_energy),
        .parameter_pitch(parameter_pitch),.parameter_coefficients(parameter_coefficients),.excitation(excitation),
        .interpolation_period(interpolation_period),.parameter_counter(parameter_counter),.subcycle(subcycle),
        .rng(rng),.pitch_count(pitch_count),.inhibit(unused_inhibit),.pitch_zero(unused_pitch_zero),
        .old_silence(unused_old_silence),.old_unvoiced(unused_old_unvoiced),.zero_all(unused_zero_all),.zero_high(unused_zero_high));
    wire filter_valid,filter_busy,filter_error,filter_ready;
    wire signed [14:0] unused_filter_raw;
    wire signed [15:0] filter_pcm;
    wire filter_req=parameter_valid && active_sample && !hard_clear;
    cvs_tms5100_lattice filter(.clk(clk),.reset(reset),.clear(datapath_reset),.sample_req(filter_req),
        .energy(parameter_energy),.excitation(excitation),.coefficients(parameter_coefficients),
        .sample_ready(filter_ready),.busy(filter_busy),.sample_valid(filter_valid),.protocol_error(filter_error),
        .raw_sample(unused_filter_raw),.pcm_sample(filter_pcm));
    always @(posedge clk)begin
        target_valid<=1'b0;sample_valid<=1'b0;
        if(reset)protocol_error<=1'b0;
        else if(control_error || frame_error || sequence_error || filter_error ||
                (sample_tick && (frame_busy || loading || sequence_busy || filter_busy || parameter_valid)) ||
                (decoded_frame && loading) || (filter_req && !filter_ready) ||
                (target_valid && !target_ready))protocol_error<=1'b1;
        if(hard_clear)begin
            owner<=NONE;loading<=1'b0;k_slot<=4'd0;target_valid<=1'b0;
            target_energy<=7'd0;target_pitch<=8'd0;target_coefficients<=100'd0;pcm<=16'sd0;
        end else begin
            if(owner!=NONE && bit_valid)owner<=NONE;
            if(owner==NONE && bit_req && bit_ready)owner<=control_req ? CONTROL : FRAME;
            if(decoded_frame)begin
                loading<=1'b1;k_slot<=4'd0;target_energy<=table_energy;target_pitch<=table_pitch;
            end else if(loading)begin
                target_coefficients[k_slot*10+:10]<=table_coefficient;
                if(k_slot==9)begin loading<=1'b0;target_valid<=1'b1;end
                else k_slot<=k_slot+4'd1;
            end
            if(parameter_valid && !active_sample)begin pcm<=16'shffff;sample_valid<=1'b1;end
            if(filter_valid)begin pcm<=filter_pcm;sample_valid<=1'b1;end
        end
    end
endmodule
