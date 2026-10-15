// SPDX-License-Identifier: BSD-3-Clause
// Actual CPU/bus/engine/clock, downloaded stop fixture; no external TALK model.
module cvs_speech_machine_tb;
    reg clk=0,reset=1,reset_na=0,ready=1,sense=1,dl_wr=0;
    reg [15:0] dl_addr=0;
    reg [7:0] dl_data=0;
    reg [6:0] command=7'h42;
    wire ce,sample_tick,sample_valid,protocol_error;
    wire signed [15:0] pcm;
    wire bit_req,bit_ready,bit_valid,bit_data,pdc,ctl_wr,pdc_wr,intack;
    wire req,wr,memory_space,extended,data_port,flag;
    wire [15:0] bit_address;
    wire [2:0] control_latches;
    wire [3:0] ctl,ctl_read,energy_index;
    wire [4:0] pitch_index;
    wire [49:0] coefficient_indices;
    wire [14:0] address;
    wire [7:0] write_data,read_data;
    wire [1:0] phase;
    wire ctl_output,talk_status,decoded_frame;
    cvs_speech_machine dut(.*);
    reg [7:0] program_bytes[0:2047],signatures[0:7];
    reg [3:0] expected_ctl[0:7];
    reg [7:0] directions=8'b00100100;
    integer cycle=0,size=256,reads=0,stores=0,samples=0,decoded=0,bits=0;
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
                check((^address)!==1'bx && (!wr || (^write_data)!==1'bx),"speech_machine_known_bus",0,address);
                if(memory_space && !wr && address==15'h1d80)begin
                    check(reads<8,"tms_cpu_read_count",8,reads);
                    check(ctl_output===directions[reads] && ctl_read===expected_ctl[reads],"tms_cpu_direction",expected_ctl[reads],ctl_read);
                    reads=reads+1;
                end
                if(memory_space && wr && address==15'h1d00)begin
                    if(stores<8)check(write_data===signatures[stores],"tms_cpu_signature",signatures[stores],write_data);
                    else check(stores==8 && write_data===8'd0,"speech_machine_pointer_load",0,write_data);
                    stores=stores+1;
                end
            end
            if(!reset && bit_req && bit_ready)bits=bits+1;
            clk=1;#5;cycle=cycle+1;
            if(!reset)begin
                if(sample_valid)begin
                    samples=samples+1;
                    check(pcm===16'sd0 || pcm=== -16'sd1,"speech_machine_pcm",0,pcm);
                end
                if(decoded_frame)begin
                    decoded=decoded+1;
                    check(energy_index===4'hf && pitch_index===0,"speech_machine_stop_frame",15,energy_index);
                end
                if(ctl_wr)control_writes=control_writes+1;
                if(pdc_wr)pdc_writes=pdc_writes+1;
                check(intack===0 && protocol_error===0,"speech_machine_isolation",0,protocol_error);
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
        if($value$plusargs("trace_start=%d",trace_start))begin $dumpfile("failure.vcd");$dumpvars(1,cvs_speech_machine_tb);$dumpoff;end
        for(integer n=0;n<2048;n=n+1)program_bytes[n]=8'h40;
        program_bytes[0]=8'h1f;program_bytes[1]=1;program_bytes[2]=0;
        for(integer n=0;n<8;n=n+1)signatures[n]=n==2?8'h42:8'hc2;
        expected_ctl[0]=4'ha;expected_ctl[1]=4'he;expected_ctl[2]=1;expected_ctl[3]=4'he;
        expected_ctl[4]=4'h4;expected_ctl[5]=0;expected_ctl[6]=4'h4;expected_ctl[7]=0;
        instruction2(8'h75,255);instruction2(8'h77,2);instruction2(8'h74,255);instruction2(8'h76,8'h20);
        ctl_command(4'ha);read_signature;
        ctl_command(4'he);read_signature;pulse_pdc;read_signature;pulse_pdc;read_signature;
        ctl_command(4'h4);read_signature;pulse_pdc;read_signature;pulse_pdc;read_signature;
        ctl_command(0);read_signature;write_byte(13'h1d00,0);ctl_command(4'ha);byte_out(8'h40);tick;
        for(integer n=0;n<2048;n=n+1)begin dl_wr=1;dl_addr=16'h9000+n;dl_data=program_bytes[n];tick;end
        for(integer n=0;n<4096;n=n+1)begin dl_addr=16'h9800+n;dl_data=n==0?8'h0f:0;tick;end
        // Neighboring main/audio/character/PROM windows must be isolated.
        for(integer n=0;n<4;n=n+1)begin
            dl_addr=n==0?16'h8000:n==1?16'h8fff:n==2?16'ha800:16'hc800;dl_data=n<2?8'hff:0;tick;
        end
        dl_wr=0;
        reset_na=1;repeat(4)tick;reset=0;
        for(integer n=0;n<90000 && !(reads==2 && req && !wr && address==15'h1d80);n=n+1)tick;
        check(reads==2 && req && address==15'h1d80,"tms_cpu_stall_fixture",2,reads);
        ready=0;repeat(512)begin tick;check(reads==2 && ctl_output && ctl_read==1,"tms_cpu_stall",2,reads);end ready=1;
        for(integer n=0;n<150000 && stores<9;n=n+1)tick;
        check(stores==9 && reads==8,"tms_cpu_completion",9,stores);
        repeat(20000)tick;
        check(!req && talk_status && control_writes==10 && pdc_writes==18,"speech_machine_events",10,control_writes);
        check(bit_address===16'd0,"tms_cpu_pointer",0,bit_address);
        check(samples>0 && bits==0,"speech_machine_clock_running",1,samples);
        for(integer n=0;n<4000000 && talk_status;n=n+1)tick;
        check(!talk_status && decoded==1 && bits==4,"speech_machine_stop",1,decoded);
        check(bit_address===16'd4,"speech_machine_serial_position",4,bit_address);
        repeat(15000)tick;
        check(pcm=== -16'sd1 && !req,"speech_machine_idle",-1,pcm);
        $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Actual speech S2650/bus/engine/nominal clock: eight firmware status signatures, ready stall, downloader isolation, one four-bit stop frame and talk drain to idle; no actual game voice/physical clock qualification\"}",cycle);$finish(0);
    end
endmodule
