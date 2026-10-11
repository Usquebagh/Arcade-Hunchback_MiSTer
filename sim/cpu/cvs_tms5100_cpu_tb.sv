// SPDX-License-Identifier: BSD-3-Clause
// Actual CPU/control bus/controller; external LPC talk-status fixture only.
module cvs_tms5100_cpu_tb;
    reg clk=0,reset=1,reset_na=0,ready=1,sense=1,talk_status=1;
    reg program_dl_wr=0,data_dl_wr=0;
    reg [10:0] program_dl_addr=0;
    reg [11:0] data_dl_addr=0;
    reg [7:0] dl_data=0;
    reg [6:0] command=7'h42;
    wire ce,unused_main,unused_audio,unused_main_step;
    wire bit_req,bit_ready,bit_valid,bit_data,pdc,ctl_wr,pdc_wr,intack;
    wire req,wr,memory_space,extended,data_port,flag;
    wire [15:0] bit_address;
    wire [2:0] control_latches;
    wire [3:0] ctl,ctl_read,address_nibble;
    wire [14:0] address;
    wire [7:0] write_data,read_data;
    wire [1:0] phase;
    wire ctl_output,start,slow,datapath_reset,address_load,branch,busy,protocol_error;
    cvs_clock clocks(.clk(clk),.reset(reset),.ce_main(unused_main),.ce_audio(unused_audio),
        .ce_main_step(unused_main_step),.ce_audio_step(ce));
    cvs_speech_cpu cpu(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(ce),.ready(ready),.sense(sense),
        .program_dl_wr(program_dl_wr),.program_dl_addr(program_dl_addr),.data_dl_wr(data_dl_wr),
        .data_dl_addr(data_dl_addr),.dl_data(dl_data),.command(command),.ctl_status(ctl_read[0]),
        .bit_req(bit_req),.bit_ready(bit_ready),.bit_valid(bit_valid),.bit_data(bit_data),
        .bit_address(bit_address),.control_latches(control_latches),.ctl(ctl),.pdc(pdc),
        .ctl_wr(ctl_wr),.pdc_wr(pdc_wr),.intack(intack),.req(req),.wr(wr),.memory_space(memory_space),
        .extended(extended),.data_port(data_port),.flag(flag),.address(address),
        .write_data(write_data),.read_data(read_data),.phase(phase));
    cvs_tms5100_control controller(.*);
    reg [7:0] program_bytes[0:2047],signatures[0:7];
    reg [3:0] expected_ctl[0:7];
    reg [7:0] directions=8'b00100100;
    integer cycle=0,size=256,reads=0,stores=0,starts=0,resets=0;
    integer trace_start=-1,last_transfer=-1,control_writes=0,pdc_writes=0;
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
                if(last_transfer>=0)check((cycle-last_transfer)%192==0,"tms_cpu_cadence",192,cycle-last_transfer);
                last_transfer=cycle;
                if(memory_space && !wr && address==15'h1d80)begin
                    check(reads<8,"tms_cpu_read_count",8,reads);
                    check(ctl_output===directions[reads] && ctl_read===expected_ctl[reads],"tms_cpu_direction",expected_ctl[reads],ctl_read);
                    check(starts==1 && resets==(reads==7?1:0),"tms_cpu_start",1,starts);
                    reads=reads+1;
                end
                if(memory_space && wr && address==15'h1d00)begin
                    check(stores<8 && write_data===signatures[stores],"tms_cpu_signature",signatures[stores],write_data);stores=stores+1;
                end
            end
            clk=1;#5;cycle=cycle+1;
            if(!reset)begin
                if(start)starts=starts+1;
                if(datapath_reset)resets=resets+1;
                if(ctl_wr)control_writes=control_writes+1;
                if(pdc_wr)pdc_writes=pdc_writes+1;
                check(!intack && !protocol_error && !busy && !bit_req && !bit_valid && !address_load && !branch && !slow,"tms_cpu_isolation",0,protocol_error);
            end
            if(trace_start>=0 && cycle==trace_start)begin $dumpon;trace_on=1;end
            if(trace_on && cycle==trace_start+2048)begin $dumpoff;trace_on=0;end
        end
    endtask
    task byte_out(input [7:0] value);begin program_bytes[size]=value;size=size+1;end endtask
    task instruction2(input [7:0] op,input [7:0] value);begin byte_out(op);byte_out(value);end endtask
    task store(input [12:0] addr);begin byte_out(8'hcc);byte_out({3'd0,addr[12:8]});byte_out(addr[7:0]);end endtask
    task write_byte(input [12:0] addr,input [7:0] value);begin instruction2(8'h04,value);store(addr);end endtask
    task pulse_pdc;begin write_byte(13'h1ddf,0);write_byte(13'h1ddf,8'h80);end endtask
    task ctl_command(input [3:0] code);
        begin write_byte(13'h1ddd,code[1]?0:8'h80);write_byte(13'h1dde,code[2]?0:8'h80);pulse_pdc;end
    endtask
    task read_signature;begin byte_out(8'h0c);byte_out(8'h1d);byte_out(8'h80);store(13'h1d00);end endtask
    initial begin
        if($value$plusargs("trace_start=%d",trace_start))begin $dumpfile("failure.vcd");$dumpvars(1,cvs_tms5100_cpu_tb);$dumpoff;end
        for(integer n=0;n<2048;n=n+1)program_bytes[n]=8'h40;
        program_bytes[0]=8'h1f;program_bytes[1]=1;program_bytes[2]=0;
        for(integer n=0;n<8;n=n+1)signatures[n]=n==2?8'h42:8'hc2;
        expected_ctl[0]=4'ha;expected_ctl[1]=4'he;expected_ctl[2]=1;expected_ctl[3]=4'he;
        expected_ctl[4]=4'h4;expected_ctl[5]=0;expected_ctl[6]=4'h4;expected_ctl[7]=0;
        instruction2(8'h75,255);instruction2(8'h77,2);instruction2(8'h74,255);instruction2(8'h76,8'h20);
        ctl_command(4'ha);read_signature;
        ctl_command(4'he);read_signature;pulse_pdc;read_signature;pulse_pdc;read_signature;
        ctl_command(4'h4);read_signature;pulse_pdc;read_signature;pulse_pdc;read_signature;
        ctl_command(0);read_signature;ctl_command(4'ha);byte_out(8'h40);tick;
        for(integer n=0;n<2048;n=n+1)begin program_dl_wr=1;program_dl_addr=n;dl_data=program_bytes[n];tick;end program_dl_wr=0;
        reset_na=1;repeat(4)tick;reset=0;
        for(integer n=0;n<90000 && !(reads==2 && req && !wr && address==15'h1d80);n=n+1)tick;
        check(reads==2 && req && address==15'h1d80,"tms_cpu_stall_fixture",2,reads);
        ready=0;repeat(512)begin tick;check(reads==2 && ctl_output && ctl_read==1,"tms_cpu_stall",2,reads);end ready=1;
        for(integer n=0;n<150000 && stores<8;n=n+1)tick;
        check(stores==8 && reads==8,"tms_cpu_completion",8,stores);
        repeat(20000)tick;
        check(!req && starts==2 && resets==1 && control_writes==10 && pdc_writes==18,"tms_cpu_events",2,starts);
        check(bit_address===16'h0610,"tms_cpu_pointer",16'h0610,bit_address);
        $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Actual speech CPU/control bus/controller: eight CTL-direction/status signatures, two starts, one reset, shared CTL latch/PDC inversion, ready stall and /192; LPC talk status remains external\"}",cycle);$finish(0);
    end
endmodule
