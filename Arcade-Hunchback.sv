// SPDX-License-Identifier: BSD-3-Clause
// Private MiSTer shell integration; board clocks, input wiring and analog mix remain provisional.
module emu #(
    parameter integer RESET_HOLD_CYCLES = 1_140_000
) (
    `include "sys/emu_ports.vh"
);
    `include "build_id.v"
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
    // OSD actions are listed before the terminal joystick metadata entries.
    localparam CONF_STR={
        "Hunchback (CVS);",
        "-;",
        "O[2:1],Coin A,1C1C,3C1C,2C1C,4C1C;",
        "O[4:3],Coin B,1C2C,1C3C,1C4C,1C5C;",
        "O[5],Lives,3,5;",
        "O[7],Cabinet,Upright,Cocktail;",
        "O[9:8],Bonus life,10k,20k,40k,80k;",
        "O[12],Orientation,Rotate CW,Rotate CCW;",
        "O[14],Audio Probe,Off,On;",
        "O[15],Probe page,Audio,Speech;",
        "O[17:16],Audio mix,Normal,Speech only,Effects only;",
        "O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
        "-;",
        "R[0],Reset;",
        "C,Cheats;",
        "-;",
        "J1,Jump,Start 2,Start 1,Coin;",
        "jn,A,X,Start,Select;",
        "V,", `BUILD_ID, ";"
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
    wire cheat_download=ioctl_download && ioctl_index==16'd255;
    reg [127:0] cheat_bits=128'd0;
    reg [128:0] cheat_code=129'd0;
    always @(posedge clk_sys) begin
        cheat_code[128] <= 1'b0;
        if (cheat_download && ioctl_wr) begin
            cheat_bits <= {cheat_bits[119:0],ioctl_dout};
            if (&ioctl_addr[3:0]) begin
                cheat_code[127:0] <= {cheat_bits[119:0],ioctl_dout};
                cheat_code[128] <= 1'b1;
            end
        end
    end
    wire cheat_reset=core_reset || (cheat_download && ioctl_wr && ioctl_addr==0);
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
    // Meter Pulses (DSW2 bit 5), Registration and Registration Length (DSW3
    // bits 0..1) are not in the OSD; they stay at MAME's defaults (2, On, 3)
    // so stale saved status bits 10, 11 and 13 have no effect.
    wire [7:0] mame_dsw2={2'b11,1'b0,status[5],coin_b,status[2:1]};
    wire [7:0] mame_dsw3={3'b111,status[7],bonus,2'b11};

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
    wire audio_trigger,intack,audio_intack,audio_irq,audio_interrupt_inhibit,audio_interrupt_sample;
    wire dac8_wr,dac4_wr,discrete_wr;
    wire [7:0] dac8;
    wire [7:0] h_count;
    wire [8:0] v_count;
    wire audio_req,audio_wr,audio_memory_space;
    wire [14:0] audio_address;

    // OSD-selectable audio diagnostics: event bars latch once seen and stay
    // black if absent. The PSU-II bar records whether interrupt inhibit was
    // ever set; the heartbeat is an independent pixel-clock control.
    assign diagnostic_red=red;
    assign diagnostic_green=green;
    assign diagnostic_blue=blue;
    reg audio_probe_command_trigger=1'b0;
    reg audio_probe_audio_irq=1'b0;
    reg audio_probe_audio_intack=1'b0;
    reg audio_probe_command_nonzero=1'b0;
    reg audio_probe_ii_seen=1'b0;
    reg audio_probe_interrupt_sample=1'b0;
    reg [23:0] audio_probe_heartbeat_count=24'd0;
    reg audio_probe_heartbeat=1'b0;
    always @(posedge clk_sys) begin
        if(core_reset) begin
            audio_probe_command_trigger<=1'b0;
            audio_probe_audio_irq<=1'b0;
            audio_probe_audio_intack<=1'b0;
            audio_probe_command_nonzero<=1'b0;
            audio_probe_ii_seen<=1'b0;
            audio_probe_interrupt_sample<=1'b0;
            audio_probe_heartbeat_count<=24'd0;
            audio_probe_heartbeat<=1'b0;
        end else begin
            if(audio_trigger) audio_probe_command_trigger<=1'b1;
            if(audio_irq) audio_probe_audio_irq<=1'b1;
            if(audio_intack) audio_probe_audio_intack<=1'b1;
            if(audio_command!=8'd0) audio_probe_command_nonzero<=1'b1;
            if(audio_interrupt_inhibit) audio_probe_ii_seen<=1'b1;
            if(audio_interrupt_sample) audio_probe_interrupt_sample<=1'b1;
            // CLK_VIDEO is 57.272727 MHz. Toggle every quarter second for
            // two complete bright/dark cycles per second.
            if(audio_probe_heartbeat_count==24'd14_318_399) begin
                audio_probe_heartbeat_count<=24'd0;
                audio_probe_heartbeat<=~audio_probe_heartbeat;
            end else audio_probe_heartbeat_count<=audio_probe_heartbeat_count+24'd1;
        end
    end
    // Speech page: the same latch-once bars for the speech CPU and TMS5100.
    wire [15:0] speech_bit_address;
    wire speech_sample_tick,speech_sample_valid,speech_protocol_error,speech_talk_status;
    wire signed [15:0] pcm8,pcm4,speech_pcm,discrete_pcm;
    wire speech_req,speech_wr,speech_ctl_wr,speech_pdc_wr;
    wire [14:0] speech_address;
    reg speech_probe_left_vector=1'b0;
    reg speech_probe_command_nonzero=1'b0;
    reg speech_probe_tms_write=1'b0;
    reg speech_probe_talk=1'b0;
    reg speech_probe_pcm_nonzero=1'b0;
    reg speech_probe_protocol_error=1'b0;
    always @(posedge clk_sys) begin
        if(core_reset) begin
            speech_probe_left_vector<=1'b0;
            speech_probe_command_nonzero<=1'b0;
            speech_probe_tms_write<=1'b0;
            speech_probe_talk<=1'b0;
            speech_probe_pcm_nonzero<=1'b0;
            speech_probe_protocol_error<=1'b0;
        end else begin
            if(speech_req && !speech_wr && speech_address>=15'h0010) speech_probe_left_vector<=1'b1;
            if(audio_command[6:0]!=7'd0) speech_probe_command_nonzero<=1'b1;
            if(speech_ctl_wr || speech_pdc_wr) speech_probe_tms_write<=1'b1;
            if(speech_talk_status) speech_probe_talk<=1'b1;
            if(speech_sample_valid && speech_pcm!=16'sd0) speech_probe_pcm_nonzero<=1'b1;
            if(speech_protocol_error) speech_probe_protocol_error<=1'b1;
        end
    end
    wire speech_page=status[15];
    wire [6:0] probe_lit=speech_page ?
        {audio_probe_heartbeat,speech_probe_protocol_error,speech_probe_pcm_nonzero,speech_probe_talk,
         speech_probe_tms_write,speech_probe_command_nonzero,speech_probe_left_vector} : 7'd0;
    wire audio_probe_pixel=status[14] && display_enable && out_y<16;
    wire probe_bar0=out_x<35;
    wire probe_bar1=out_x>=35 && out_x<70;
    wire probe_bar2=out_x>=70 && out_x<105;
    wire probe_bar3=out_x>=105 && out_x<140;
    wire probe_bar4=out_x>=140 && out_x<175;
    wire probe_bar5=out_x>=175 && out_x<210;
    wire probe_bar6=out_x>=210;
    wire probe_heartbeat_lit=probe_bar6 && audio_probe_heartbeat;
    wire speech_probe_white=(probe_bar0 && probe_lit[0]) || (probe_bar1 && probe_lit[1]) ||
        (probe_bar2 && probe_lit[2]) || (probe_bar3 && probe_lit[3]) || (probe_bar4 && probe_lit[4]) ||
        (probe_bar6 && probe_lit[6]);
    // A protocol error is a fault: show it red only.
    wire speech_probe_red_only=probe_bar5 && probe_lit[5];
    wire [7:0] probe_red=audio_probe_pixel ? (speech_page ?
        (speech_probe_white || speech_probe_red_only ? 8'hff : 8'h00) :
        ((probe_bar3 && audio_probe_command_nonzero) || (probe_bar4 && audio_probe_ii_seen) ||
         (probe_bar5 && audio_probe_interrupt_sample) ||
         probe_heartbeat_lit ? 8'hff : 8'h00)) : diagnostic_red;
    wire [7:0] probe_green=audio_probe_pixel ? (speech_page ?
        (speech_probe_white ? 8'hff : 8'h00) :
        ((probe_bar1 && audio_probe_audio_irq) || (probe_bar2 && audio_probe_audio_intack) ||
         (probe_bar3 && audio_probe_command_nonzero) || probe_heartbeat_lit ? 8'hff : 8'h00)) : diagnostic_green;
    wire [7:0] probe_blue=audio_probe_pixel ? (speech_page ?
        (speech_probe_white ? 8'hff : 8'h00) :
        ((probe_bar0 && audio_probe_command_trigger) || (probe_bar2 && audio_probe_audio_intack) ||
         (probe_bar5 && audio_probe_interrupt_sample) || probe_heartbeat_lit ? 8'hff : 8'h00)) : diagnostic_blue;
    wire signed [15:0] audio_out;
    wire audio_sample_ce;
    wire cpu_reset,cpu_reset_na;
    cvs_cpu_reset cpu_reset_sequence(.clk(clk_sys),.reset_in(core_reset),
        .reset(cpu_reset),.reset_na(cpu_reset_na));
    cvs_full_machine machine (
        .clk(clk_sys),.reset(cpu_reset),.reset_na(cpu_reset_na),.video_reset(core_reset),.scan_run(1'b1),
        .ready(1'b1),.audio_ready(1'b1),.audio_sense(sense_380),.speech_ready(1'b1),.speech_sense(sense_380),
        .dl_wr(ioctl_wr && rom_download),.cheat_reset(cheat_reset),.cheat_code(cheat_code),
        .dl_addr(ioctl_addr[15:0]),.dl_data(ioctl_dout),
        .in0(in0),.in1(in1),.in2(8'hff),.in3(8'hff),.dsw1(mame_dsw2),.dsw2(mame_dsw3),
        .pixel_valid(pixel_valid),.pixel_ce_all(pixel_ce_all),.display_enable(display_enable),
        .out_x(out_x),.out_y(out_y),.red(red),.green(green),.blue(blue),.raw_pixel(raw_pixel),
        .pvi_irq(pvi_irq),.palette_index(palette_index),.bullet_present(bullet_present),
        .background_collision(background_collision),.hsync_n(hsync_n),.vsync_n(vsync_n),
        .collision_events(collision_events),.collision(collision),.video_fx(video_fx),
        .audio_command(audio_command),.audio_trigger(audio_trigger),.intack(intack),
        .audio_intack(audio_intack),.audio_irq(audio_irq),.audio_interrupt_inhibit(audio_interrupt_inhibit),
        .audio_interrupt_sample(audio_interrupt_sample),
        .dac8(dac8),.dac4(dac4),.discrete(discrete),
        .audio_req(audio_req),.audio_wr(audio_wr),.audio_memory_space(audio_memory_space),
        .audio_address(audio_address),
        .dac8_wr(dac8_wr),.dac4_wr(dac4_wr),.discrete_wr(discrete_wr),.sample_ce(audio_sample_ce),.pcm8(pcm8),.pcm4(pcm4),
        .discrete_pcm(discrete_pcm),
        .speech_sample_tick(speech_sample_tick),.speech_sample_valid(speech_sample_valid),
        .speech_protocol_error(speech_protocol_error),.speech_pcm(speech_pcm),.speech_talk_status(speech_talk_status),
        .speech_bit_address(speech_bit_address),
        .speech_req(speech_req),.speech_wr(speech_wr),.speech_address(speech_address),
        .speech_ctl_wr(speech_ctl_wr),.speech_pdc_wr(speech_pdc_wr)
    );

    wire mister_pixel_ce;
    cvs_mister_pixel_enable pixel_enable_delay(.clk(clk_sys),.reset(core_reset),
        .pixel_ce_in(pixel_ce_all),.pixel_ce_out(mister_pixel_ce));
    assign CLK_VIDEO=clk_sys;
    assign CE_PIXEL=mister_pixel_ce;
    wire [1:0] ar=status[122:121];
    // Native output is not usable with the current CVS raw timing, so expose
    // only the two verified framebuffer-rotation directions.
    wire no_rotate=1'b0;
    wire rotate_ccw=status[12];
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
        .VGA_R(probe_red),.VGA_G(probe_green),.VGA_B(probe_blue),
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
    assign VGA_R=probe_red;
    assign VGA_G=probe_green;
    assign VGA_B=probe_blue;
    assign VGA_HS=hsync_n;
    assign VGA_VS=vsync_n;
    assign VGA_DE=display_enable;

    // pcm4 is a raw offset-binary diagnostic sample and is not added here.
    // The resistor-weighted SP_LAT0..3 path is already included once inside
    // discrete_pcm, with the byte DAC and modeled discrete sources.
    // Couple the DAC/discrete mix before adding speech and before final
    // saturation so its idle offset cannot rail or erase the speech channel.
    // Diagnostic OSD mix: 0 normal, 1 speech only, 2 effects only.
    wire signed [15:0] mix_speech=status[17:16]==2'd2 ? 16'sd0 : speech_pcm;
    wire signed [15:0] mix_discrete=status[17:16]==2'd1 ? 16'sd0 : discrete_pcm;
    cvs_audio_output audio_output(.clk(clk_sys),.reset(core_reset),.sample_ce(audio_sample_ce),
        .speech_pcm(mix_speech),.discrete_pcm(mix_discrete),.audio_pcm(audio_out));
    assign AUDIO_L=audio_out;
    assign AUDIO_R=audio_out;
    assign AUDIO_S=1'b1;
    assign AUDIO_MIX=2'b00;
    assign LED_USER=rom_download || speech_talk_status;
endmodule
