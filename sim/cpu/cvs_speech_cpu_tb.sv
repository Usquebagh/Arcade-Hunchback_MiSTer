// SPDX-License-Identifier: BSD-3-Clause
// Actual speech CPU with actual ROM/control/serial bus, external status fixture.
module cvs_speech_cpu_tb;
    reg clk=0,reset=1,reset_na=0,ready=1,sense=1,ctl_status=0,bit_req=0;
    reg program_dl_wr=0,data_dl_wr=0;
    reg [10:0] program_dl_addr=0;
    reg [11:0] data_dl_addr=0;
    reg [7:0] dl_data=0;
    reg [6:0] command=7'h42;
    wire ce,unused_main,unused_audio,unused_main_step;
    wire bit_ready,bit_valid,bit_data,pdc,ctl_wr,pdc_wr,intack;
    wire req,wr,memory_space,extended,data_port,flag;
    wire [15:0] bit_address;
    wire [2:0] control_latches;
    wire [3:0] ctl;
    wire [14:0] address;
    wire [7:0] write_data,read_data;
    wire [1:0] phase;
    cvs_clock clocks(.clk(clk),.reset(reset),.ce_main(unused_main),.ce_audio(unused_audio),
        .ce_main_step(unused_main_step),.ce_audio_step(ce));
    cvs_speech_cpu dut(.*);
    reg [7:0] program_bytes[0:2047],expected[0:16];
    reg [14:0] destinations[0:16];
    integer cycle=0,size=256,stores=0,last_transfer=-1,trace_start=-1,ctl_count=0,pdc_count=0;
    reg trace_on=0;
    task check(input condition,input [8*40-1:0] label_text,input integer want,input integer got);
        if(condition!==1'b1)begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":\"%0d\"}",label_text,cycle,want,got);$finish(1);
        end
    endtask
    task tick;
        begin
            clk=0;#5;
            if(!reset && req && ready)begin
                if(last_transfer>=0)check((cycle-last_transfer)%192==0,"speech_cpu_cadence",192,cycle-last_transfer);
                last_transfer=cycle;
                if(wr && memory_space && address>=15'h1d00)begin
                    check(stores<17 && address===destinations[stores],"speech_cpu_order",destinations[stores],address);
                    check(write_data===expected[stores],"speech_cpu_signature",expected[stores],write_data);stores=stores+1;
                    if(stores==2)ctl_status=1;
                    if(stores==3)sense=0;
                end
            end
            clk=1;#5;cycle=cycle+1;
            if(!reset)begin
                check(intack===1'b0,"speech_cpu_no_irq",0,intack);
                if(ctl_wr)ctl_count=ctl_count+1;
                if(pdc_wr)pdc_count=pdc_count+1;
            end
            if(trace_start>=0 && cycle==trace_start)begin $dumpon;trace_on=1;end
            if(trace_on && cycle==trace_start+2048)begin $dumpoff;trace_on=0;end
        end
    endtask
    task byte_out(input [7:0] value);begin program_bytes[size]=value;size=size+1;end endtask
    task instruction2(input [7:0] op,input [7:0] value);begin byte_out(op);byte_out(value);end endtask
    task store(input [12:0] addr);begin byte_out(8'hcc);byte_out({3'd0,addr[12:8]});byte_out(addr[7:0]);end endtask
    task load(input [12:0] addr);begin byte_out(8'h0c);byte_out({3'd0,addr[12:8]});byte_out(addr[7:0]);end endtask
    initial begin
        if($value$plusargs("trace_start=%d",trace_start))begin $dumpfile("failure.vcd");$dumpvars(1,cvs_speech_cpu_tb);$dumpoff;end
        for(integer n=0;n<2048;n=n+1)program_bytes[n]=8'h40;
        program_bytes[0]=8'h1f;program_bytes[1]=1;program_bytes[2]=0;program_bytes[2046]=8'h5a;
        expected[0]=8'ha0;expected[1]=8'hc2;expected[2]=8'h42;expected[3]=8'h20;
        expected[4]=8'h5a;expected[5]=8'hff;expected[6]=8'hff;
        for(integer n=0;n<7;n=n+1)destinations[n]=15'h1d00;
        for(integer n=7;n<15;n=n+1)destinations[n]=15'h1ddc+(n-7)/2;
        expected[7]=8'hff;expected[8]=0;
        for(integer n=9;n<15;n=n+2)begin expected[n]=8'h80;expected[n+1]=1;end
        destinations[15]=15'h1d00;expected[15]=8'hff;destinations[16]=15'h1d40;expected[16]=8'h0f;
        instruction2(8'h75,255);instruction2(8'h77,2);instruction2(8'h74,255);instruction2(8'h76,8'h20);
        byte_out(8'h12);store(13'h1d00);
        load(13'h1d80);store(13'h1d00);load(13'h1d80);store(13'h1d00);
        byte_out(8'h12);store(13'h1d00);
        instruction2(8'h04,255);store(13'h07fe);load(13'h07fe);store(13'h1d00);
        load(13'h1c00);store(13'h1d00);byte_out(8'h70);store(13'h1d00);
        for(integer n=7;n<17;n=n+1)begin instruction2(8'h04,expected[n]);store(destinations[n][12:0]);end
        byte_out(8'h40);tick;
        for(integer n=0;n<2048;n=n+1)begin program_dl_wr=1;program_dl_addr=n;dl_data=program_bytes[n];tick;end program_dl_wr=0;
        for(integer n=0;n<4096;n=n+1)begin data_dl_wr=1;data_dl_addr=n;dl_data=n==0?8'h5a:n==4095?8'ha6:8'(n*53+29);tick;end data_dl_wr=0;
        reset_na=1;repeat(4)tick;reset=0;
        for(integer n=0;n<15000 && !(req && wr && address==15'h1d00 && write_data===8'hc2);n=n+1)tick;
        check(req && wr && write_data===8'hc2,"speech_cpu_stall_fixture",8'hc2,write_data);
        ready=0;repeat(512)begin tick;check(stores==1,"speech_cpu_stall",1,stores);end ready=1;
        for(integer n=0;n<60000 && stores<17;n=n+1)tick;
        check(stores==17,"speech_cpu_completion",17,stores);repeat(2000)tick;
        check(!req && ctl===4'he && pdc===1'b1 && control_latches===3'h7,"speech_cpu_controls",4'he,ctl);
        check(ctl_count==6 && pdc_count==2 && bit_address===16'h7ff8,"speech_cpu_strobes",62,ctl_count*10+pdc_count);
        for(integer n=0;n<16;n=n+1)begin
            bit_req=1;tick;
            check(bit_valid && bit_data===(n<8?((8'ha6>>(n%8))&1'b1):((8'h5a>>(n%8))&1'b1)),"speech_cpu_serial",n<8?((8'ha6>>(n%8))&1):((8'h5a>>(n%8))&1),bit_data);
        end
        bit_req=0;tick;check(bit_address===16'd8 && !bit_valid,"speech_cpu_serial_wrap",8,bit_address);
        $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Actual speech CPU: 17 independent control/address signatures, /192, status/SENSE, ready stall, protected/unmapped reads and real serial ROM wrap; no TMS engine\"}",cycle);$finish(0);
    end
endmodule
