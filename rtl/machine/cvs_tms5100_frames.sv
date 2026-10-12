// SPDX-License-Identifier: BSD-3-Clause
// Original staged TMC0281 serial parser; normalized handshake, not pin timing.
module cvs_tms5100_frames (
    input wire clk,reset,clear,frame_req,
    output wire frame_ready,busy,bit_req,
    input wire bit_ready,bit_valid,bit_data,
    output reg frame_valid,protocol_error,
    output reg [3:0] energy_index,
    output reg [4:0] pitch_index,
    output reg repeat_frame,unvoiced_mask,
    output wire stop_frame,
    output reg [49:0] coefficient_indices
);
    localparam [2:0] IDLE=0,ENERGY=1,REPEAT_BIT=2,PITCH=3,COEFFICIENT=4;
    reg [2:0] state,bits_left;
    reg waiting;
    reg [3:0] accumulator;
    reg [4:0] staged_pitch;
    reg [3:0] staged_energy,k_slot;
    reg staged_repeat;
    reg [49:0] staged_k;
    wire [4:0] assembled={accumulator,bit_data};
    assign busy=state!=IDLE;
    assign frame_ready=!reset && !clear && !busy;
    assign bit_req=!reset && !clear && busy && !waiting;
    assign stop_frame=energy_index==4'hf;
    function automatic [2:0] k_width(input [3:0] slot);
        if(slot<2)k_width=3'd5;
        else if(slot<7)k_width=3'd4;
        else k_width=3'd3;
    endfunction
    always @(posedge clk)begin
        frame_valid<=1'b0;
        if(reset || clear)begin
            state<=IDLE;bits_left<=3'd0;waiting<=1'b0;accumulator<=4'd0;
            staged_pitch<=5'd0;staged_energy<=4'd0;k_slot<=4'd0;
            staged_repeat<=1'b0;staged_k<=50'd0;protocol_error<=1'b0;
            energy_index<=4'd0;pitch_index<=5'd0;coefficient_indices<=50'd0;
            repeat_frame<=1'b0;unvoiced_mask<=1'b0;
        end else begin
            if(frame_req)begin
                if(!frame_ready)protocol_error<=1'b1;
                else begin
                    state<=ENERGY;bits_left<=3'd4;accumulator<=4'd0;
                    staged_k<=coefficient_indices;staged_pitch<=pitch_index;
                    staged_repeat<=1'b0;k_slot<=4'd0;
                end
            end
            if(bit_req && bit_ready)waiting<=1'b1;
            if(waiting && bit_valid)begin
                waiting<=1'b0;
                if(bits_left!=3'd1)begin
                    accumulator<=assembled[3:0];bits_left<=bits_left-3'd1;
                end else begin
                    accumulator<=4'd0;
                    case(state)
                        ENERGY:begin
                            staged_energy<=assembled[3:0];
                            if(assembled[3:0]==0 || assembled[3:0]==4'hf)begin
                                energy_index<=assembled[3:0];repeat_frame<=1'b0;
                                unvoiced_mask<=1'b0;frame_valid<=1'b1;state<=IDLE;
                            end else begin state<=REPEAT_BIT;bits_left<=3'd1;end
                        end
                        REPEAT_BIT:begin
                            staged_repeat<=bit_data;state<=PITCH;bits_left<=3'd5;
                        end
                        PITCH:begin
                            staged_pitch<=assembled;
                            if(staged_repeat)begin
                                energy_index<=staged_energy;pitch_index<=assembled;
                                repeat_frame<=1'b1;unvoiced_mask<=assembled==0;
                                frame_valid<=1'b1;state<=IDLE;
                            end else begin state<=COEFFICIENT;bits_left<=3'd5;k_slot<=4'd0;end
                        end
                        COEFFICIENT:begin
                            staged_k[k_slot*5+:5]<=assembled;
                            if(k_slot==4'd9 || (staged_pitch==0 && k_slot==4'd3))begin
                                coefficient_indices<=staged_k;
                                coefficient_indices[k_slot*5+:5]<=assembled;
                                energy_index<=staged_energy;pitch_index<=staged_pitch;
                                repeat_frame<=1'b0;unvoiced_mask<=staged_pitch==0;
                                frame_valid<=1'b1;state<=IDLE;
                            end else begin k_slot<=k_slot+4'd1;bits_left<=k_width(k_slot+4'd1);end
                        end
                        default:protocol_error<=1'b1;
                    endcase
                end
            end
        end
    end
endmodule
