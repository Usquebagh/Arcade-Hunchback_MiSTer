// SPDX-License-Identifier: BSD-3-Clause
// Provisional identity viewport, not measured PCK/PIXCLK/display phases.
module cvs_scan (
    input wire clk, reset, run,
    output wire pixel_ce, pixel_ce_all, line_start, frame_start, vrst, visible,
    output wire [7:0] pixel_x, pixel_y,
    output wire hsync_n, vsync_n, hrst, cbf,
    output wire [7:0] h_count,
    output wire [8:0] v_count
);
    wire ce_position, raw_line_start, blank;
    reg [1:0] line_delay;
    cvs_video_timing timing(.clk(clk),.reset(reset),.run(run),.ce_position(ce_position),
        .line_start(raw_line_start),.frame_start(frame_start),.h_count(h_count),.v_count(v_count),
        .hrst(hrst),.vrst(vrst),.cbf(cbf),.blank(blank),.hsync_n(hsync_n),.vsync_n(vsync_n));
    always @(posedge clk) begin
        if(reset) line_delay<=2'd0;
        else if(run) line_delay<={line_delay[0],raw_line_start};
    end
    assign line_start=run && !reset && line_delay[1];
    wire viewport=v_count>=9'd43 && v_count<9'd299;
    assign pixel_ce=ce_position && viewport;
    assign pixel_ce_all=ce_position;
    assign pixel_x=h_count>=8'd6 ? h_count-8'd6 : h_count+8'd221;
    assign pixel_y=8'(v_count-9'd43);
    assign visible=viewport && !blank;
endmodule
