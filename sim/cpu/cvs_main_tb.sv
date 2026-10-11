// SPDX-License-Identifier: BSD-3-Clause
// Synthetic program, actual adapted CPU, clock enables and SV memory/I/O.
module cvs_main_tb;
    reg clk=0, reset=1, reset_na=0, ready=1, dl_wr=0;
    reg [14:0] dl_addr=0;
    reg [7:0] dl_data=0;
    wire ce_main, ce_audio, ce, ce_audio_step;
    wire intack, req, wr, memory_space, extended, data_port, flag;
    wire [14:0] address;
    wire [7:0] write_data, read_data, scroll, video_fx, audio_command;
    wire [1:0] char_page, char_mode, phase;
    wire collision_clear, audio_trigger;
    wire [2:0] sprite_select;
    wire sprite_rd, sprite_wr;
    wire [7:0] sprite_addr, sprite_dout;
    cvs_clock clocks(.clk(clk),.reset(reset),.ce_main(ce_main),.ce_audio(ce_audio),
        .ce_main_step(ce),.ce_audio_step(ce_audio_step));
    cvs_main dut(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(ce),.ready(ready),
        .irq(1'b0),.sense(1'b1),.ivec(8'h03),.intack(intack),
        .dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),
        .in0(8'h91),.in1(8'h26),.in2(8'he3),.in3(8'h58),.dsw1(8'had),.dsw2(8'h72),
        .collision(8'h39),.char_page(char_page),.char_mode(char_mode),.scroll(scroll),
        .video_fx(video_fx),.audio_command(audio_command),.collision_clear(collision_clear),
        .audio_trigger(audio_trigger),.video_tile_rd(1'b0),.video_tile_addr(10'd0),.video_bullet_addr(8'd0),.video_glyph_rd(1'b0),.video_glyph_addr(10'd0),.video_palette_rd(1'b0),.video_palette_addr(4'd0),
        .sprite_din(8'h8b),.sprite_select(sprite_select),
        .sprite_rd(sprite_rd),.sprite_wr(sprite_wr),.sprite_addr(sprite_addr),.sprite_dout(sprite_dout),
        .req(req),.wr(wr),.memory_space(memory_space),.extended(extended),.data_port(data_port),
        .flag(flag),.address(address),.write_data(write_data),.read_data(read_data),.phase(phase));
    integer cycle=0, size=0, signatures=0, triggers=0, clears=0, sprite_reads=0, sprite_writes=0;
    integer trace_start=-1, last_transfer=-1, steps=0, stall_count=0;
    reg trace_on=0, stall_started=0;
    reg [14:0] held_address;
    reg [7:0] program_bytes[0:1023];
    reg [7:0] expected[0:23];
    task check(input condition,input [8*40-1:0] label_text,input integer want,input integer got);
        begin
            if (condition !== 1'b1) begin
                // Preserve X/Z observations as valid structured evidence.
                $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":\"%0d\"}",label_text,cycle,want,got);
                $finish(1);
            end
        end
    endtask
    task tick;
        begin
            clk=0;#5;
            if (!reset) begin
                if (ce) steps=steps+1;
                check(!req || ce,"connected_request_enable",0,req && !ce);
                if (req && ready) begin
                    if (last_transfer>=0) check(cycle-last_transfer>=96,"connected_cadence",96,cycle-last_transfer);
                    last_transfer=cycle;
                    if (memory_space && wr && address>=15'h1c00 && address<=15'h1c17) begin
                        check(address==15'h1c00+signatures,"connected_signature_order",signatures,address-15'h1c00);
                        check(write_data===expected[signatures],"connected_signature",expected[signatures],write_data);
                        signatures=signatures+1;
                    end
                    if (sprite_rd) begin
                        sprite_reads=sprite_reads+1;
                        check(sprite_select==4 && sprite_addr==8'h53,"connected_sprite_read",4,sprite_select);
                    end
                    if (sprite_wr) begin
                        sprite_writes=sprite_writes+1;
                        check(sprite_select==2 && sprite_addr==8'h53 && sprite_dout==8'h9b,"connected_sprite_write",8'h9b,sprite_dout);
                    end
                end
            end
            clk=1;#5;cycle=cycle+1;
            if (audio_trigger) triggers=triggers+1;
            if (collision_clear) clears=clears+1;
            if (trace_start>=0 && cycle==trace_start) begin $dumpon;trace_on=1;end
            if (trace_on && cycle==trace_start+2048) begin $dumpoff;trace_on=0;end
        end
    endtask
    task byte_out(input [7:0] value);
        begin program_bytes[size]=value;size=size+1;end
    endtask
    task instruction2(input [7:0] op,input [7:0] operand);
        begin byte_out(op);byte_out(operand);end
    endtask
    task store(input [12:0] target);
        begin byte_out(8'hcc);byte_out({3'b000,target[12:8]});byte_out(target[7:0]);end
    endtask
    task load(input [12:0] target);
        begin byte_out(8'h0c);byte_out({3'b000,target[12:8]});byte_out(target[7:0]);end
    endtask
    initial begin
        if ($value$plusargs("trace_start=%d",trace_start)) begin
            $dumpfile("failure.vcd");$dumpvars(1,cvs_main_tb);$dumpoff;
        end
        expected[0]=8'h26;expected[1]=8'had;expected[2]=8'hb4;expected[3]=8'he5;
        expected[4]=8'h83;expected[5]=8'ha4;expected[6]=8'h41;expected[7]=8'h62;
        expected[8]=8'h80;expected[9]=8'h39;expected[10]=0;
        expected[11]=8'h8b;
        for(integer n=0;n<12;n=n+1) expected[n+12]=expected[n];
        instruction2(8'h75,8'hff);instruction2(8'h77,8'h0a);instruction2(8'h74,8'hff);
        instruction2(8'h04,8'h41);store(13'h1405);
        instruction2(8'h04,8'h62);store(13'h1812);
        instruction2(8'h76,8'h40);
        instruction2(8'h04,8'h83);store(13'h1405);
        instruction2(8'h04,8'ha4);store(13'h1812);
        instruction2(8'h54,8'ha2);store(13'h1c00);
        instruction2(8'h04,8'hb4);store(13'h1753);
        instruction2(8'h54,8'hf7);store(13'h1c01);
        instruction2(8'h04,8'he5);store(13'h1753);
        instruction2(8'h54,8'h82);load(13'h1753);store(13'h1c02);
        instruction2(8'h54,8'hc0);load(13'h1753);store(13'h1c03);
        load(13'h1405);store(13'h1c04);load(13'h1812);store(13'h1c05);
        instruction2(8'h74,8'h40);
        load(13'h1405);store(13'h1c06);load(13'h1812);store(13'h1c07);
        byte_out(8'h12);store(13'h1c08);
        byte_out(8'h30);store(13'h1c09);byte_out(8'h70);store(13'h1c0a);
        load(13'h1553);store(13'h1c0b);
        instruction2(8'h04,8'h9b);store(13'h1653);
        // Read each signature back through actual system RAM, then store it in
        // a second range. This detects a disconnected/late RAM response.
        for(integer n=0;n<12;n=n+1) begin load(13'h1c00+n);store(13'h1c0c+n);end
        instruction2(8'h04,8'h80);byte_out(8'hb0);byte_out(8'hb0);
        instruction2(8'h04,0);byte_out(8'hb0);
        instruction2(8'h04,8'hff);byte_out(8'hb0);
        instruction2(8'h04,8'h25);instruction2(8'hd4,8'h00);
        instruction2(8'h04,8'h31);byte_out(8'hf0);byte_out(8'h40);
        tick;
        for(integer n=0;n<size;n=n+1) begin dl_wr=1;dl_addr=n;dl_data=program_bytes[n];tick;end
        dl_wr=0;reset_na=1;repeat(4)tick;reset=0;
        // Stall the first enabled transaction. No primed-response or state change
        // may be caused by an unaccepted request. This is a readiness contract.
        for(integer n=0;n<100000;n=n+1) begin
            clk=0;#1;
            if (!stall_started && ce) begin
                ready=0;#1; // settle the combinational pending-transfer mux
                stall_started=1;held_address=address;
            end
            if (stall_started && stall_count<250) begin
                check(address===held_address,"connected_stall",held_address,address);
                stall_count=stall_count+1;
            end else ready=1;
            tick;
            if (video_fx==8'h31) begin
                repeat(400)tick;
                check(signatures==24,"connected_completion",24,signatures);
                check(triggers==2,"connected_audio_edges",2,triggers);
                check(clears==1,"connected_clear_event",1,clears);
                check(scroll==8'hda,"connected_scroll",8'hda,scroll);
                check(char_page==3 && char_mode==0,"connected_bank_hold",3,char_page);
                check(sprite_select==0 && !sprite_rd && !sprite_wr,"connected_sprite_isolation",0,sprite_select);
                check(sprite_reads==1 && sprite_writes==1,"connected_sprite_events",2,sprite_reads+sprite_writes);
                $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"24 CPU signatures/readbacks, /96 transfers, stall and I/O/sprite events\"}",cycle);
                $finish(0);
            end
        end
        $display("BDSM {\"status\":\"ERROR\",\"reason\":\"Synthetic CPU program did not complete within bounded run\"}");
        $finish(2);
    end
endmodule
