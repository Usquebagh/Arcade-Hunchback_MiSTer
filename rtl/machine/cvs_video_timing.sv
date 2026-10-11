// SPDX-License-Identifier: BSD-3-Clause
// Provisional 2621 waveform subset. See docs/video-timing.md for reference gaps.
// Master = four times crystal; position tick = crystal/4. No generated clocks.
module cvs_video_timing #(
    parameter integer V_LINES = 312
) (
    input wire clk, reset, run,
    output wire ce_position, line_start, frame_start,
    output reg [7:0] h_count,
    output reg [8:0] v_count,
    output wire hrst, vrst, cbf, blank,
    output wire hsync_n, vsync_n
);
    reg [3:0] phase;
    assign ce_position = run && !reset && (phase == 4'd15);
    assign line_start = ce_position && (h_count == 8'd5);
    assign frame_start = line_start && (v_count == 9'(V_LINES));
    always @(posedge clk) begin
        if (reset) begin
            phase <= 4'd0;
            h_count <= 8'd0;
            v_count <= 9'(V_LINES);
        end else begin
            if (run) phase <= phase + 4'd1;
            if (ce_position) begin
                h_count <= h_count == 8'd226 ? 8'd0 : h_count + 8'd1;
                if (h_count == 8'd5) begin
                    v_count <= v_count == 9'(V_LINES) ? 9'd1 : v_count + 9'd1;
                end
            end
        end
    end
    assign hrst = h_count >= 8'd6 && h_count < 8'd50;
    assign vrst = v_count >= 9'd1 && v_count < 9'd43;
    assign cbf = h_count >= 8'd31 && h_count < 8'd40;
    assign blank = hrst || vrst;
    assign hsync_n = !(h_count >= 8'd11 && h_count < 8'd28);
    // A labelled line spans h=6..226, then h=0..5. Keep VS continuous
    // across that horizontal wrap, and exclude the tail after its falling edge.
    assign vsync_n = !((v_count == 9'd11 && (h_count >= 8'd28 || h_count < 8'd6)) ||
                      (v_count > 9'd11 && v_count < 9'd15) ||
                      (v_count == 9'd15 && h_count >= 8'd6 && h_count < 8'd11));
endmodule
