// SPDX-License-Identifier: BSD-3-Clause
// Independent command sequence executed by both actual CPUs, no RAM preload.
module cvs_av_machine_tb;
    reg clk=0,reset=1,reset_na=0,video_reset=1,scan_run=0,ready=1,audio_ready=1;
    reg dl_wr=0;
    reg [15:0] dl_addr=0;
    reg [7:0] dl_data=0;
    wire req,wr,memory_space,extended,data_port,flag,audio_trigger;
    wire audio_req,audio_wr,audio_memory_space,audio_intack,audio_irq,audio_interrupt_inhibit,audio_interrupt_sample,dac8_wr;
    wire [14:0] address,audio_address;
    wire [7:0] write_data,audio_write_data,audio_read_data,audio_command,dac8;
    wire [3:0] dac4;
    wire sample_ce;
    wire signed [15:0] pcm8,pcm4;
    cvs_av_machine dut(.clk(clk),.reset(reset),.reset_na(reset_na),.video_reset(video_reset),
        .cheat_reset(reset),.cheat_code(129'd0),
        .scan_run(scan_run),.ready(ready),
        .audio_ready(audio_ready),.audio_sense(1'b1),
        .dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),
        .in0(8'hff),.in1(8'hff),.in2(8'hff),.in3(8'hff),.dsw1(8'hff),.dsw2(8'hff),
        .req(req),.wr(wr),.memory_space(memory_space),.extended(extended),.data_port(data_port),
        .flag(flag),.address(address),.write_data(write_data),.audio_command(audio_command),.audio_trigger(audio_trigger),
        .audio_req(audio_req),.audio_wr(audio_wr),.audio_memory_space(audio_memory_space),
        .audio_address(audio_address),.audio_write_data(audio_write_data),.audio_read_data(audio_read_data),
        .audio_intack(audio_intack),.audio_irq(audio_irq),.audio_interrupt_inhibit(audio_interrupt_inhibit),
        .audio_interrupt_sample(audio_interrupt_sample),
        .dac8(dac8),.dac8_wr(dac8_wr),.dac4(dac4),
        .sample_ce(sample_ce),.pcm8(pcm8),.pcm4(pcm4));
    reg [7:0] main_program[0:1023],audio_program[0:4095],commands[0:4],responses[0:1];
    integer cycle=0,size=0,updates=0,triggers=0,acks=0,reads=0,stores=0,dacs=0;
    integer last_main=-1,last_audio=-1,trace_start=-1;
    reg previous_ack=0,trace_on=0;
    longint unsigned sample_edges=0;
    integer samples=0,want_pcm8=0,want_pcm4=0;
    task check(input condition,input [8*40-1:0] label_text,input integer want,input integer got);
        if(condition!==1'b1)begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":\"%0d\"}",label_text,cycle,want,got);$finish(1);
        end
    endtask
    task tick;
        reg command_write,command_read,want_sample;
        begin
            clk=0;#5;command_write=0;command_read=0;
            want_sample=0;
            if(reset)begin sample_edges=0;want_pcm8=0;want_pcm4=0;samples=0;end
            else begin
                sample_edges=sample_edges+1;
                want_sample=(sample_edges*48000/57272724)!=((sample_edges-1)*48000/57272724);
                if(want_sample)begin want_pcm8=dac8*256-32768;want_pcm4=dac4*4096-32768;samples=samples+1;end
            end
            if(!reset && req && ready)begin
                if(last_main>=0)check((cycle-last_main)%96==0,"av_main_cadence",96,cycle-last_main);
                last_main=cycle;
                if(wr && !memory_space && !extended && !data_port)begin
                    check(updates<5,"av_command_count",5,updates+1);
                    check(write_data===commands[updates],"av_main_command",commands[updates],write_data);
                    check(flag===(updates<3 ? 1'b0 : 1'b1),"av_main_flag",updates>=3,flag);
                    command_write=1;
                end
            end
            if(!reset && audio_req && audio_ready)begin
                if(last_audio>=0)check((cycle-last_audio)%192==0,"av_audio_cadence",192,cycle-last_audio);
                last_audio=cycle;
                if(audio_memory_space && audio_address==15'h1800 && !audio_wr)command_read=1;
                if(audio_memory_space && audio_address==15'h1000 && audio_wr)begin
                    check(stores<2,"av_store_count",2,stores+1);
                    check(audio_write_data===responses[stores],"av_ram_command",responses[stores],audio_write_data);stores=stores+1;
                end
            end
            clk=1;#5;cycle=cycle+1;
            check(sample_ce===want_sample,"av_sample_cadence",want_sample,sample_ce);
            check($signed(pcm8)===want_pcm8,"av_sample8",want_pcm8,$signed(pcm8));
            check($signed(pcm4)===want_pcm4,"av_sample4",want_pcm4,$signed(pcm4));
            if(!reset)begin
                if(audio_intack)check(audio_interrupt_inhibit===1'b1,"av_ii_on_intack",1,audio_interrupt_inhibit);
                if(audio_intack)check(audio_interrupt_sample===1'b0,"av_sample_not_eligible_after_accept",0,audio_interrupt_sample);
                if(audio_intack && !previous_ack)acks=acks+1;previous_ack=audio_intack;
                if(command_write)begin
                    check(audio_command===commands[updates],"av_command_latch",commands[updates],audio_command);
                    check(audio_trigger===(updates==1 || updates==4),"av_trigger",updates==1 || updates==4,audio_trigger);
                    updates=updates+1;
                end else check(audio_trigger===1'b0,"av_trigger_width",0,audio_trigger);
                if(audio_trigger)triggers=triggers+1;
                if(command_read)begin
                    check(reads<2,"av_read_count",2,reads+1);
                    check(audio_read_data===responses[reads],"av_audio_command",responses[reads],audio_read_data);reads=reads+1;
                end
                if(dac8_wr)begin
                    check(dacs<2,"av_dac_count",2,dacs+1);
                    check(dac8===responses[dacs],"av_dac_command",responses[dacs],dac8);dacs=dacs+1;
                end
            end
            if(trace_start>=0 && cycle==trace_start)begin $dumpon;trace_on=1;end
            if(trace_on && cycle==trace_start+2048)begin $dumpoff;trace_on=0;end
        end
    endtask
    task byte_out(input [7:0] value);begin main_program[size]=value;size=size+1;end endtask
    task instruction2(input [7:0] op,input [7:0] data);begin byte_out(op);byte_out(data);end endtask
    task send_command(input [7:0] value);begin instruction2(8'h04,value);byte_out(8'hb0);end endtask
    initial begin
        if($value$plusargs("trace_start=%d",trace_start))begin $dumpfile("failure.vcd");$dumpvars(1,cvs_av_machine_tb);$dumpoff;end
        commands[0]=8'h40;commands[1]=8'h9b;commands[2]=8'hda;commands[3]=8'h40;commands[4]=8'hc6;
        responses[0]=8'h9b;responses[1]=8'hc6;
        for(integer n=0;n<1024;n=n+1)main_program[n]=8'hc0;
        for(integer n=0;n<4096;n=n+1)audio_program[n]=8'h40;
        instruction2(8'h75,255);instruction2(8'h77,2);instruction2(8'h74,255);instruction2(8'h76,8'h20);
        send_command(8'h40);send_command(8'h9b);repeat(80)byte_out(8'hc0);
        send_command(8'hda);repeat(16)byte_out(8'hc0);
        instruction2(8'h76,8'h40);send_command(8'h40);repeat(16)byte_out(8'hc0);
        send_command(8'hc6);repeat(80)byte_out(8'hc0);byte_out(8'h40);
        // Audio reset jumps over vector 03. ISR reads real command, stores RAM,
        // writes the DAC and RETE resumes the idle HALT/branch loop.
        audio_program[0]=8'h1f;audio_program[1]=1;audio_program[2]=0;
        audio_program[3]=8'h0c;audio_program[4]=8'h18;audio_program[5]=0;
        audio_program[6]=8'hcc;audio_program[7]=8'h10;audio_program[8]=0;
        audio_program[9]=8'hcc;audio_program[10]=8'h18;audio_program[11]=8'h40;audio_program[12]=8'h37;
        audio_program[256]=8'h75;audio_program[257]=255;audio_program[258]=8'h77;audio_program[259]=2;
        audio_program[260]=8'h74;audio_program[261]=255;audio_program[262]=8'h76;audio_program[263]=8'h20;
        audio_program[264]=8'h74;audio_program[265]=8'h20;audio_program[266]=8'h40;
        audio_program[267]=8'h1f;audio_program[268]=1;audio_program[269]=8'h0a;
        tick;
        for(integer n=0;n<1024;n=n+1)begin dl_wr=1;dl_addr=n;dl_data=main_program[n];tick;end
        for(integer n=0;n<4096;n=n+1)begin dl_wr=1;dl_addr=16'h8000+n;dl_data=audio_program[n];tick;end
        // Neighboring auxiliary windows have hostile bytes, and must not alias.
        for(integer n=0;n<4096;n=n+1)begin dl_addr=16'h9000+n;dl_data=8'hff;tick;end
        dl_wr=0;reset_na=1;repeat(4)tick;reset=0;
        for(integer n=0;n<15000 && !(audio_req && !audio_wr && audio_address==15'h1800);n=n+1)tick;
        check(audio_req && audio_address==15'h1800,"av_read_stall_fixture",15'h1800,audio_address);
        audio_ready=0;repeat(512)begin tick;check(reads==0 && stores==0 && dacs==0,"av_audio_stall",0,reads+stores+dacs);end audio_ready=1;
        for(integer n=0;n<50000 && !(updates==4 && req && wr && !memory_space && !extended && !data_port);n=n+1)tick;
        check(updates==4 && req && wr,"av_write_stall_fixture",4,updates);
        ready=0;repeat(512)begin tick;check(updates==4 && acks==1 && audio_command===8'h40,"av_main_stall",4,updates);end ready=1;
        repeat(50000)tick;
        check(updates==5 && triggers==2,"av_main_events",52,updates*10+triggers);
        check(acks==2,"av_ack_count",2,acks);
        check(reads==2 && stores==2 && dacs==2,"av_audio_events",222,reads*100+stores*10+dacs);
        check(audio_irq===1'b0 && audio_command===8'hc6 && dac8===8'hc6,"av_completion",8'hc6,dac8);
        check(samples==sample_edges*48000/57272724 && samples>30,"av_sample_count",sample_edges*48000/57272724,samples);
        $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Two actual CPUs: image isolation, FLAG-independent WRTC, two real IRQ/RETE command reads and RAM/DAC signatures, /96 and /192, independent ready stalls\"}",cycle);$finish(0);
    end
endmodule
