// SPDX-License-Identifier: BSD-3-Clause
// Actual VHDL audio CPU, actual /192 enables and actual digital bus/RAM.
module cvs_audio_cpu_tb;
    reg clk=0,reset=1,reset_na=0,ready=1,dl_wr=0,command_trigger=0;
    reg [11:0] dl_addr=0;
    reg [7:0] dl_data=0,command=0;
    wire ce,unused_main,unused_audio,unused_main_step;
    wire intack,irq,interrupt_inhibit,interrupt_sample,dac8_wr,dac4_wr,discrete_wr;
    wire req,wr,memory_space,extended,data_port,flag;
    wire [7:0] dac8,write_data,read_data;
    wire [3:0] dac4,discrete;
    wire [14:0] address;
    wire [1:0] phase;
    cvs_clock clocks(.clk(clk),.reset(reset),.ce_main(unused_main),.ce_audio(unused_audio),
        .ce_main_step(unused_main_step),.ce_audio_step(ce));
    cvs_audio_cpu dut(.*,.sense(1'b1));
    reg [7:0] program_bytes[0:511],expected[0:8];
    integer cycle=0,size=256,stores=0,acks=0,eligible_samples=0,dac8_count=0,dac4_count=0,discrete_count=0,last_transfer=-1,trace_start=-1;
    reg previous_ack=0,previous_irq=0,trace_on=0;
    task check(input condition,input [8*40-1:0] label_text,input integer want,input integer got);
        if(condition!==1'b1)begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":\"%0d\"}",label_text,cycle,want,got);$finish(1);
        end
    endtask
    task tick;
        begin
            clk=0;#5;
            if(!reset && interrupt_sample)begin
                eligible_samples=eligible_samples+1;
                $display("AUDIO_IRQ_ELIGIBLE cycle=%0d command=%02x irq=%b intack=%b psu_ii=%b",cycle,command,irq,intack,interrupt_inhibit);
            end
            if(!reset && req && ready)begin
                if(last_transfer>=0)check((cycle-last_transfer)%192==0,"audio_cpu_cadence",192,cycle-last_transfer);
                last_transfer=cycle;
                if(wr && memory_space && address>=15'h1000 && address<15'h1009)begin
                    check(stores<9 && address==15'h1000+stores,"audio_cpu_store_order",stores,address-15'h1000);
                    check(write_data===expected[stores],"audio_cpu_signature",expected[stores],write_data);stores=stores+1;
                end
            end
            clk=1;#5;cycle=cycle+1;
            if(!reset)begin
                if(intack)check(interrupt_inhibit===1'b1,"audio_cpu_ii_on_intack",1,interrupt_inhibit);
                if(irq && !previous_irq)
                    $display("AUDIO_IRQ_SAMPLE cycle=%0d command=%02x irq=%b intack=%b psu_ii=%b",cycle,command,irq,intack,interrupt_inhibit);
                if(intack && !previous_ack)
                    $display("AUDIO_IRQ_ACCEPT cycle=%0d irq=%b intack=%b psu_ii=%b",cycle,irq,intack,interrupt_inhibit);
                previous_irq=irq;
                if(intack && !previous_ack)acks=acks+1;previous_ack=intack;
                if(dac8_wr)dac8_count=dac8_count+1;
                if(dac4_wr)dac4_count=dac4_count+1;
                if(discrete_wr)discrete_count=discrete_count+1;
            end
            if(trace_start>=0 && cycle==trace_start)begin $dumpon;trace_on=1;end
            if(trace_on && cycle==trace_start+2048)begin $dumpoff;trace_on=0;end
        end
    endtask
    task byte_out(input [7:0] value);begin program_bytes[size]=value;size=size+1;end endtask
    task instruction2(input [7:0] op,input [7:0] data);begin byte_out(op);byte_out(data);end endtask
    task store(input [12:0] addr);begin byte_out(8'hcc);byte_out({3'd0,addr[12:8]});byte_out(addr[7:0]);end endtask
    task load(input [12:0] addr);begin byte_out(8'h0c);byte_out({3'd0,addr[12:8]});byte_out(addr[7:0]);end endtask
    initial begin
        if($value$plusargs("trace_start=%d",trace_start))begin $dumpfile("failure.vcd");$dumpvars(1,cvs_audio_cpu_tb);$dumpoff;end
        expected[0]=8'ha0;expected[1]=8'h5a;expected[2]=8'h5a;expected[3]=8'ha1;expected[4]=8'h9b;
        expected[5]=8'h80;expected[6]=8'h9b;expected[7]=8'hff;expected[8]=8'h66;
        for(integer n=0;n<512;n=n+1)program_bytes[n]=8'h40;
        program_bytes[0]=8'h1f;program_bytes[1]=1;program_bytes[2]=0;
        size=3;byte_out(8'h12);store(13'h1003);load(13'h1800);store(13'h1004);store(13'h1840);
        instruction2(8'h04,255);for(integer n=0;n<4;n=n+1)store(13'h1880+n);
        instruction2(8'h04,1);for(integer n=0;n<4;n=n+1)store(13'h1884+n);
        instruction2(8'h04,0);store(13'h1881);instruction2(8'h04,8'h80);store(13'h1886);byte_out(8'h37);
        size=256;instruction2(8'h75,255);instruction2(8'h77,2);instruction2(8'h74,255);instruction2(8'h76,8'h20);
        byte_out(8'h12);store(13'h1000);instruction2(8'h04,8'h5a);store(13'h1001);load(13'h1001);store(13'h1002);
        instruction2(8'h74,8'h20);byte_out(8'h40);
        byte_out(8'h12);store(13'h1005);load(13'h1800);store(13'h1006);byte_out(8'h70);store(13'h1007);
        byte_out(8'hf0);instruction2(8'h04,8'h66);store(13'h1008);byte_out(8'h40);
        tick;
        check(req===1'b0,"audio_cpu_async_reset_request",0,req);
        check(intack===1'b0,"audio_cpu_async_reset_intack",0,intack);
        check(interrupt_inhibit===1'b0,"audio_cpu_async_reset_ii",0,interrupt_inhibit);
        for(integer n=0;n<512;n=n+1)begin dl_wr=1;dl_addr=n;dl_data=program_bytes[n];tick;end
        dl_wr=0;reset_na=1;repeat(4)tick;reset=0;
        for(integer n=0;n<15000 && !(req && wr && address==15'h1001);n=n+1)tick;
        check(req && wr && address==15'h1001,"audio_cpu_stall_fixture",15'h1001,address);
        ready=0;repeat(512)begin tick;check(stores==1,"audio_cpu_stall",1,stores);end ready=1;
        for(integer n=0;n<10000 && stores<3;n=n+1)tick;
        check(stores==3,"audio_cpu_ram",3,stores);repeat(3000)tick;
        check(!req && acks==0,"audio_cpu_halt",0,acks);
        check(interrupt_inhibit===1'b0,"audio_cpu_ii_idle_before_irq",0,interrupt_inhibit);
        command=8'h9b;command_trigger=1;tick;command_trigger=0;
        for(integer n=0;n<30000 && stores<9;n=n+1)tick;
        check(stores==9 && acks==1,"audio_cpu_completion",9,stores);
        check(eligible_samples>0,"audio_cpu_interrupt_boundary_reached",1,eligible_samples);
        check(dac8===8'h9b && dac4===4'hd && discrete===4'hb,"audio_cpu_controls",16'hbd9b,{discrete,dac4,dac8});
        check(dac8_count==1 && dac4_count==5 && discrete_count==5,"audio_cpu_strobes",551,dac8_count+10*dac4_count+100*discrete_count);
        check(irq===1'b0,"audio_cpu_irq_clear",0,irq);
        check(interrupt_inhibit===1'b0,"audio_cpu_ii_cleared_by_rete",0,interrupt_inhibit);
        $display("AUDIO_RETE_RETURN cycle=%0d irq=%b intack=%b psu_ii=%b",cycle,irq,intack,interrupt_inhibit);
        $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Actual audio CPU/RAM: nine independent signatures, /192 cadence, ready stall, HALT/vector/RETE and digital DAC/discrete writes\"}",cycle);$finish(0);
    end
endmodule
