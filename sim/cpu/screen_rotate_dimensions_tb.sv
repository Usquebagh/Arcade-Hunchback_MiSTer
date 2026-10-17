`timescale 1ns/1ps
module screen_rotate_dimensions_tb;
    reg clk=0,reset=1,pixel_ce=0,pixel_valid=0;
    reg [7:0] x=0;
    reg vs=1;
    wire rotate_ce,rotate_de,video_rotated,fb_en,ddram_clk,ddram_we,ddram_rd;
    wire [11:0] fb_width,fb_height;
    wire [4:0] fb_format;
    wire [31:0] fb_base;
    wire [13:0] fb_stride;
    wire [7:0] ddram_burstcnt,ddram_be;
    wire [28:0] ddram_addr;
    wire [63:0] ddram_din;
    always #5 clk=~clk;
    cvs_rotation_raster raster(.clk(clk),.reset(reset),.pixel_ce(pixel_ce),
        .pixel_valid(pixel_valid),.x(x),.rotate_pixel_ce(rotate_ce),.rotate_de(rotate_de));
    screen_rotate dut(.CLK_VIDEO(clk),.CE_PIXEL(rotate_ce),.VGA_R(8'h12),.VGA_G(8'h34),.VGA_B(8'h56),
        .VGA_HS(1'b1),.VGA_VS(vs),.VGA_DE(rotate_de),.rotate_ccw(1'b0),.no_rotate(1'b0),.flip(1'b0),
        .video_rotated(video_rotated),.FB_EN(fb_en),.FB_FORMAT(fb_format),.FB_WIDTH(fb_width),.FB_HEIGHT(fb_height),
        .FB_BASE(fb_base),.FB_STRIDE(fb_stride),.FB_VBL(1'b0),.FB_LL(1'b0),.DDRAM_CLK(ddram_clk),
        .DDRAM_BUSY(1'b0),.DDRAM_BURSTCNT(ddram_burstcnt),.DDRAM_ADDR(ddram_addr),.DDRAM_DIN(ddram_din),
        .DDRAM_BE(ddram_be),.DDRAM_WE(ddram_we),.DDRAM_RD(ddram_rd));
    task automatic pulse(input integer yy,input integer xx);
        begin
            @(negedge clk); x=xx[7:0];
            pixel_valid=(yy>=51 && yy<=298);
            vs=!((yy==11 && xx>=28) || (yy>=12 && yy<=14) || (yy==15 && xx<11));
            pixel_ce=1;
            @(posedge clk); #1; pixel_ce=0;
            repeat(15) @(posedge clk);
        end
    endtask
    integer frame,y,h;
    initial begin
        repeat(3) @(posedge clk); reset=0;
        for(frame=0;frame<3;frame=frame+1)
            for(y=1;y<=312;y=y+1)
            for(h=0;h<244;h=h+1) pulse(y,h);
        repeat(4) @(posedge clk); #1;
        if(fb_width!==12'd248 || fb_height!==12'd244) begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"rotation_native_dimensions\",\"cycle\":0,\"expected\":\"248x244\",\"observed\":\"%0dx%0d\"}",fb_width,fb_height);
            $finish(1);
        end
        $display("BDSM {\"status\":\"PASS\",\"observed\":\"screen_rotate accepts native 244x248 CVS pixels as a 248x244 rotated buffer\"}");
        $finish(0);
    end
endmodule
