module mister_shell_tb;
    reg clk_50m=0;
    reg reset=0;
    tri [45:0] hps_bus;
    wire [11:0] hdmi_width=0,hdmi_height=0;
    wire clk_audio=0,sd_miso=0,sd_cd=0,ddram_busy=0,ddram_dout_ready=0;
    wire [63:0] ddram_dout=0;
    wire uart_cts=0,uart_rxd=0,uart_dsr=0,osd_status=0;
    wire [6:0] user_in=0;
    wire fb_vbl=0,fb_ll=0;
    localparam integer TEST_RESET_HOLD_CYCLES=32;
    emu #(.DIAGNOSTIC_PROBES(1'b1),.RESET_HOLD_CYCLES(TEST_RESET_HOLD_CYCLES)) dut(.CLK_50M(clk_50m),.RESET(reset),.HPS_BUS(hps_bus),
        .HDMI_WIDTH(hdmi_width),.HDMI_HEIGHT(hdmi_height),.CLK_AUDIO(clk_audio),
        .SD_MISO(sd_miso),.SD_CD(sd_cd),.DDRAM_BUSY(ddram_busy),
        .DDRAM_DOUT(ddram_dout),.DDRAM_DOUT_READY(ddram_dout_ready),
        .FB_VBL(fb_vbl),.FB_LL(fb_ll),.UART_CTS(uart_cts),.UART_RXD(uart_rxd),.UART_DSR(uart_dsr),
        .USER_IN(user_in),.OSD_STATUS(osd_status));
    always #5 clk_50m=~clk_50m;

    reg download=0,download_wr=0;
    reg [15:0] download_index=0;
    reg [26:0] download_addr=0;
    reg [7:0] download_data=0;
    reg [127:0] menu_status=0;
    reg [1:0] menu_buttons=0;
    reg [31:0] joy0=0,joy1=0;
    integer cycle=0;
    always @(posedge clk_50m)cycle=cycle+1;

    task automatic fail(input [255:0] label_text,input [31:0] want,input [31:0] got);
        begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":\"%b\",\"observed\":\"%b\"}",label_text,cycle,want,got);
            $dumpfile("failure.vcd");$dumpvars(0,mister_shell_tb);
            $finish(1);
        end
    endtask

    task automatic clocks(input integer count);
        repeat(count)begin @(posedge clk_50m);#1;end
    endtask

    task automatic check_input(input [31:0] player0,input [31:0] player1,
                               input [7:0] expected_in0,input [7:0] expected_in1,
                               input [255:0] label_text);
        begin
            joy0=player0;joy1=player1;#1;
            if(dut.in0!==expected_in0)fail(label_text,expected_in0,dut.in0);
            if(dut.in1!==expected_in1)fail(label_text,expected_in1,dut.in1);
        end
    endtask

    initial begin
        force dut.hps_io.ioctl_download=download;
        force dut.hps_io.ioctl_wr=download_wr;
        force dut.hps_io.ioctl_index=download_index;
        force dut.hps_io.ioctl_addr=download_addr;
        force dut.hps_io.ioctl_dout=download_data;
        force dut.hps_io.status=menu_status;
        force dut.hps_io.buttons=menu_buttons;
        force dut.hps_io.joystick_0=joy0;
        force dut.hps_io.joystick_1=joy1;
        reset=1;
        #1;
        if(dut.core_reset!==1'b1)fail("reset_waits_for_rom",1,dut.core_reset);
        reset=0;clocks(TEST_RESET_HOLD_CYCLES);
        if(dut.core_reset!==1'b1)fail("reset_waits_for_rom_after_minimum_hold",1,dut.core_reset);

        download=1;download_wr=1;download_index=0;download_addr=0;download_data=8'h5a;
        clocks(2);
        if(dut.core_reset!==1'b1)fail("reset_during_rom_download",1,dut.core_reset);
        if(dut.rom_loaded!==1'b0)fail("rom_not_complete_during_download",0,dut.rom_loaded);
        download=0;download_wr=0;
        clocks(1);
        if(dut.rom_loaded!==1'b1)fail("rom_load_completion",1,dut.rom_loaded);
        if(dut.core_reset!==1'b0)fail("reset_releases_after_rom",0,dut.core_reset);

        reset=1;#1;
        if(dut.core_reset!==1'b1)fail("external_reset_assertion",1,dut.core_reset);
        reset=0;clocks(1);
        if(dut.core_reset!==1'b1)fail("external_reset_minimum_hold",1,dut.core_reset);
        clocks(TEST_RESET_HOLD_CYCLES);
        if(dut.core_reset!==1'b0)fail("external_reset_releases_after_minimum_hold",0,dut.core_reset);

        menu_status=0;menu_buttons=0;joy0=0;joy1=0;#1;
        if(dut.in0!==8'hff)fail("joystick_idle_in0",8'hff,dut.in0);
        if(dut.in1!==8'hff)fail("joystick_idle_in1",8'hff,dut.in1);
        for(integer input_bit=0;input_bit<8;input_bit=input_bit+1)begin
            if(dut.in0[input_bit]!==1'b1)fail("joystick_idle_each_in0_bit",1,dut.in0[input_bit]);
            if(dut.in1[input_bit]!==1'b1)fail("joystick_idle_each_in1_bit",1,dut.in1[input_bit]);
        end
        if(dut.diagnostic_video_probes.diag_credit1!==1'b0 ||
           dut.diagnostic_video_probes.diag_credit2!==1'b0)
            fail("diagnostic_coin_idle",0,
                 {dut.diagnostic_video_probes.diag_credit1,dut.diagnostic_video_probes.diag_credit2});
        check_input(32'b1<<4,0,8'hdf,8'hff,"joystick_jump_active_low");
        check_input(0,32'b1<<4,8'hef,8'hff,"joystick_jump2_active_low");
        check_input(32'b1<<7,0,8'hf7,8'hff,"joystick_coin1_active_low");
        check_input(0,32'b1<<7,8'hfb,8'hff,"joystick_coin2_active_low");
        check_input(32'b1<<6,0,8'hfe,8'hff,"joystick_start1_active_low");
        check_input(32'b1<<5,0,8'hfd,8'hff,"joystick_start2_active_low");
        check_input(32'b1<<0,0,8'hff,8'hef,"joystick_p1_right_active_low");
        check_input(32'b1<<1,0,8'hff,8'hdf,"joystick_p1_left_active_low");
        check_input(0,32'b1<<0,8'hff,8'hfb,"joystick_p2_right_active_low");
        check_input(0,32'b1<<1,8'hff,8'hf7,"joystick_p2_left_active_low");
        check_input(32'b1<<3,0,8'hff,8'hff,"joystick_p1_up_not_in_cvs_horizontal_port");
        check_input(32'b1<<2,0,8'hff,8'hff,"joystick_p1_down_not_in_cvs_horizontal_port");
        menu_status=0;#1;
        // Reset the fixture between controls, then prove status remains visible
        // even if a coin bit is held; the diagnostic priority is intentional.
        joy0=(32'b1<<7);joy1=0;menu_status=0;#1;
        if(dut.diagnostic_green!==8'hff)fail("diagnostic_coin1_pressed",8'hff,dut.diagnostic_green);
        menu_status[14]=1;#1;
        if({dut.diagnostic_red,dut.diagnostic_green,dut.diagnostic_blue}!==24'hff0000)
            fail("diagnostic_status_priority",24'hff0000,
                 {dut.diagnostic_red,dut.diagnostic_green,dut.diagnostic_blue});
        menu_status=0;joy0=0;joy1=(32'b1<<7);#1;
        if(dut.diagnostic_blue!==8'hff)fail("diagnostic_coin2_pressed",8'hff,dut.diagnostic_blue);
        joy1=0;
        if(dut.video_rotated!==1'b1 || dut.rotate_ccw!==1'b0 || dut.no_rotate!==1'b0)
            fail("default_rotation_clockwise",1,{dut.video_rotated,dut.rotate_ccw,dut.no_rotate});
        if(dut.hps_io.video_rotated!==dut.video_rotated)
            fail("osd_rotation_feedback",dut.video_rotated,dut.hps_io.video_rotated);
        menu_status[12]=1'b1;#1;
        if(dut.rotate_ccw!==1'b1 || dut.video_rotated!==1'b1)
            fail("menu_rotation_ccw",3,{dut.rotate_ccw,dut.video_rotated});
        menu_status[12]=1'b0;#1;
        if(dut.no_rotate!==1'b0 || dut.video_rotated!==1'b1)
            fail("menu_rotation_cw",1,{dut.no_rotate,dut.video_rotated});
        // MRA defaults: Jump=A, Start 1=Start, Coin=Select, Start 2=X.
        joy0=(32'b1<<7)|(32'b1<<6)|(32'b1<<5)|(32'b1<<4)|(32'b1<<2);
        joy1=(32'b1<<7)|(32'b1<<4)|(32'b1<<3);
        #1;
        if(dut.in0!==8'b11000000)fail("joystick_player_coin_start_polarity",8'b11000000,dut.in0);
        if(dut.in1!==8'b11111111)fail("joystick_directions_jump2_polarity",8'b11111111,dut.in1);

        menu_status=0;
        menu_status[2:1]=2'b01;menu_status[4:3]=2'b10;menu_status[5]=1;
        menu_status[7]=1;menu_status[9:8]=2'b10;menu_status[11]=1;
        #1;
        if(dut.machine.dsw1!==8'hd9)fail("mame_dsw2_machine_port",8'hd9,dut.machine.dsw1);
        if(dut.machine.dsw2!==8'hf9)fail("mame_dsw3_machine_port",8'hf9,dut.machine.dsw2);
        menu_status[13]=1;#1;
        if(dut.machine.dsw1!==8'hf9)fail("mame_meter_pulses_dsw2_bit5",8'hf9,dut.machine.dsw1);
        menu_status[13]=0;

        menu_status[0]=1;clocks(1);
        if(dut.core_reset!==1'b1)fail("menu_reset_assertion",1,dut.core_reset);
        if(dut.rom_loaded!==1'b1 || dut.rom_download!==1'b0)
            fail("menu_reset_is_not_download_hold",1,{dut.rom_loaded,dut.rom_download});
        if(dut.machine.main_audio_video.main_video.main.reset!==1'b1 ||
           dut.machine.main_audio_video.main_video.main.reset_na!==1'b0 ||
           dut.machine.main_audio_video.audio.reset!==1'b1 ||
           dut.machine.speech.reset!==1'b1 || dut.machine.speech.reset_na!==1'b0)
            fail("menu_reset_reaches_all_game_cpus",1,0);
        // R[0] is a momentary OSD status bit. The shortened test parameter
        // exercises the hold/release sequence; production is configured for 20 ms.
        menu_status[0]=0;clocks(1);
        if(dut.core_reset!==1'b1)fail("menu_reset_minimum_hold",1,dut.core_reset);
        if(dut.machine.main_audio_video.main_video.main.reset!==1'b1 ||
           dut.machine.main_audio_video.audio.reset!==1'b1 || dut.machine.speech.reset!==1'b1)
            fail("menu_reset_minimum_hold_reaches_all_cpus",1,0);
        clocks(TEST_RESET_HOLD_CYCLES-2);
        if(dut.core_reset!==1'b1)fail("menu_reset_minimum_hold",1,dut.core_reset);
        clocks(1);
        if(dut.core_reset!==1'b0)fail("menu_reset_synchronized_release_after_hold",0,dut.core_reset);
        if(dut.machine.main_audio_video.main_video.main.reset!==1'b0 ||
           dut.machine.main_audio_video.main_video.main.reset_na!==1'b1 ||
           dut.machine.main_audio_video.audio.reset!==1'b0 ||
           dut.machine.speech.reset!==1'b0 || dut.machine.speech.reset_na!==1'b1)
            fail("menu_reset_release_reaches_all_game_cpus",0,1);
        begin : reset_vector_reexecution
            integer fetch_wait;
            fetch_wait=0;
            while(fetch_wait<128 && !(dut.machine.main_audio_video.main_video.main.req &&
                  dut.machine.main_audio_video.main_video.main.memory_space &&
                  dut.machine.main_audio_video.main_video.main.address==15'h0000)) begin
                clocks(1);fetch_wait=fetch_wait+1;
            end
            if(fetch_wait==128)fail("menu_reset_cpu_restarts_at_reset_vector",15'h0000,
                dut.machine.main_audio_video.main_video.main.address);
        end
        menu_buttons[1]=1;#1;
        if(dut.core_reset!==1'b1)fail("user_button_reset_assertion",1,dut.core_reset);
        menu_buttons=0;

        // The integrated discrete model owns byte-DAC routing and weighted
        // four-bit/discrete mixing; verify that its signed output reaches HPS.
        force dut.discrete_pcm=16'sd20000;
        force dut.speech_pcm=16'sd0;
        #1;
        if(dut.AUDIO_L!==16'd20000 || dut.AUDIO_R!==16'd20000)
            fail("audible_byte_dac_not_clipped_by_raw_four_bit",20000,dut.AUDIO_L);
        release dut.discrete_pcm;release dut.speech_pcm;

        $display("BDSM {\"status\":\"PASS\",\"observed\":\"MiSTer shell ROM-load/reset sequencing and MAME-compatible joystick mapping with actual CPU hierarchy\"}");
        $finish(0);
    end
endmodule
