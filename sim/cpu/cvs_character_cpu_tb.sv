// SPDX-License-Identifier: BSD-3-Clause
// Actual CPU writes shared memories and reads actual pixel collision status.
module cvs_character_cpu_tb;
    reg clk=0, reset=1, reset_na=0, dl_wr=0, irq=0;
    reg [14:0] dl_addr=0;
    reg [7:0] dl_data=0;
    reg graphics_dl_wr=0, pixel_ce=0;
    reg [12:0] graphics_dl_addr=0;
    reg [7:0] graphics_dl_data=0,pixel_x=0,pixel_y=8;
    reg [11:0] sprites=0;
    wire ce,intack,req,wr,memory_space,collision_clear;
    wire [14:0] address;
    wire [7:0] write_data,video_fx,scroll,collision;
    wire [1:0] char_mode;
    wire video_tile_rd,video_glyph_rd,video_palette_rd,pixel_valid;
    wire [9:0] video_tile_addr,video_glyph_addr;
    wire [7:0] video_bullet_addr,video_code,video_attr,video_bullet,video_palette;
    wire [23:0] video_glyph;
    wire [3:0] video_palette_addr,palette_index;
    wire [2:0] raw_pixel;
    wire [7:0] out_x,out_y,red,green,blue,collision_events;
    wire bullet_present,background_collision;
    cvs_clock clocks(.clk(clk),.reset(reset),.ce_main(),.ce_audio(),.ce_main_step(ce),.ce_audio_step());
    cvs_main dut(.clk(clk),.reset(reset),.reset_na(reset_na),.ce(ce),.ready(1'b1),
        .irq(irq),.sense(1'b0),.ivec(8'h03),.intack(intack),
        .dl_wr(dl_wr),.dl_addr(dl_addr),.dl_data(dl_data),
        .in0(8'hff),.in1(8'hff),.in2(8'hff),.in3(8'hff),.dsw1(8'hff),.dsw2(8'hff),
        .collision(collision),.char_page(),.char_mode(char_mode),.scroll(scroll),.video_fx(video_fx),.audio_command(),
        .collision_clear(collision_clear),.audio_trigger(),.sprite_din(8'hff),.sprite_select(),
        .sprite_rd(),.sprite_wr(),.sprite_addr(),.sprite_dout(),
        .req(req),.wr(wr),.memory_space(memory_space),.extended(),.data_port(),.flag(),
        .address(address),.write_data(write_data),.read_data(),.phase(),
        .video_tile_rd(video_tile_rd),.video_tile_addr(video_tile_addr),.video_bullet_addr(video_bullet_addr),
        .video_code(video_code),.video_attr(video_attr),.video_bullet(video_bullet),
        .video_glyph_rd(video_glyph_rd),.video_glyph_addr(video_glyph_addr),.video_glyph(video_glyph),
        .video_palette_rd(video_palette_rd),.video_palette_addr(video_palette_addr),.video_palette(video_palette));
    cvs_character_video renderer(.clk(clk),.reset(reset),.pixel_ce(pixel_ce),.visible(1'b1),
        .pixel_x(pixel_x),.pixel_y(pixel_y),.scroll(scroll),.char_mode(char_mode),.sprites(sprites),
        .collision_clear(collision_clear),.dl_wr(graphics_dl_wr),.dl_addr(graphics_dl_addr),.dl_data(graphics_dl_data),
        .video_tile_rd(video_tile_rd),.video_tile_addr(video_tile_addr),.video_bullet_addr(video_bullet_addr),
        .video_code(video_code),.video_attr(video_attr),.video_bullet(video_bullet),
        .video_glyph_rd(video_glyph_rd),.video_glyph_addr(video_glyph_addr),.video_glyph(video_glyph),
        .video_palette_rd(video_palette_rd),.video_palette_addr(video_palette_addr),.video_palette(video_palette),
        .pixel_valid(pixel_valid),.out_x(out_x),.out_y(out_y),.red(red),.green(green),.blue(blue),
        .raw_pixel(raw_pixel),.palette_index(palette_index),.bullet_present(bullet_present),
        .background_collision(background_collision),.collision_events(collision_events),.collision(collision));
    reg [7:0] program_bytes[0:4095];
    integer size=256,cycle=0,stores=0,acks=0,trace_start=-1;
    reg previous_ack=0,trace_on=0;
    task check(input condition,input [8*40-1:0] label_text,input integer want,input integer got);
        if(condition !== 1'b1)begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":\"%0d\"}",label_text,cycle,want,got);$finish(1);
        end
    endtask
    task tick;
        begin
            clk=0;#5;
            if(!reset && req && wr && memory_space && address>=15'h1c00 && address<15'h1c02)begin
                check(address==15'h1c00+stores,"character_cpu_store_order",stores,address-15'h1c00);
                check(write_data===(stores==0?8'hff:8'd0),"character_cpu_collision",stores==0?255:0,write_data);stores=stores+1;
            end
            clk=1;#5;cycle=cycle+1;
            if(intack && !previous_ack)begin irq=0;acks=acks+1;end
            previous_ack=intack;
            if(trace_start>=0 && cycle==trace_start)begin $dumpon;trace_on=1;end
            if(trace_on && cycle==trace_start+2048)begin $dumpoff;trace_on=0;end
        end
    endtask
    task byte_out(input [7:0] value);begin program_bytes[size]=value;size=size+1;end endtask
    task instruction2(input [7:0] op,input [7:0] operand);begin byte_out(op);byte_out(operand);end endtask
    task store(input [12:0] target);begin byte_out(8'hcc);byte_out({3'd0,target[12:8]});byte_out(target[7:0]);end endtask
    task poke(input [12:0] target,input [7:0] value);begin instruction2(8'h04,value);store(target);end endtask
    function integer raw_expected(input integer x);
        case(x%8)
            0:raw_expected=x<8?4:x<16?0:7;
            1:raw_expected=x<8?2:x<16?1:6;
            2:raw_expected=x<8?1:x<16?2:5;
            3:raw_expected=x<8?0:x<16?4:4;
            4:raw_expected=x<8?0:x<16?4:3;
            5:raw_expected=x<8?1:x<16?2:2;
            6:raw_expected=x<8?2:x<16?1:1;
            7:raw_expected=x<8?4:x<16?0:0;
        endcase
    endfunction
    integer raw_want,pen_want,active,r_want,g_want,b_want;
    initial begin
        if($value$plusargs("trace_start=%d",trace_start))begin $dumpfile("failure.vcd");$dumpvars(1,cvs_character_cpu_tb);$dumpoff;end
        for(integer n=0;n<4096;n=n+1)program_bytes[n]=8'h40;
        program_bytes[0]=8'h1f;program_bytes[1]=1;program_bytes[2]=0;program_bytes[3]=8'h37;
        instruction2(8'h75,8'hff);instruction2(8'h77,8'h0a);instruction2(8'h74,8'hff);
        poke(13'h1820,8'h83);poke(13'h1821,8'h02);poke(13'h1822,8'h01);
        for(integer y=8;y<16;y=y+1)poke(13'h1400+y,240);
        instruction2(8'h76,8'h40);
        poke(13'h1820,8'h80);poke(13'h1821,8'hc0);poke(13'h1822,8'h20);
        for(integer n=0;n<16;n=n+1)poke(13'h1400+n,255-n*17);
        instruction2(8'h54,8'h30);
        for(integer row=0;row<8;row=row+1)begin poke(13'h1700+row,8'h81);poke(13'h1600+row,8'h42);poke(13'h1500+row,8'h24);end
        instruction2(8'h54,8'hb0);
        for(integer row=0;row<8;row=row+1)begin poke(13'h1700+row,8'h18);poke(13'h1600+row,8'h24);poke(13'h1500+row,8'h42);end
        instruction2(8'h54,8'h70);
        for(integer row=0;row<8;row=row+1)begin poke(13'h1700+row,0);poke(13'h1600+row,0);poke(13'h1500+row,0);end
        instruction2(8'h04,8'hff);instruction2(8'hd4,0);
        instruction2(8'h04,8'h55);byte_out(8'hf0);byte_out(8'h40);
        byte_out(8'h30);store(13'h1c00);byte_out(8'h70);byte_out(8'h30);store(13'h1c01);
        instruction2(8'h04,8'h66);byte_out(8'hf0);byte_out(8'h40);
        check(size<4096,"character_cpu_program_size",4096,size);
        tick;
        for(integer n=0;n<size;n=n+1)begin dl_wr=1;dl_addr=n;dl_data=program_bytes[n];tick;end
        dl_wr=0;
        for(integer p=0;p<3;p=p+1)for(integer row=0;row<8;row=row+1)begin
            graphics_dl_wr=1;graphics_dl_addr=p*2048+256+row;graphics_dl_data=p==0?8'hf0:p==1?8'hcc:8'haa;tick;
        end
        for(integer n=0;n<2048;n=n+1)begin graphics_dl_addr=6144+n;graphics_dl_data=n/256;tick;end
        graphics_dl_wr=0;reset_na=1;repeat(4)tick;reset=0;
        for(integer n=0;n<180000 && video_fx!=8'h55;n=n+1)tick;
        check(video_fx==8'h55 && char_mode==3 && scroll==0,"character_cpu_initialized",85,video_fx);
        for(integer y=8;y<16;y=y+1)for(integer x=0;x<24;x=x+1)begin
            pixel_x=x;pixel_y=y;sprites=y==8 && x==0?12'h888:y==8 && x==6?12'h0a9:0;
            pixel_ce=1;tick;pixel_ce=0;repeat(4)tick;
            raw_want=raw_expected(x);pen_want=(raw_want%2)*4+(raw_want&2)+(raw_want/4);
            if(x>=5 && x<=8)pen_want=7;
            if(y==8 && x==0)pen_want=8;
            if(y==8 && x==6)pen_want=11;
            active=pen_want*17;r_want=(active%4)*85;g_want=(active/4)%8;b_want=active/32;
            g_want=g_want*32+g_want*4+g_want/2;b_want=b_want*32+b_want*4+b_want/2;
            check(pixel_valid && out_x==x && out_y==y,"character_cpu_valid",x,out_x);
            check(raw_pixel===raw_want[2:0],"character_cpu_glyph",raw_want,raw_pixel);
            check(palette_index===pen_want[3:0],"character_cpu_palette",pen_want,palette_index);
            check(red==r_want && green==g_want && blue==b_want,"character_cpu_rgb",r_want+256*g_want+65536*b_want,red+256*green+65536*blue);
        end
        check(collision===8'hff,"character_cpu_accumulation",255,collision);
        repeat(5)tick;irq=1;
        for(integer n=0;n<15000 && video_fx!=8'h66;n=n+1)tick;
        check(video_fx==8'h66 && stores==2 && acks==1,"character_cpu_completed",2,stores);
        $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Actual CPU initializes video RAM/two glyph pages; 192 pixels and collision read/clear signatures\"}",cycle);$finish(0);
    end
endmodule
