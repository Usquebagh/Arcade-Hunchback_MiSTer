// SPDX-License-Identifier: BSD-3-Clause
// Nominal 620000/80 Hz speech rate from the shared 57272724 Hz master.
module cvs_tms5100_rate (
    input wire clk,reset,
    output wire sample_tick
);
    reg [25:0] phase;
    wire [26:0] sum={1'b0,phase}+27'd7750;
    assign sample_tick=!reset && sum>=27'd57272724;
    always @(posedge clk)begin
        if(reset)phase<=26'd0;
        else phase<=sample_tick ? 26'(sum-27'd57272724) : 26'(sum);
    end
endmodule
