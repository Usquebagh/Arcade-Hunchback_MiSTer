// SPDX-License-Identifier: BSD-3-Clause
// CVS 2621 sync slots plus the schematic-derived PCK pixel enable.
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
    reg [3:0] pixel_phase;
    reg [7:0] active_pixel;
    cvs_video_timing timing(.clk(clk),.reset(reset),.run(run),.ce_position(ce_position),
        .line_start(raw_line_start),.frame_start(frame_start),.h_count(h_count),.v_count(v_count),
        .hrst(hrst),.vrst(vrst),.cbf(cbf),.blank(blank),.hsync_n(hsync_n),.vsync_n(vsync_n));
    always @(posedge clk) begin
        if(reset) line_delay<=2'd0;
        else if(run) line_delay<={line_delay[0],raw_line_start};
    end
    assign line_start=run && !reset && line_delay[1];
    // MAME's 256x256 screen exposes y=8..255 (248 rows). VRST/PVI field
    // timing remains at line 43; this crop only selects output rows.
    wire viewport=v_count>=9'd51 && v_count<9'd299;
    // U12A's PCK chain divides the 14.318 MHz crystal by three. HRST spans
    // 44 of the 2621's 227 slots; the 183 unblanked slots contain
    // 183*16/12 = 244 pixel periods. Rephase the /12 enable at HRST.
    wire active_pixel_ce=run && !reset && !hrst && pixel_phase==4'd11;
    assign pixel_ce_all=active_pixel_ce;
    assign pixel_ce=active_pixel_ce && viewport;
    always @(posedge clk) begin
        if(reset) begin
            pixel_phase<=4'd0;
            active_pixel<=8'd0;
        end else if(run) begin
            // Entering the 44-slot HRST reset window establishes the next
            // line's counter origin; keep it held until PIXCLK resumes.
            if(ce_position && h_count==8'd5) begin
                pixel_phase<=4'd0;
                active_pixel<=8'd0;
            end else if(!hrst && pixel_phase==4'd11) begin
                pixel_phase<=4'd0;
                active_pixel<=active_pixel+8'd1;
            end else if(!hrst) pixel_phase<=pixel_phase+4'd1;
        end
    end
    assign pixel_x=active_pixel;
    assign pixel_y=8'(v_count-9'd43);
    // The pixel strobe exists only outside HRST. This term handles vertical
    // blanking while preserving the 248-row MAME-compatible viewport.
    wire vertical_blank=blank && !hrst;
    assign visible=viewport && !vertical_blank;
endmodule
