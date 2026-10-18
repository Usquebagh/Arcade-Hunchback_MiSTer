// SPDX-License-Identifier: BSD-3-Clause
// Actual CPU/FLAG memory/three PVIs, initialized by a synthetic downloaded ROM.
module cvs_s2636_cpu_tb;
    reg clk=0, reset=1, reset_na=0, dl_wr=0, vrst=1, line_start=0, ce_pixel=0, irq=0;
    reg [14:0] dl_addr=0;
    reg [7:0] dl_data=0, pixel_x=0;
    wire ce, intack, req, wr, memory_space;
    wire [14:0] address;
    wire [7:0] write_data, video_fx, sprite_address, sprite_write_data, sprite_read_data;
    wire [2:0] chip_select, pvi_irq;
    wire sprite_rd, sprite_wr;
    wire [11:0] pixels, object_masks;
    cvs_clock clocks(.clk(clk),.reset(reset),.ce_main(),.ce_audio(),.ce_main_step(ce),.ce_audio_step());
    cvs_main dut(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(ce),.ready(1'b1),
        .cheat_reset(reset),.cheat_code(129'd0),
        .irq(irq),.sense(vrst),.ivec(8'h03),.intack(intack),
        .dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),
        .in0(8'hff),.in1(8'hff),.in2(8'hff),.in3(8'hff),.dsw1(8'hff),.dsw2(8'hff),
        .collision(8'd0),.char_page(),.char_mode(),.scroll(),.video_fx(video_fx),.audio_command(),
        .collision_clear(),.audio_trigger(),.video_tile_rd(1'b0),.video_tile_addr(10'd0),.video_bullet_addr(8'd0),.video_glyph_rd(1'b0),.video_glyph_addr(10'd0),.video_palette_rd(1'b0),.video_palette_addr(4'd0),
        .sprite_din(sprite_read_data),.sprite_select(chip_select),
        .sprite_rd(sprite_rd),.sprite_wr(sprite_wr),.sprite_addr(sprite_address),.sprite_dout(sprite_write_data),
        .req(req),.wr(wr),.memory_space(memory_space),.extended(),.data_port(),.flag(),
        .address(address),.write_data(write_data),.read_data(),.phase());
    cvs_s2636_bank pvis(.clk(clk),.reset(reset),.chip_select(chip_select),.cpu_rd(sprite_rd),
        .cpu_wr(sprite_wr),.cpu_addr(sprite_address),.cpu_din(sprite_write_data),.cpu_dout(sprite_read_data),
        .vrst(vrst),.line_start(line_start),.ce_pixel(ce_pixel),.pixel_x(pixel_x),
        .intack({3{intack}}),.irq(pvi_irq),.pixels(pixels),.object_masks(object_masks));
    reg [7:0] program_bytes[0:4095];
    reg [7:0] expected[0:17];
    integer size=256, cycle=0, stores=0, acknowledgements=0, trace_start=-1;
    reg previous_ack=0, trace_on=0;
    task check(input condition,input [8*40-1:0] label_text,input integer want,input integer got);
        begin
            if(condition !== 1'b1)begin
                $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":\"%0d\"}",label_text,cycle,want,got);
                $finish(1);
            end
        end
    endtask
    task tick;
        begin
            clk=0;#5;
            if(!reset && req && wr && memory_space && address>=15'h1c00 && address<15'h1c12)begin
                check(address==15'h1c00+stores,"pvi_cpu_store_order",stores,address-15'h1c00);
                check(write_data===expected[stores],"pvi_cpu_readback",expected[stores],write_data);
                stores=stores+1;
            end
            clk=1;#5;cycle=cycle+1;
            if(!reset)begin
                if(intack && !previous_ack)begin acknowledgements=acknowledgements+1;irq=0;end
                previous_ack=intack;
            end
            if(trace_start>=0 && cycle==trace_start)begin $dumpon;trace_on=1;end
            if(trace_on && cycle==trace_start+2048)begin $dumpoff;trace_on=0;end
        end
    endtask
    task byte_out(input [7:0] value);begin program_bytes[size]=value;size=size+1;end endtask
    task instruction2(input [7:0] op,input [7:0] operand);begin byte_out(op);byte_out(operand);end endtask
    task store(input [12:0] target);begin byte_out(8'hcc);byte_out({3'd0,target[12:8]});byte_out(target[7:0]);end endtask
    task load(input [12:0] target);begin byte_out(8'h0c);byte_out({3'd0,target[12:8]});byte_out(target[7:0]);end endtask
    task poke(input [12:0] target,input [7:0] value);begin instruction2(8'h04,value);store(target);end endtask
    initial begin
        if($value$plusargs("trace_start=%d",trace_start))begin
            $dumpfile("failure.vcd");$dumpvars(1,cvs_s2636_cpu_tb);$dumpoff;
        end
        for(integer n=0;n<4096;n=n+1)program_bytes[n]=8'h40;
        program_bytes[0]=8'h1f;program_bytes[1]=1;program_bytes[2]=0;program_bytes[3]=8'h37;
        instruction2(8'h75,8'hff);instruction2(8'h77,8'h0a);instruction2(8'h74,8'hff);
        for(integer chip=0;chip<3;chip=chip+1)begin
            for(integer obj=0;obj<4;obj=obj+1)begin
                for(integer row=0;row<10;row=row+1)
                    poke(13'h1500+chip*256+(obj==3?64:obj*16)+row,
                         obj==0?(chip==0?8'h81:chip==1?8'h42:8'h24):0);
                // HC=46 plus MAME CVS X=-26 gives the expected pixel origin X=20.
                poke(13'h1500+chip*256+(obj==3?64:obj*16)+10,obj==0?46:255);
                poke(13'h1500+chip*256+(obj==3?64:obj*16)+11,255);
                poke(13'h1500+chip*256+(obj==3?64:obj*16)+12,obj==0?4:255);
                poke(13'h1500+chip*256+(obj==3?64:obj*16)+13,255);
            end
            poke(13'h15c0+chip*256,0);
            poke(13'h15c1+chip*256,chip==0?32:chip==1?16:8);
            poke(13'h15c2+chip*256,0);
        end
        // FLAG-high character RAM write must not modify the chip-3 descriptor.
        instruction2(8'h76,8'h40);poke(13'h1500,8'hee);instruction2(8'h74,8'h40);
        for(integer chip=0;chip<3;chip=chip+1)begin load(13'h1500+chip*256);store(13'h1c00+chip);end
        for(integer chip=0;chip<3;chip=chip+1)begin load(13'h15cb+chip*256);store(13'h1c03+chip);end
        for(integer chip=0;chip<3;chip=chip+1)begin load(13'h15fb+chip*256);store(13'h1c06+chip);end
        instruction2(8'h04,8'h55);byte_out(8'hf0);byte_out(8'h40);
        for(integer chip=0;chip<3;chip=chip+1)begin load(13'h15ca+chip*256);store(13'h1c09+chip);end
        for(integer chip=0;chip<3;chip=chip+1)begin load(13'h15fa+chip*256);store(13'h1c0c+chip);end
        for(integer chip=0;chip<3;chip=chip+1)begin load(13'h1500+chip*256);store(13'h1c0f+chip);end
        instruction2(8'h04,8'h66);byte_out(8'hf0);byte_out(8'h40);
        check(size<4096,"synthetic_program_size",4096,size);
        expected[0]=8'h81;expected[1]=8'h42;expected[2]=8'h24;
        for(integer n=3;n<6;n=n+1)expected[n]=8'h40;
        for(integer n=6;n<9;n=n+1)expected[n]=0;
        for(integer n=9;n<12;n=n+1)expected[n]=8'h08;
        for(integer n=12;n<15;n=n+1)expected[n]=0;
        expected[15]=8'h81;expected[16]=8'h42;expected[17]=8'h24;
        tick;
        for(integer n=0;n<size;n=n+1)begin dl_wr=1;dl_addr=n;dl_data=program_bytes[n];tick;end
        dl_wr=0;reset_na=1;repeat(4)tick;reset=0;
        for(integer n=0;n<250000 && video_fx!=8'h55;n=n+1)tick;
        check(video_fx==8'h55 && stores==9,"pvi_cpu_initialization",9,stores);
        vrst=0;tick;
        for(integer y=0;y<20;y=y+1)begin
            line_start=1;tick;line_start=0;
            for(integer x=0;x<227;x=x+1)begin
                pixel_x=x;ce_pixel=1;tick;
                check(pixels===((y>=4 && y<14)?
                    ((x==20 || x==27)?12'hc00:(x==21 || x==26)?12'h0a0:(x==22 || x==25)?12'h009:12'h000):12'h000),
                    "pvi_cpu_pixel",(y>=4 && y<14)?((x==20 || x==27)?12'hc00:(x==21 || x==26)?12'h0a0:(x==22 || x==25)?12'h009:0):0,pixels);
            end
            ce_pixel=0;
        end
        irq=1;
        for(integer n=0;n<15000 && video_fx!=8'h66;n=n+1)tick;
        check(video_fx==8'h66 && stores==18,"pvi_cpu_completion",18,stores);
        check(acknowledgements==1,"pvi_fixture_ack",1,acknowledgements);
        $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Three real PVI instances initialized/read by actual CPU; 18 signatures, FLAG isolation, pixels and status clearing\"}",cycle);
        $finish(0);
    end
endmodule
