// SPDX-License-Identifier: BSD-3-Clause
// Contract: master clock = four times the board's 14.318181 MHz crystal.
// Enables are synchronous strobes, never generated clocks.
module cvs_clock (
    input wire clk,
    input wire reset,
    output wire ce_main,
    output wire ce_audio,
    output wire ce_main_step,
    output wire ce_audio_step
);
    reg [5:0] phase;
    reg [1:0] main_step, audio_step;
    always @(posedge clk) begin
        if (reset) phase <= 6'd0;
        else phase <= phase + 6'd1;
    end
    // The adapted S2650 advances once per three original CPU clock periods.
    always @(posedge clk) begin
        if (reset) begin
            main_step <= 2'd0;
            audio_step <= 2'd0;
        end else begin
            if (ce_main) main_step <= main_step == 2'd2 ? 2'd0 : main_step + 2'd1;
            if (ce_audio) audio_step <= audio_step == 2'd2 ? 2'd0 : audio_step + 2'd1;
        end
    end
    assign ce_main = !reset && (phase[4:0] == 5'd31);
    assign ce_audio = !reset && (phase == 6'd63);
    assign ce_main_step = ce_main && (main_step == 2'd2);
    assign ce_audio_step = ce_audio && (audio_step == 2'd2);
endmodule
