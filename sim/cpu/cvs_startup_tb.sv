// SPDX-License-Identifier: BSD-3-Clause
// Actual CPU/memory/PVI machine. Scan is paused; this checks initialization only.
module cvs_startup_tb;
    reg clk=0,reset=1,reset_na=0,video_reset=1,scan_run=0,ready=1,dl_wr=0;
    wire cheat_reset=reset;
    wire [128:0] cheat_code=129'd0;
    reg [15:0] dl_addr=0;
    reg [7:0] dl_data=0;
    wire pixel_valid,pixel_ce_all,display_enable,bullet_present,background_collision,hsync_n,vsync_n,audio_trigger,intack;
    wire req,wr,memory_space,extended,data_port,flag;
    wire [7:0] out_x,out_y,red,green,blue,collision_events,collision,video_fx,audio_command;
    wire [7:0] write_data,read_data,h_count;
    wire [2:0] raw_pixel,pvi_irq;
    wire [3:0] palette_index;
    wire [14:0] address;
    wire [1:0] phase;
    wire [8:0] v_count;
    cvs_machine dut(.*,.in0(8'hff),.in1(8'hff),.in2(8'hff),.in3(8'hff),.dsw1(8'hff),.dsw2(8'hff));
    reg [7:0] image_bytes[0:51231];
    reg [26:0] expected_writes[0:8191];
    wire [26:0] bus_write={memory_space,memory_space?2'b00:{extended,data_port},address,flag,write_data};
    integer cycle=0,stores=0,expected_count,resume_pc,image_fd,image_size,trace_start=-1;
    reg trace_on=0;
    string image_name,expect_name;
    task fail(input [8*40-1:0] label_text,input integer want,input integer got);
        begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":\"%0d\"}",label_text,cycle,want,got);
            $finish(1);
        end
    endtask
    // Dump the actual PVI register arrays at the authenticated first-return
    // checkpoint.  The ordering follows the three RTL bank instances.
    task dump_s2636_checkpoint;
        integer chip_index,address_index;
        reg [7:0] value;
        begin
            for(chip_index=0;chip_index<3;chip_index=chip_index+1) begin
                for(address_index=0;address_index<256;address_index=address_index+1) begin
                    case(chip_index)
                        0: value=dut.video.pvis.pvi[0].chip.registers[address_index];
                        1: value=dut.video.pvis.pvi[1].chip.registers[address_index];
                        default: value=dut.video.pvis.pvi[2].chip.registers[address_index];
                    endcase
                    $display("RTL_S2636_REG chip=%0d address=%02X value=%02X",chip_index,address_index,value);
                end
            end
        end
    endtask
    task tick;
        reg completed;
        begin
            completed=0;clk=0;#5;
            if(!reset && req && ready)begin
                if(wr)begin
                    if(stores>=expected_count)fail("startup_extra_write",expected_count,stores+1);
                    if(bus_write !== expected_writes[stores])fail("startup_write",expected_writes[stores],bus_write);
                    stores=stores+1;
                end else if(memory_space && phase==0 && address==resume_pc && stores==expected_count)completed=1;
            end
            clk=1;#5;cycle=cycle+1;
            if(completed)begin
                dump_s2636_checkpoint;
                $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Unchanged authenticated ROM completed first initialization call: %0d modeled memory/I/O writes and return fetch\"}",cycle,stores);
                $finish(0);
            end
            if(trace_start>=0 && cycle==trace_start)begin $dumpon;trace_on=1;end
            if(trace_on && cycle==trace_start+2048)begin $dumpoff;trace_on=0;end
        end
    endtask
    initial begin
        if($value$plusargs("trace_start=%d",trace_start))begin $dumpfile("failure.vcd");$dumpvars(1,cvs_startup_tb);$dumpoff;end
        if(!$value$plusargs("image=%s",image_name) || !$value$plusargs("expect=%s",expect_name) ||
           !$value$plusargs("count=%d",expected_count) || !$value$plusargs("resume=%d",resume_pc) ||
           expected_count<1 || expected_count>8192)begin
            $display("BDSM {\"status\":\"ERROR\",\"reason\":\"Missing/invalid startup fixture\"}");$finish(0);
        end
        image_fd=$fopen(image_name,"rb");image_size=$fread(image_bytes,image_fd);$fclose(image_fd);
        if(image_size!=51232)begin $display("BDSM {\"status\":\"ERROR\",\"reason\":\"Startup image length\"}");$finish(0);end
        $readmemh(expect_name,expected_writes,0,expected_count-1);
        tick;
        for(integer n=0;n<51232;n=n+1)begin dl_wr=1;dl_addr=n;dl_data=image_bytes[n];tick;end
        dl_wr=0;reset_na=1;video_reset=0;repeat(4)tick;reset=0;
        for(integer n=0;n<4000000;n=n+1)tick;
        $display("BDSM {\"status\":\"ERROR\",\"reason\":\"Startup return not reached within bounded fixture\"}");$finish(0);
    end
endmodule
