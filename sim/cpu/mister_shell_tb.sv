module mister_shell_tb;
    reg clk_50m=0;
    reg reset=0;
    tri [45:0] hps_bus;
    wire [11:0] hdmi_width=0,hdmi_height=0;
    wire clk_audio=0,sd_miso=0,sd_cd=0,ddram_busy=0,ddram_dout_ready=0;
    wire [63:0] ddram_dout=0;
    wire uart_cts=0,uart_rxd=0,uart_dsr=0,osd_status=0;
    wire [6:0] user_in=0;
    emu dut(.CLK_50M(clk_50m),.RESET(reset),.HPS_BUS(hps_bus),
        .HDMI_WIDTH(hdmi_width),.HDMI_HEIGHT(hdmi_height),.CLK_AUDIO(clk_audio),
        .SD_MISO(sd_miso),.SD_CD(sd_cd),.DDRAM_BUSY(ddram_busy),
        .DDRAM_DOUT(ddram_dout),.DDRAM_DOUT_READY(ddram_dout_ready),
        .UART_CTS(uart_cts),.UART_RXD(uart_rxd),.UART_DSR(uart_dsr),
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
        reset=0;clocks(2);
        if(dut.core_reset!==1'b1)fail("reset_waits_for_rom",1,dut.core_reset);

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
        if(dut.core_reset!==1'b1)fail("reset_release_stage_one",1,dut.core_reset);
        clocks(1);
        if(dut.core_reset!==1'b0)fail("reset_two_clock_release",0,dut.core_reset);

        menu_status=0;menu_buttons=0;joy0=0;joy1=0;#1;
        if(dut.in0!==8'hff)fail("joystick_idle_in0",8'hff,dut.in0);
        if(dut.in1!==8'hff)fail("joystick_idle_in1",8'hff,dut.in1);
        joy0=(32'b1<<9)|(32'b1<<10)|(32'b1<<4)|(32'b1<<2);
        joy1=(32'b1<<9)|(32'b1<<10)|(32'b1<<4)|(32'b1<<3);
        #1;
        if(dut.in0!==8'b11000000)fail("joystick_player_coin_jump_polarity",8'b11000000,dut.in0);
        if(dut.in1!==8'b11011011)fail("joystick_jump2_polarity",8'b11011011,dut.in1);

        menu_status=0;
        menu_status[2:1]=2'b01;menu_status[4:3]=2'b10;menu_status[5]=1;
        menu_status[7]=1;menu_status[9:8]=2'b10;menu_status[11]=1;
        #1;
        if(dut.machine.dsw1!==8'hd9)fail("mame_dsw2_machine_port",8'hd9,dut.machine.dsw1);
        if(dut.machine.dsw2!==8'hf9)fail("mame_dsw3_machine_port",8'hf9,dut.machine.dsw2);

        menu_status[0]=1;#1;
        if(dut.core_reset!==1'b1)fail("menu_reset_assertion",1,dut.core_reset);
        menu_status[0]=0;menu_buttons[1]=1;#1;
        if(dut.core_reset!==1'b1)fail("user_button_reset_assertion",1,dut.core_reset);
        menu_buttons=0;

        $display("BDSM {\"status\":\"PASS\",\"observed\":\"MiSTer shell ROM-load/reset sequencing and MAME-compatible joystick mapping with actual CPU hierarchy\"}");
        $finish(0);
    end
endmodule
