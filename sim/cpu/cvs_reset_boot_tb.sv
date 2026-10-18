// SPDX-License-Identifier: BSD-3-Clause
// Independent synthetic reset-vector contract through the actual MiSTer shell.
module cvs_reset_boot_tb;
    reg clk=0,reset=0;
    tri [45:0] hps_bus;
    emu #(.RESET_HOLD_CYCLES(8)) dut(.CLK_50M(clk),.RESET(reset),.HPS_BUS(hps_bus),
        .HDMI_WIDTH(12'd0),.HDMI_HEIGHT(12'd0),.CLK_AUDIO(1'b0),
        .SD_MISO(1'b0),.SD_CD(1'b0),.DDRAM_BUSY(1'b0),
        .DDRAM_DOUT(64'd0),.DDRAM_DOUT_READY(1'b0),
        .FB_VBL(1'b0),.FB_LL(1'b0),.UART_CTS(1'b0),.UART_RXD(1'b0),.UART_DSR(1'b0),
        .USER_IN(7'd0),.OSD_STATUS(1'b0));
    always #5 clk=~clk;
    reg download=0,download_wr=0;
    reg [26:0] download_addr=0;
    reg [7:0] download_data=0;
    integer cycle=0;
    integer accesses[0:2];
    wire [2:0] requests={dut.machine.speech_req,dut.machine.audio_req,dut.machine.req};
    wire [2:0] writes={dut.machine.speech_wr,dut.machine.audio_wr,dut.machine.wr};
    wire [2:0] memories={dut.machine.speech_memory_space,dut.machine.audio_memory_space,dut.machine.memory_space};
    wire [14:0] addresses[0:2];
    assign addresses[0]=dut.machine.address;
    assign addresses[1]=dut.machine.audio_address;
    assign addresses[2]=dut.machine.speech_address;
    wire [2:0] resets={dut.machine.speech.reset,dut.machine.main_audio_video.audio.reset,
                       dut.machine.main_audio_video.main_video.main.reset};
    task automatic fail(input string label_text,input integer want,input integer got);
        $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":%0d}",label_text,cycle,want,got);
        $finish;
    endtask
    // Observe accepted reads before the edge, independently of CPU internals.
    always @(posedge clk) begin
        cycle=cycle+1;
        for(integer cpu=0;cpu<3;cpu=cpu+1)begin
            if(!dut.core_reset && !resets[cpu] && requests[cpu] && accesses[cpu]<3)begin
                if(writes[cpu] || !memories[cpu])fail("reset_boot_memory_read",1,0);
                if(addresses[cpu] != (accesses[cpu]<2 ? accesses[cpu]+1 : 'h100+cpu*'h20))
                    fail(cpu==0 ? "reset_boot_main_branch" : cpu==1 ? "reset_boot_audio_branch" : "reset_boot_speech_branch",
                         accesses[cpu]<2 ? accesses[cpu]+1 : 'h100+cpu*'h20, int'(addresses[cpu]));
                accesses[cpu]=accesses[cpu]+1;
            end
        end
    end
    task automatic clocks(input integer count);
        repeat(count)begin @(posedge clk);#1;end
    endtask
    task automatic put(input integer address,input [7:0] data);
        @(negedge clk);download_addr=27'(address);download_data=data;download_wr=1;
        clocks(1);
    endtask
    // Reapply changing HPS output values explicitly: Verilator 5.020 samples
    // procedural force RHS at execution, unlike Icarus continuous-force RHS.
    always @(download or download_wr or download_addr or download_data)begin
        force dut.hps_io.ioctl_download=download;
        force dut.hps_io.ioctl_wr=download_wr;
        force dut.hps_io.ioctl_index=16'd0;
        force dut.hps_io.ioctl_addr=download_addr;
        force dut.hps_io.ioctl_dout=download_data;
    end
    initial begin
        for(integer cpu=0;cpu<3;cpu=cpu+1)accesses[cpu]=0;
        // Isolate reset-vector execution from the scan's initial vblank IRQ.
        // This is external interrupt stimulus, never CPU/ROM initialization.
        force dut.machine.main_audio_video.main_video.irq=1'b0;
        reset=1;clocks(2);reset=0;
        download=1;
        for(integer cpu=0;cpu<3;cpu=cpu+1)begin
            // Main 0x0000, audio 0x8000, speech 0x9000 downloader windows.
            put(cpu==0 ? 0 : cpu==1 ? 'h8000 : 'h9000,8'h1f);
            put((cpu==0 ? 0 : cpu==1 ? 'h8000 : 'h9000)+1,8'h01);
            put((cpu==0 ? 0 : cpu==1 ? 'h8000 : 'h9000)+2,8'(cpu*'h20));
            put((cpu==0 ? 0 : cpu==1 ? 'h8000 : 'h9000)+'h100+cpu*'h20,8'h40);
        end
        @(negedge clk);download_wr=0;download=0;
        for(integer wait_cycle=0;wait_cycle<4096;wait_cycle=wait_cycle+1)begin
            clocks(1);
            if(accesses[0]==3 && accesses[1]==3 && accesses[2]==3)begin
                $display("BDSM {\"status\":\"PASS\",\"observed\":\"Zero-power-up top-level main/audio/speech operand reads 1,2 then targets 0x100/0x120/0x140; 9 accepted reads\"}");
                $finish;
            end
        end
        fail("reset_boot_completion",9,accesses[0]+accesses[1]+accesses[2]);
    end
endmodule
