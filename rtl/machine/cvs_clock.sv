// SPDX-License-Identifier: BSD-3-Clause
// Contract: master clock = four times the board's 14.318181 MHz crystal.
// Enables are synchronous strobes, never generated clocks.
module cvs_clock (
    input wire clk,
    input wire reset,
    output wire ce_main,
    output wire ce_audio
);
    reg [5:0] phase;
    always @(posedge clk) begin
        if (reset) phase <= 6'd0;
        else phase <= phase + 6'd1;
    end
    assign ce_main = !reset && (phase[4:0] == 5'd31);
    assign ce_audio = !reset && (phase == 6'd63);
endmodule
