// SPDX-License-Identifier: BSD-3-Clause
// Independently written normalized MAME-compatible command boundary, not LPC.
module cvs_tms5100_control (
    input wire clk,reset,
    input wire [3:0] ctl,
    input wire pdc,talk_status,
    output wire [3:0] ctl_read,
    output wire ctl_output,
    output reg start,slow,datapath_reset,
    output reg address_load,branch,
    output reg [3:0] address_nibble,
    output wire bit_req,
    input wire bit_ready,bit_valid,bit_data,
    output wire busy,
    output reg protocol_error
);
    localparam [2:0] INPUT_STATE=0,ARM_TALK=1,TALK_OUTPUT=2,
                     ARM_BUFFER=3,BUFFER_OUTPUT=4;
    localparam [2:0] IDLE=0,READ_BIT=1,DUMMY_ONLY=2,
                     DUMMY_START=3,DUMMY_RESET=4;
    reg [2:0] direction,operation;
    reg [3:0] read_buffer;
    reg previous_pdc,next_address,dummy_pending,waiting;
    wire falling=previous_pdc && !pdc;
    assign ctl_output=direction==TALK_OUTPUT || direction==BUFFER_OUTPUT;
    assign ctl_read=direction==TALK_OUTPUT ? {3'd0,talk_status} :
                    direction==BUFFER_OUTPUT ? read_buffer : ctl;
    assign busy=operation!=IDLE;
    assign bit_req=!reset && operation!=IDLE && !waiting;
    always @(posedge clk)begin
        previous_pdc<=pdc;
        start<=1'b0;datapath_reset<=1'b0;address_load<=1'b0;branch<=1'b0;
        if(reset)begin
            direction<=INPUT_STATE;operation<=IDLE;read_buffer<=4'd0;
            previous_pdc<=1'b0;next_address<=1'b0;dummy_pending<=1'b0;
            waiting<=1'b0;slow<=1'b0;address_nibble<=4'd0;protocol_error<=1'b0;
        end else begin
            if(bit_req && bit_ready)waiting<=1'b1;
            if(waiting && bit_valid)begin
                waiting<=1'b0;operation<=IDLE;
                if(operation==READ_BIT)read_buffer<={bit_data,read_buffer[3:1]};
                else if(operation==DUMMY_START)start<=1'b1;
                else if(operation==DUMMY_RESET)begin
                    datapath_reset<=1'b1;read_buffer<=4'd0;direction<=INPUT_STATE;
                    next_address<=1'b0;slow<=1'b0;address_nibble<=4'd0;
                end
            end
            if(falling)begin
                if(busy)protocol_error<=1'b1;
                else case(direction)
                    ARM_TALK:direction<=TALK_OUTPUT;
                    TALK_OUTPUT:direction<=INPUT_STATE;
                    ARM_BUFFER:direction<=BUFFER_OUTPUT;
                    BUFFER_OUTPUT:direction<=INPUT_STATE;
                    default:begin
                        if(next_address)begin
                            next_address<=1'b0;address_load<=1'b1;
                            address_nibble<=ctl;dummy_pending<=1'b1;
                        end else case(ctl[3:1])
                            3'd0:begin
                                dummy_pending<=1'b0;
                                if(dummy_pending)operation<=DUMMY_RESET;
                                else begin
                                    datapath_reset<=1'b1;read_buffer<=4'd0;
                                    direction<=INPUT_STATE;next_address<=1'b0;
                                    slow<=1'b0;address_nibble<=4'd0;
                                end
                            end
                            3'd1:next_address<=1'b1;
                            3'd2:direction<=ARM_BUFFER;
                            3'd3,3'd5:begin
                                slow<=ctl[3:1]==3'd3;dummy_pending<=1'b0;
                                if(dummy_pending)operation<=DUMMY_START;
                                else start<=1'b1;
                            end
                            3'd4:begin
                                dummy_pending<=1'b0;
                                operation<=dummy_pending ? DUMMY_ONLY : READ_BIT;
                            end
                            3'd6:begin branch<=1'b1;dummy_pending<=1'b0;end
                            3'd7:direction<=ARM_TALK;
                        endcase
                    end
                endcase
            end
        end
    end
endmodule
