// SPDX-License-Identifier: BSD-3-Clause
// Actual CPU/memory/timing/IRQ assembly, synthetic ROM and provisional timing.
module cvs_video_cpu_tb;
    reg clk=0, video_reset=1, cpu_reset=1, reset_na=0, dl_wr=0;
    reg [14:0] dl_addr=0;
    reg [7:0] dl_data=0;
    wire cpu_ce, vrst, irq, intack, req, wr, memory_space;
    wire [7:0] h_count, write_data;
    wire [8:0] v_count;
    wire [14:0] address;
    cvs_clock clocks(.clk(clk),.reset(cpu_reset),.ce_main(),.ce_audio(),
        .ce_main_step(cpu_ce),.ce_audio_step());
    cvs_video_timing timing(.clk(clk),.reset(video_reset),.run(1'b1),
        .ce_position(),.line_start(),.frame_start(),.h_count(h_count),.v_count(v_count),
        .hrst(),.vrst(vrst),.cbf(),.blank(),.hsync_n(),.vsync_n());
    cvs_vblank_irq interrupt_latch(.clk(clk),.reset(cpu_reset),.vblank(vrst),
        .intack(intack),.irq(irq));
    cvs_main dut(.clk(clk),.reset(cpu_reset),.reset_na(reset_na),.ce(cpu_ce),.ready(1'b1),
        .cheat_reset(cpu_reset),.cheat_code(129'd0),
        .irq(irq),.sense(vrst),.ivec(8'h03),.intack(intack),
        .dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),
        .in0(8'hff),.in1(8'hff),.in2(8'hff),.in3(8'hff),.dsw1(8'hff),.dsw2(8'hff),
        .collision(8'h00),.char_page(),.char_mode(),.scroll(),.video_fx(),.audio_command(),
        .collision_clear(),.audio_trigger(),.video_tile_rd(1'b0),.video_tile_addr(10'd0),.video_bullet_addr(8'd0),.video_glyph_rd(1'b0),.video_glyph_addr(10'd0),.video_palette_rd(1'b0),.video_palette_addr(4'd0),
        .sprite_din(8'h00),.sprite_select(),
        .sprite_rd(),.sprite_wr(),.sprite_addr(),.sprite_dout(),.req(req),.wr(wr),
        .memory_space(memory_space),.extended(),.data_port(),.flag(),.address(address),
        .write_data(write_data),.read_data(),.phase());
    reg [7:0] program_bytes[0:383];
    integer cycle=0, ack_count=0, blank_count=0, stores=0;
    integer trace_start=-1;
    reg previous_ack=0, previous_blank=0, trace_on=0;
    task check(input condition,input [8*40-1:0] label_text,input integer want,input integer got);
        begin
            if(condition !== 1'b1) begin
                $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":\"%0d\"}",label_text,cycle,want,got);
                $finish(1);
            end
        end
    endtask
    task tick;
        begin
            clk=0;#5;
            if(!cpu_reset) begin
                if(vrst && !previous_blank) blank_count=blank_count+1;
                previous_blank=vrst;
                if(req && memory_space && wr) begin
                    case(address)
                        15'h1c00: begin
                            check(stores==0,"video_store_order",0,stores);
                            check(write_data===8'h00,"sense_outside_blank",0,write_data);
                        end
                        15'h1c01: begin
                            check(stores==1 || stores==5,"video_store_order",1,stores);
                            check(write_data===8'ha1,"interrupt_status",8'ha1,write_data);
                        end
                        15'h1c02: begin
                            check(stores==2 || stores==6,"video_store_order",2,stores);
                            check(write_data===8'hd7,"video_handler",8'hd7,write_data);
                        end
                        15'h1c03: begin
                            check(stores==3,"video_store_order",3,stores);
                            check(write_data===8'h80,"sense_inside_blank",8'h80,write_data);
                        end
                        15'h1c04: begin
                            check(stores==4,"video_store_order",4,stores);
                            check(write_data===8'h22,"video_halt_resume",8'h22,write_data);
                        end
                        default: check(1'b0,"video_unexpected_store",0,address);
                    endcase
                    stores=stores+1;
                end
                // Fixed raster deadlines distinguish missing/wrong IRQs from
                // tool timeouts. Sufficient time for the documented ISR sequence.
                if(v_count==5 && h_count==50 && blank_count>0) begin
                    check(ack_count==blank_count,"video_ack_count",blank_count,ack_count);
                    check(stores==(blank_count==1?5:7),"video_retirement",blank_count==1?5:7,stores);
                end
                if(v_count==43 && h_count==50 && blank_count>0) begin
                    check(ack_count==blank_count,"video_ack_count",blank_count,ack_count);
                    check(irq===1'b0,"video_irq_cleared",0,irq);
                    if(blank_count==2) begin
                        check(stores==7,"video_completion",7,stores);
                        $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Actual CPU SENSE, vector 03, ISR status, HALT resume and two-frame interrupt rearm\"}",cycle);
                        $finish(0);
                    end
                end
            end
            clk=1;#5;cycle=cycle+1;
            if(!cpu_reset) begin
                if(intack && !previous_ack) ack_count=ack_count+1;
                previous_ack=intack;
            end
            if(trace_start>=0 && cycle==trace_start) begin $dumpon;trace_on=1;end
            if(trace_on && cycle==trace_start+2048) begin $dumpoff;trace_on=0;end
        end
    endtask
    initial begin
        if($value$plusargs("trace_start=%d",trace_start)) begin
            $dumpfile("failure.vcd");$dumpvars(1,cvs_video_cpu_tb);$dumpoff;
        end
        for(integer n=0;n<384;n=n+1)program_bytes[n]=8'h40;
        // BCTA,UN to 0100; vector 03 is an actual direct ISR entry.
        program_bytes[0]=8'h1f;program_bytes[1]=8'h01;program_bytes[2]=8'h00;
        program_bytes[3]=8'h12;
        program_bytes[4]=8'hcc;program_bytes[5]=8'h1c;program_bytes[6]=8'h01;
        program_bytes[7]=8'h04;program_bytes[8]=8'hd7;
        program_bytes[9]=8'hcc;program_bytes[10]=8'h1c;program_bytes[11]=8'h02;
        program_bytes[12]=8'h37; // RETE,UN
        program_bytes[256]=8'h75;program_bytes[257]=8'hff;
        program_bytes[258]=8'h77;program_bytes[259]=8'h0a;
        program_bytes[260]=8'h74;program_bytes[261]=8'hff;
        program_bytes[262]=8'h12;
        program_bytes[263]=8'hcc;program_bytes[264]=8'h1c;program_bytes[265]=8'h00;
        program_bytes[266]=8'h40; // HALT until first subsequent VRST
        program_bytes[267]=8'h12;
        program_bytes[268]=8'hcc;program_bytes[269]=8'h1c;program_bytes[270]=8'h03;
        program_bytes[271]=8'h04;program_bytes[272]=8'h22;
        program_bytes[273]=8'hcc;program_bytes[274]=8'h1c;program_bytes[275]=8'h04;
        // Remaining HALTs permit a second frame without additional main stores.
        tick;
        for(integer n=0;n<384;n=n+1)begin dl_wr=1;dl_addr=n;dl_data=program_bytes[n];tick;end
        dl_wr=0;video_reset=0;
        while(!vrst)tick;
        while(vrst)tick;
        reset_na=1;repeat(4)tick;cpu_reset=0;
        for(integer n=0;n<3000000;n=n+1)tick;
        $display("BDSM {\"status\":\"ERROR\",\"reason\":\"Bounded video/CPU fixture did not reach completion\"}");
        $finish(2);
    end
endmodule
