// SPDX-License-Identifier: BSD-3-Clause
// Original serial lattice: modulo-32768 state is observably equivalent to the
// pinned software's wide sums followed by wrapped matrix inputs/final output.
module cvs_tms5100_lattice (
    input wire clk,reset,clear,sample_req,
    input wire [6:0] energy,
    input wire signed [7:0] excitation,
    input wire [99:0] coefficients,
    output wire sample_ready,busy,
    output reg sample_valid,protocol_error,
    output reg signed [14:0] raw_sample,
    output reg signed [15:0] pcm_sample
);
    localparam [1:0] IDLE=0,UP=1,DOWN=2,FINISH=3;
    reg [1:0] state;
    reg [3:0] stage;
    reg [99:0] captured_k;
    reg [6:0] previous_energy,next_energy;
    reg signed [14:0] top[0:10],delay[0:9];
    wire [3:0] mul_slot=state==DOWN ? stage-4'd1 : stage;
    wire signed [9:0] mul_coefficient=$signed(captured_k[mul_slot*10+:10]);
    wire signed [14:0] mul_value=state==UP ? delay[stage] : top[stage-4'd1];
    wire signed [15:0] initial_product=$signed({1'b0,previous_energy}) * excitation;
    wire signed [15:0] quantized;
    cvs_tms5100_pcm quantizer(.raw_sample(top[0]),.pcm_sample(quantized));
    assign busy=state!=IDLE;
    assign sample_ready=!reset && !clear && !busy;
    function automatic signed [14:0] matrix(input signed [9:0] a,input signed [14:0] b);
        reg signed [24:0] product;
        begin product=a*b;matrix=15'(product >>> 9);end
    endfunction
    always @(posedge clk)begin
        sample_valid<=1'b0;
        if(reset || clear)begin
            state<=IDLE;stage<=4'd9;captured_k<=100'd0;
            previous_energy<=7'd0;next_energy<=7'd0;protocol_error<=1'b0;
            raw_sample<=15'sd0;pcm_sample<=16'sd0;
            for(integer i=0;i<11;i=i+1)top[i]<=15'sd0;
            for(integer i=0;i<10;i=i+1)delay[i]<=15'sd0;
        end else begin
            if(sample_req && busy)protocol_error<=1'b1;
            case(state)
                IDLE:if(sample_req)begin
                    captured_k<=coefficients;next_energy<=energy;
                    top[10]<=15'(initial_product >>> 3);stage<=4'd9;state<=UP;
                end
                UP:begin
                    top[stage]<=top[stage+4'd1]-matrix(mul_coefficient,mul_value);
                    if(stage==0)begin stage<=4'd9;state<=DOWN;end
                    else stage<=stage-4'd1;
                end
                DOWN:begin
                    delay[stage]<=delay[stage-4'd1]+matrix(mul_coefficient,mul_value);
                    if(stage==4'd1)state<=FINISH;
                    else stage<=stage-4'd1;
                end
                FINISH:begin
                    delay[0]<=top[0];raw_sample<=top[0];pcm_sample<=quantized;
                    previous_energy<=next_energy;sample_valid<=1'b1;state<=IDLE;
                end
            endcase
        end
    end
endmodule
