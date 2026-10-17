// SPDX-License-Identifier: BSD-3-Clause
// Private MiSTer shell integration; board clocks, input wiring and analog mix remain provisional.
module emu #(
    parameter DIAGNOSTIC_PROBES = 1'b0,
    parameter integer RESET_HOLD_CYCLES = 1_140_000
) (
    `include "sys/emu_ports.vh"
);
    assign ADC_BUS='Z;
    assign USER_OUT='1;
    assign {UART_RTS,UART_TXD,UART_DTR}=0;
    assign {SD_SCK,SD_MOSI,SD_CS}='Z;
    assign {SDRAM_DQ,SDRAM_A,SDRAM_BA,SDRAM_CLK,SDRAM_CKE,SDRAM_DQML,SDRAM_DQMH,
        SDRAM_nWE,SDRAM_nCAS,SDRAM_nRAS,SDRAM_nCS}='Z;
    assign {VGA_F1,VGA_SL,VGA_SCALER,VGA_DISABLE,HDMI_FREEZE,HDMI_BLACKOUT,HDMI_BOB_DEINT}=0;
    assign LED_DISK=0;
    assign LED_POWER=0;
    assign BUTTONS=0;

    wire [127:0] status;
    wire [1:0] buttons;
    wire [31:0] joy0,joy1;
    wire forced_scandoubler;
    wire video_rotated;
    wire ioctl_download,ioctl_wr;
    wire [26:0] ioctl_addr;
    wire [7:0] ioctl_dout;
    wire [15:0] ioctl_index;
    wire [21:0] unused_gamma_bus;
    wire clk_sys,pll_locked;
    localparam CONF_STR={
        "Hunchback (CVS);",
        "-;",
        "O[2:1],Coin A,1C1C,3C1C,2C1C,4C1C;",
        "O[4:3],Coin B,1C2C,1C3C,1C4C,1C5C;",
        "O[5],Lives,3,5;",
        "O[7],Cabinet,Upright,Cocktail;",
        "O[9:8],Bonus life,10k,20k,40k,80k;",
        "O[10],Registration,On,Off;",
        "O[11],Registration length,3,10;",
        "O[13:12],Orientation,Rotate CW,Rotate CCW,Native;",
        "O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
        "-;",
        // MRA names map consecutively to HPS joystick bits [4..7].
        "J1,Jump,Start 2,Start 1,Coin;",
        "jn,A,X,Start,Select;",
        "R0,Reset;",
        // MiSTer displays this permanent build identifier in the OSD version line.
        "V,v261017-02;"
    };
    hps_io #(.CONF_STR(CONF_STR)) hps_io (
        .clk_sys(clk_sys),.HPS_BUS(HPS_BUS),.EXT_BUS(),.gamma_bus(unused_gamma_bus),
        .forced_scandoubler(forced_scandoubler),.buttons(buttons),.status(status),
        .status_menumask(1'b0),.ioctl_download(ioctl_download),.ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),.ioctl_dout(ioctl_dout),.ioctl_index(ioctl_index),
        .ioctl_wait(1'b0),.joystick_0(joy0),.joystick_1(joy1),
        .video_rotated(video_rotated),.new_vmode(1'b0)
    );

    pll pll(.refclk(CLK_50M),.rst(1'b0),.outclk_0(clk_sys),.locked(pll_locked));
    wire rom_download=ioctl_download && ioctl_index==16'd0;
    reg rom_download_d=1'b0,rom_loaded=1'b0;
    always @(posedge clk_sys) begin
        rom_download_d<=rom_download;
        if(rom_download)rom_loaded<=1'b0;
        else if(rom_download_d)rom_loaded<=1'b1;
    end
    wire reset_async=RESET || status[0] || buttons[1] || !pll_locked;
    wire core_reset;
    cvs_reset #(.HOLD_CYCLES(RESET_HOLD_CYCLES)) reset_boundary(.clk(clk_sys),.reset_async(reset_async),.pll_locked(pll_locked),
        .load_active(rom_download),.rom_loaded(rom_loaded),.reset(core_reset));

    wire [7:0] in0,in1;
    cvs_mister_input controls(.joystick_0(joy0),.joystick_1(joy1),.in0(in0),.in1(in1));
    wire [1:0] coin_b=status[4:3]==2'd0 ? 2'b11 : status[4:3]==2'd1 ? 2'b01 :
                      status[4:3]==2'd2 ? 2'b10 : 2'b00;
    wire [1:0] bonus=status[9:8]==2'd0 ? 2'b11 : status[9:8]==2'd1 ? 2'b01 :
                     status[9:8]==2'd2 ? 2'b10 : 2'b00;
    wire [7:0] mame_dsw2={2'b11,1'b0,status[5],coin_b,status[2:1]};
    wire [7:0] mame_dsw3={3'b111,status[7],bonus,~status[11],~status[10]};

    reg [16:0] sense_divider=0;
    reg sense_380=0;
    always @(posedge clk_sys) begin
        if(core_reset)begin sense_divider<=0;sense_380<=0;end
        else if(sense_divider==17'd75359)begin sense_divider<=0;sense_380<=~sense_380;end
        else sense_divider<=sense_divider+17'd1;
    end

    wire pixel_valid,pixel_ce_all,display_enable;
    wire [7:0] out_x,out_y,red,green,blue,audio_command;
    wire [7:0] diagnostic_red,diagnostic_green,diagnostic_blue;
    wire [2:0] raw_pixel,pvi_irq;
    wire [3:0] palette_index,dac4,discrete;
    wire bullet_present,background_collision,hsync_n,vsync_n;
    wire [7:0] collision_events,collision,video_fx;
    wire audio_trigger,intack,audio_intack,audio_irq,dac8_wr,dac4_wr,discrete_wr;
    wire [7:0] dac8;
    wire [7:0] h_count;
    wire [8:0] v_count;

    // Optional HPS-boundary video probes for shell diagnostics. MiSTer joystick
    // bits are active-high; cvs_mister_input converts them to active-low CVS
    // matrix levels. Give status/reset priority so a held button cannot hide them.
    generate if (DIAGNOSTIC_PROBES) begin : diagnostic_video_probes
        reg [26:0] reset_probe_hold = 27'd0;
        always @(posedge clk_sys) begin
            if (!pll_locked) reset_probe_hold <= 27'd0;
            else if (status[0]) reset_probe_hold <= 27'd100_000_000;
            else if (reset_probe_hold != 0) reset_probe_hold <= reset_probe_hold - 27'd1;
        end
        wire diag_reset = status[0] || (reset_probe_hold != 0);
        wire diag_status = status[14];
        wire diag_credit1 = joy0[7];
        wire diag_credit2 = joy1[7];
        assign diagnostic_red = diag_reset ? 8'hff :
                                diag_status ? 8'hff :
                                diag_credit1 ? 8'h00 :
                                diag_credit2 ? 8'h00 : red;
        assign diagnostic_green = diag_reset ? 8'hff :
                                  diag_status ? 8'h00 :
                                  diag_credit1 ? 8'hff :
                                  diag_credit2 ? 8'h00 : green;
        assign diagnostic_blue = diag_reset ? 8'hff :
                                 diag_status ? 8'h00 :
                                 diag_credit1 ? 8'h00 :
                                 diag_credit2 ? 8'hff : blue;
    end else begin : normal_video
        assign diagnostic_red = red;
        assign diagnostic_green = green;
        assign diagnostic_blue = blue;
    end endgenerate
    wire [15:0] speech_bit_address;
    wire speech_sample_tick,speech_sample_valid,speech_protocol_error,speech_talk_status;
    wire signed [15:0] pcm8,pcm4,speech_pcm;
    cvs_full_machine machine (
        .clk(clk_sys),.reset(core_reset),.reset_na(!core_reset),.video_reset(core_reset),.scan_run(1'b1),
        .ready(1'b1),.audio_ready(1'b1),.audio_sense(sense_380),.speech_ready(1'b1),.speech_sense(sense_380),
        .dl_wr(ioctl_wr && rom_download),.dl_addr(ioctl_addr[15:0]),.dl_data(ioctl_dout),
        .in0(in0),.in1(in1),.in2(8'hff),.in3(8'hff),.dsw1(mame_dsw2),.dsw2(mame_dsw3),
        .pixel_valid(pixel_valid),.pixel_ce_all(pixel_ce_all),.display_enable(display_enable),
        .out_x(out_x),.out_y(out_y),.red(red),.green(green),.blue(blue),.raw_pixel(raw_pixel),
        .pvi_irq(pvi_irq),.palette_index(palette_index),.bullet_present(bullet_present),
        .background_collision(background_collision),.hsync_n(hsync_n),.vsync_n(vsync_n),
        .collision_events(collision_events),.collision(collision),.video_fx(video_fx),
        .audio_command(audio_command),.audio_trigger(audio_trigger),.intack(intack),
        .audio_intack(audio_intack),.audio_irq(audio_irq),.dac8(dac8),.dac4(dac4),.discrete(discrete),
        .dac8_wr(dac8_wr),.dac4_wr(dac4_wr),.discrete_wr(discrete_wr),.sample_ce(),.pcm8(pcm8),.pcm4(pcm4),
        .speech_sample_tick(speech_sample_tick),.speech_sample_valid(speech_sample_valid),
        .speech_protocol_error(speech_protocol_error),.speech_pcm(speech_pcm),.speech_talk_status(speech_talk_status),
        .speech_bit_address(speech_bit_address)
    );

    wire mister_pixel_ce;
    cvs_mister_pixel_enable pixel_enable_delay(.clk(clk_sys),.reset(core_reset),
        .pixel_ce_in(pixel_ce_all),.pixel_ce_out(mister_pixel_ce));
    assign CLK_VIDEO=clk_sys;
    assign CE_PIXEL=mister_pixel_ce;
    wire [1:0] ar=status[122:121];
    wire no_rotate=(status[13:12]>=2'd2);
    wire rotate_ccw=(status[13:12]==2'd1);
    wire fb_en;
    wire [4:0] fb_format;
    wire [11:0] fb_width,fb_height;
    wire [31:0] fb_base;
    wire [13:0] fb_stride;
    wire rotate_pixel_ce,rotate_de;
    cvs_rotation_raster #(.LAST_X(8'd243)) rotation_raster(.clk(clk_sys),.reset(core_reset),
        .pixel_ce(mister_pixel_ce),.pixel_valid(pixel_valid),.x(out_x),
        .rotate_pixel_ce(rotate_pixel_ce),.rotate_de(rotate_de));
    screen_rotate video_rotation (
        .CLK_VIDEO(CLK_VIDEO),.CE_PIXEL(rotate_pixel_ce),
        .VGA_R(diagnostic_red),.VGA_G(diagnostic_green),.VGA_B(diagnostic_blue),
        .VGA_HS(hsync_n),.VGA_VS(vsync_n),.VGA_DE(rotate_de),
        .rotate_ccw(rotate_ccw),.no_rotate(no_rotate),.flip(1'b0),.video_rotated(video_rotated),
        .FB_EN(fb_en),.FB_FORMAT(fb_format),.FB_WIDTH(fb_width),.FB_HEIGHT(fb_height),
        .FB_BASE(fb_base),.FB_STRIDE(fb_stride),.FB_VBL(FB_VBL),.FB_LL(FB_LL),
        .DDRAM_CLK(DDRAM_CLK),.DDRAM_BUSY(DDRAM_BUSY),.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
        .DDRAM_ADDR(DDRAM_ADDR),.DDRAM_DIN(DDRAM_DIN),.DDRAM_BE(DDRAM_BE),
        .DDRAM_WE(DDRAM_WE),.DDRAM_RD(DDRAM_RD)
    );
    assign FB_EN=fb_en;
    assign FB_FORMAT=fb_format;
    assign FB_WIDTH=fb_width;
    assign FB_HEIGHT=fb_height;
    assign FB_BASE=fb_base;
    assign FB_STRIDE=fb_stride;
    assign FB_FORCE_BLANK=1'b0;
    assign VIDEO_ARX=!ar ? (video_rotated ? 13'd248 : 13'd244) : ar==2'd1 ? 13'd0 : ar==2'd2 ? 13'd1 : 13'd2;
    assign VIDEO_ARY=!ar ? (video_rotated ? 13'd244 : 13'd248) : ar==2'd1 ? 13'd0 : 13'd0;
    assign VGA_R=diagnostic_red;
    assign VGA_G=diagnostic_green;
    assign VGA_B=diagnostic_blue;
    assign VGA_HS=hsync_n;
    assign VGA_VS=vsync_n;
    assign VGA_DE=display_enable;

    // Keep the audible bring-up path centered. The raw four-bit latch remains
    // exposed for diagnostics, but its observed attract value is code 0 and
    // the provisional offset-binary sampler maps that to -32768. Adding it at
    // full scale clips the byte-DAC waveform almost entirely to the negative
    // rail. Its board weight/mix is not yet calibrated.
    wire signed [17:0] sound_sum={{2{pcm8[15]}},pcm8}+{{2{speech_pcm[15]}},speech_pcm};
    wire signed [15:0] sound_out=sound_sum>18'sd32767 ? 16'sh7fff :
        sound_sum< -18'sd32768 ? 16'sh8000 : sound_sum[15:0];
    assign AUDIO_L=sound_out;
    assign AUDIO_R=sound_out;
    assign AUDIO_S=1'b1;
    assign AUDIO_MIX=2'b00;
    assign LED_USER=rom_download || speech_talk_status;
endmodule
