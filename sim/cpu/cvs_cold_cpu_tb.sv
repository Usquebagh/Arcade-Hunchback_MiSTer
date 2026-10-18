// SPDX-License-Identifier: BSD-3-Clause
// Cold synthesized CPU: no simulation-only register initialization is allowed.
module cvs_cold_cpu_tb;
    reg clk=0,reset=1,reset_na=0,dl_wr=0;
    reg [14:0] dl_addr=0;
    reg [7:0] dl_data=0;
    wire ce,req,wr,memory_space,flag;
    wire [14:0] address;
    wire [7:0] write_data;
    cvs_clock clocks(.clk(clk),.reset(reset),.ce_main(),.ce_audio(),.ce_main_step(ce),.ce_audio_step());
    cvs_main dut(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(ce),.ready(1'b1),
        .cheat_reset(reset),.cheat_code(129'd0),
        .irq(1'b0),.sense(1'b0),.ivec(8'd0),.intack(),.dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),
        .in0(8'hff),.in1(8'hff),.in2(8'hff),.in3(8'hff),.dsw1(8'hff),.dsw2(8'hff),.collision(8'd0),
        .char_page(),.char_mode(),.scroll(),.video_fx(),.audio_command(),.collision_clear(),.audio_trigger(),
        .video_tile_rd(1'b0),.video_tile_addr(10'd0),.video_bullet_addr(8'd0),.video_glyph_rd(1'b0),.video_glyph_addr(10'd0),
        .video_palette_rd(1'b0),.video_palette_addr(4'd0),.sprite_din(8'hff),.sprite_select(),.sprite_rd(),.sprite_wr(),.sprite_addr(),.sprite_dout(),
        .req(req),.wr(wr),.memory_space(memory_space),.extended(),.data_port(),.flag(flag),.address(address),.write_data(write_data),.read_data(),.phase());
    reg [7:0] program_bytes[0:19];
    integer cycle=0,stores=0,trace_start=-1;
    reg trace_on=0;
    task check(input condition,input [8*40-1:0] label_text,input integer want,input integer got);
        if(condition !== 1'b1)begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":\"%0d\"}",label_text,cycle,want,got);$finish(1);
        end
    endtask
    task tick;
        begin
            clk=0;#5;
            if(!reset && req && wr && memory_space)begin
                check(address===(stores==0?15'h1cff:stores==1?15'h1dff:15'h1eff) && flag===1'b1 && write_data===(stores<2?8'd0:8'h27),
                    "cold_cpu_self_xor",stores==0?15'h1cff:stores==1?15'h1dff:15'h1eff,address);stores=stores+1;
            end
            clk=1;#5;cycle=cycle+1;
            if(trace_start>=0 && cycle==trace_start)begin $dumpon;trace_on=1;end
            if(trace_on && cycle==trace_start+2048)begin $dumpoff;trace_on=0;end
        end
    endtask
    initial begin
        if($value$plusargs("trace_start=%d",trace_start))begin $dumpfile("failure.vcd");$dumpvars(1,cvs_cold_cpu_tb);$dumpoff;end
        program_bytes[0]=8'h76;program_bytes[1]=8'h60; // FLAG/inhibit, no general-register initialization
        program_bytes[2]=8'h77;program_bytes[3]=8'hff;
        program_bytes[4]=8'h75;program_bytes[5]=8'h18;
        program_bytes[6]=8'h20;program_bytes[7]=8'hc1; // architectural zero, then R1=R0
        program_bytes[8]=8'hcd;program_bytes[9]=8'h5c;program_bytes[10]=0;
        program_bytes[11]=8'hcd;program_bytes[12]=8'h7d;program_bytes[13]=0;
        program_bytes[14]=8'h13; // CC zero, all non-CC initialized PSL bits retained
        program_bytes[15]=8'hcc;program_bytes[16]=8'h1e;program_bytes[17]=8'hff;program_bytes[18]=8'h40;
        tick;
        for(integer n=0;n<19;n=n+1)begin dl_wr=1;dl_addr=n;dl_data=program_bytes[n];tick;end
        dl_wr=0;reset_na=1;repeat(4)tick;reset=0;
        for(integer n=0;n<10000 && stores<3;n=n+1)tick;
        check(stores==3,"cold_cpu_completion",3,stores);
        $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Cold synthesized CPU self-XOR clears R0 and indexed R1 without inferred general-register initialization\"}",cycle);$finish(0);
    end
endmodule
