// SPDX-License-Identifier: BSD-3-Clause
// Original logical-sample sequencer for the pinned software fast-start profile.
// sample_tick/frame targets/chirp data are normalized external interfaces.
module cvs_tms5100_sequence (
    input wire clk,reset,clear,start,slow,sample_tick,
    output reg frame_req,
    output wire frame_ready,busy,talk_status,
    input wire frame_valid,
    input wire [3:0] frame_energy_index,
    input wire [4:0] frame_pitch_index,
    input wire [6:0] frame_energy,
    input wire [7:0] frame_pitch,
    input wire [99:0] frame_coefficients,
    input wire frame_unvoiced_mask,
    output wire [5:0] chirp_address,
    input wire signed [7:0] chirp_data,
    output reg parameter_valid,active_sample,protocol_error,
    output reg [6:0] parameter_energy,
    output reg [7:0] parameter_pitch,
    output reg [99:0] parameter_coefficients,
    output reg signed [7:0] excitation,
    output reg [2:0] interpolation_period,
    output reg [3:0] parameter_counter,
    output reg [1:0] subcycle,
    output reg [12:0] rng,
    output reg [8:0] pitch_count,
    output reg inhibit,pitch_zero,old_silence,old_unvoiced,zero_all,zero_high
);
    reg pending,spen,talk,talkd,subcycle_reload;
    reg [3:0] target_energy_index;
    reg [4:0] target_pitch_index;
    reg [6:0] target_energy;
    reg [7:0] target_pitch;
    reg [99:0] target_coefficients;
    reg [6:0] next_energy;
    reg [7:0] next_pitch;
    reg [99:0] next_coefficients;
    reg [1:0] interpolation_shift;
    wire inhibit_update=inhibit && interpolation_period!=0;
    assign busy=pending;
    assign frame_ready=pending && !reset && !clear;
    assign talk_status=spen || talkd;
    assign chirp_address=pitch_count>=9'd51 ? 6'd51 : pitch_count[5:0];
    function automatic signed [9:0] interpolate(
        input signed [9:0] previous,input signed [9:0] target,
        input [1:0] shift,input block_update,input force_zero);
        reg signed [10:0] difference;
        reg signed [9:0] value;
        begin
            difference=$signed({target[9],target})-$signed({previous[9],previous});
            value=10'($signed({previous[9],previous})+(block_update ? 11'sd0 : (difference >>> shift)));
            interpolate=force_zero ? 10'sd0 : value;
        end
    endfunction
    function automatic [12:0] advance_rng(input [12:0] previous);
        reg [12:0] value;
        begin
            value=previous;
            for(integer n=0;n<20;n=n+1)value={value[11:0],value[12]^value[3]^value[2]^value[0]};
            advance_rng=value;
        end
    endfunction
    always @* begin
        case(interpolation_period)
            3'd0:interpolation_shift=2'd0;
            3'd1,3'd2,3'd3:interpolation_shift=2'd3;
            3'd4,3'd5:interpolation_shift=2'd2;
            default:interpolation_shift=2'd1;
        endcase
        next_energy=parameter_energy;next_pitch=parameter_pitch;
        next_coefficients=parameter_coefficients;
        if(subcycle==2)begin
            if(parameter_counter==0)
                next_energy=7'(interpolate($signed({3'd0,parameter_energy}),$signed({3'd0,target_energy}),interpolation_shift,inhibit_update,zero_all));
            else if(parameter_counter==1)
                next_pitch=8'(interpolate($signed({2'd0,parameter_pitch}),$signed({2'd0,target_pitch}),interpolation_shift,inhibit_update,zero_all));
            else if(parameter_counter>=2 && parameter_counter<=11)
                next_coefficients[(parameter_counter-2)*10+:10]=interpolate(
                    $signed(parameter_coefficients[(parameter_counter-2)*10+:10]),
                    $signed(target_coefficients[(parameter_counter-2)*10+:10]),
                    interpolation_shift,inhibit_update,zero_all || (zero_high && parameter_counter>=6));
        end
    end
    task automatic advance_phase(input is_active,input [7:0] effective_pitch,input effective_pitch_zero);
        reg force_pitch_zero;
        begin
            force_pitch_zero=effective_pitch_zero;
            if(parameter_counter==12 && subcycle==1)begin
                if(interpolation_period==7)begin
                    talkd<=talk;
                    if(!talk && spen)talk<=1'b1;
                    if(is_active)begin
                        old_silence<=target_energy_index==0;old_unvoiced<=target_pitch_index==0;
                        if(inhibit)begin pitch_zero<=1'b1;force_pitch_zero=1'b1;end
                    end
                end
                parameter_counter<=4'd0;subcycle<={1'b0,subcycle_reload};
                interpolation_period<=interpolation_period+3'd1;
            end else if(subcycle==2)begin
                parameter_counter<=parameter_counter+4'd1;subcycle<={1'b0,subcycle_reload};
            end else subcycle<=subcycle+2'd1;
            if(is_active)begin
                if(force_pitch_zero || pitch_count+9'd1>={1'b0,effective_pitch})pitch_count<=9'd0;
                else pitch_count<=pitch_count+9'd1;
            end
        end
    endtask
    task automatic emit_active;
        begin
            excitation<=old_unvoiced ? (rng[0] ? -8'sd64 : 8'sd64) : chirp_data;
            rng<=advance_rng(rng);parameter_valid<=1'b1;active_sample<=1'b1;
        end
    endtask
    always @(posedge clk)begin
        frame_req<=1'b0;parameter_valid<=1'b0;
        if(reset || clear)begin
            pending<=1'b0;spen<=1'b0;talk<=1'b0;talkd<=1'b0;subcycle_reload<=1'b1;
            target_energy_index<=4'd0;target_pitch_index<=5'd0;
            target_energy<=7'd0;target_pitch<=8'd0;target_coefficients<=100'd0;
            active_sample<=1'b0;protocol_error<=1'b0;
            parameter_energy<=7'd0;parameter_pitch<=8'd0;parameter_coefficients<=100'd0;excitation<=8'sd0;
            interpolation_period<=3'd0;parameter_counter<=4'd0;subcycle<=2'd0;
            rng<=13'h1fff;pitch_count<=9'd0;inhibit<=1'b1;pitch_zero<=1'b0;
            old_silence<=1'b1;old_unvoiced<=1'b1;zero_all<=1'b0;zero_high<=1'b0;
        end else begin
            if(sample_tick)begin
                if(pending)protocol_error<=1'b1;
                else if(!talkd)begin
                    active_sample<=1'b0;parameter_valid<=1'b1;advance_phase(1'b0,parameter_pitch,pitch_zero);
                end else if(interpolation_period==0 && parameter_counter==12 && subcycle==1)begin
                    frame_req<=1'b1;pending<=1'b1;
                end else begin
                    parameter_energy<=next_energy;parameter_pitch<=next_pitch;parameter_coefficients<=next_coefficients;
                    emit_active();
                    if(interpolation_period==0 && parameter_counter==0 && subcycle==2)pitch_zero<=1'b0;
                    advance_phase(1'b1,next_pitch,!(interpolation_period==0 && parameter_counter==0 && subcycle==2) && pitch_zero);
                end
            end
            if(pending && frame_valid)begin
                pending<=1'b0;target_energy_index<=frame_energy_index;target_pitch_index<=frame_pitch_index;
                target_energy<=frame_energy;target_pitch<=frame_pitch;target_coefficients<=frame_coefficients;
                zero_all<=1'b0;zero_high<=frame_unvoiced_mask;
                inhibit<=(old_unvoiced!=(frame_pitch_index==0)) || (old_silence && frame_energy_index!=0);
                if(frame_energy_index==4'hf)begin spen<=1'b0;talk<=1'b0;end
                emit_active();advance_phase(1'b1,parameter_pitch,pitch_zero);
            end
            if(start)begin
                if(pending)protocol_error<=1'b1;
                spen<=1'b1;talk<=1'b1;subcycle_reload<=!slow;
                old_silence<=1'b1;old_unvoiced<=1'b1;zero_all<=1'b1;zero_high<=1'b1;
            end
        end
    end
endmodule
