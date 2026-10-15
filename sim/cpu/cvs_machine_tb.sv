// SPDX-License-Identifier: BSD-3-Clause
// Actual CPU and actual provisional main/video assembly, no mock RAM/PVI.
module cvs_machine_tb;
    reg clk=0,reset=1,reset_na=0,video_reset=1,scan_run=0,ready=1,dl_wr=0;
    reg [15:0] dl_addr=0;
    reg [7:0] dl_data=0;
    wire pixel_valid,pixel_ce_all,display_enable,bullet_present,background_collision,hsync_n,vsync_n,audio_trigger,intack;
    wire mister_pixel_ce;
    wire req,wr,memory_space,extended,data_port,flag;
    wire [7:0] out_x,out_y,red,green,blue,collision_events,collision,video_fx,audio_command;
    wire [7:0] write_data,read_data,h_count;
    wire [2:0] raw_pixel,pvi_irq;
    wire [3:0] palette_index;
    wire [14:0] address;
    wire [1:0] phase;
    wire [8:0] v_count;
    cvs_machine dut(.*,.in0(8'hff),.in1(8'hff),.in2(8'hff),.in3(8'hff),.dsw1(8'hff),.dsw2(8'hff));
    cvs_mister_pixel_enable pixel_enable_delay(.clk(clk),.reset(video_reset),
        .pixel_ce_in(pixel_ce_all),.pixel_ce_out(mister_pixel_ce));
    reg [7:0] program_bytes[0:4095],image_bytes[0:51231];
    reg [23:0] boot_expected[0:1023];
    reg boot=0,trace_on=0;
    reg [5:0] valid_expect=0,hs_expect=63,vs_expect=63,ce_expect=0;
    integer cycle=0,size=256,stores=0,pixels=0,scan_steps=0,trace_start=-1;
    integer frame_ticks=70824,tick_count,hor,vert,frame_position;
    integer x_want,y_want,pen_want,events_want,active,r_want,g_want,b_want;
    reg sprite_want,bullet_want,visible_want,request_want;
    string image_name,expect_name;
    integer image_fd,image_size;
    task check(input condition,input [8*40-1:0] label_text,input integer want,input integer got);
        if(condition !== 1'b1)begin
            $display("BDSM {\"status\":\"FAIL\",\"label\":\"%0s\",\"cycle\":%0d,\"expected\":%0d,\"observed\":\"%0d\"}",label_text,cycle,want,got);$finish(1);
        end
    endtask
    task tick;
        begin
            clk=0;#5;
            if(!reset && req && ready && wr && memory_space)begin
                if(boot)begin
                    check({address,flag,write_data}===boot_expected[stores],"bootstrap_write",boot_expected[stores],{address,flag,write_data});stores=stores+1;
                end else if(address>=15'h1c00 && address<15'h1c05)begin
                    check(address==15'h1c00+stores,"assembly_store_order",stores,address-15'h1c00);
                    check(write_data===(stores==0?8'hff:stores==1?8'd0:8'd8),"assembly_cpu_readback",stores==0?255:stores==1?0:8,write_data);stores=stores+1;
                end
            end
            if(video_reset)begin valid_expect=0;hs_expect=63;vs_expect=63;ce_expect=0;scan_steps=0;end
            else begin
                tick_count=scan_steps/16;hor=tick_count%227;
                vert=((tick_count+frame_ticks-6)/227)%312+1;
                frame_position=(tick_count+frame_ticks-6)%frame_ticks;
                request_want=scan_run && scan_steps%16==15 && vert>=43 && vert<=298;
                valid_expect={valid_expect[4:0],request_want};
                hs_expect={hs_expect[4:0],!(hor>=11 && hor<28)};
                vs_expect={vs_expect[4:0],!(frame_position>=2292 && frame_position<3183)};
                ce_expect={ce_expect[4:0],scan_run && scan_steps%16==15};
            end
            check(pixel_ce_all===(!video_reset && scan_run && scan_steps%16==15),
                "assembly_pixel_ce",!video_reset && scan_run && scan_steps%16==15,pixel_ce_all);
            clk=1;#5;cycle=cycle+1;
            check(pixel_valid===valid_expect[5],"assembly_latency",valid_expect[5],pixel_valid);
            check(mister_pixel_ce===ce_expect[5],"assembly_mister_ce",ce_expect[5],mister_pixel_ce);
            check(display_enable===(pixel_valid && out_x>=8'd44),"assembly_display_enable",pixel_valid && out_x>=8'd44,display_enable);
            check(hsync_n===hs_expect[5] && vsync_n===vs_expect[5],"assembly_sync",hs_expect[5]+2*vs_expect[5],hsync_n+2*vsync_n);
            if(!video_reset && scan_run)scan_steps=scan_steps+1;
            if(!boot && pixel_valid)begin
                x_want=pixels%227;y_want=pixels/227;
                check(out_x==x_want && out_y==y_want,"assembly_coordinates",x_want+256*y_want,out_x+256*out_y);
                visible_want=x_want>=44;
                sprite_want=x_want>=48 && x_want<56 && y_want>=8 && y_want<18;
                bullet_want=x_want>=45 && x_want<=48 && y_want>=8 && y_want<16;
                pen_want=sprite_want?14:bullet_want?7:1;
                check(raw_pixel===3'd7,"assembly_character",7,raw_pixel);
                check(palette_index===pen_want[3:0],"assembly_palette",pen_want,palette_index);
                check(bullet_present==(bullet_want && visible_want) && background_collision==visible_want,"assembly_foreground",bullet_want+2*visible_want,bullet_present+2*background_collision);
                events_want=visible_want?((sprite_want?119:0)+(bullet_want?128:0)+(sprite_want && bullet_want?8:0)):0;
                check(collision_events===events_want[7:0],"assembly_collision",events_want,collision_events);
                active=pen_want*17;r_want=visible_want?(active%4)*85:0;
                g_want=(active/4)%8;b_want=active/32;
                g_want=visible_want?(g_want*32+g_want*4+g_want/2):0;
                b_want=visible_want?(b_want*32+b_want*4+b_want/2):0;
                check(red==r_want && green==g_want && blue==b_want,"assembly_rgb",r_want+256*g_want+65536*b_want,red+256*green+65536*blue);
                pixels=pixels+1;
            end
            if(boot && stores==1024)begin
                $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Authenticated unchanged parent ROM executed 1024 independently modeled system-RAM clear writes; early bootstrap only\"}",cycle);$finish(0);
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
    task fill_words(input integer base,input integer blocks,input [7:0] data);
        integer loop_pc;
        begin
            instruction2(8'h04,data);instruction2(8'h05,0);loop_pc=size;
            for(integer block=0;block<blocks;block=block+1)begin
                byte_out(8'hcd);byte_out((block==0?8'h40:8'h60)+((base+block*256)>>8));byte_out(0);
            end
            instruction2(8'h59,(loop_pc-(size+2))&127);
        end
    endtask
    initial begin
        if($value$plusargs("trace_start=%d",trace_start))begin $dumpfile("failure.vcd");$dumpvars(1,cvs_machine_tb);$dumpoff;end
        boot=$test$plusargs("boot");tick;
        if(boot)begin
            if(!$value$plusargs("image=%s",image_name) || !$value$plusargs("expect=%s",expect_name))begin
                $display("BDSM {\"status\":\"ERROR\",\"reason\":\"Missing bootstrap files\"}");$finish(0);
            end
            image_fd=$fopen(image_name,"rb");image_size=$fread(image_bytes,image_fd);$fclose(image_fd);
            if(image_size!=51232)begin $display("BDSM {\"status\":\"ERROR\",\"reason\":\"Bootstrap image length\"}");$finish(0);end
            $readmemh(expect_name,boot_expected);
            for(integer n=0;n<51232;n=n+1)begin dl_wr=1;dl_addr=n;dl_data=image_bytes[n];tick;end
        end else begin
            for(integer n=0;n<4096;n=n+1)program_bytes[n]=8'h40;
            program_bytes[0]=8'h1f;program_bytes[1]=1;program_bytes[2]=0;
            instruction2(8'h75,8'hff);instruction2(8'h77,8'h0a);instruction2(8'h74,8'hff);
            instruction2(8'h76,8'h20);fill_words(13'h1800,4,8'h83);fill_words(13'h1400,1,0);
            for(integer y=8;y<16;y=y+1)poke(13'h1400+y,200);
            instruction2(8'h76,8'h40);fill_words(13'h1800,4,8'h80);
            for(integer n=0;n<16;n=n+1)poke(13'h1400+n,255-n*17);
            instruction2(8'h54,8'h30);
            for(integer row=0;row<8;row=row+1)begin poke(13'h1700+row,255);poke(13'h1600+row,255);poke(13'h1500+row,255);end
            instruction2(8'h74,8'h40);
            for(integer chip=0;chip<3;chip=chip+1)begin
                for(integer obj=0;obj<4;obj=obj+1)begin
                    for(integer row=0;row<10;row=row+1)poke(13'h1500+chip*256+(obj==3?64:obj*16)+row,obj==0?255:0);
                    poke(13'h1500+chip*256+(obj==3?64:obj*16)+10,obj==0?48:255);
                    poke(13'h1500+chip*256+(obj==3?64:obj*16)+11,255);
                    poke(13'h1500+chip*256+(obj==3?64:obj*16)+12,obj==0?8:255);
                    poke(13'h1500+chip*256+(obj==3?64:obj*16)+13,255);
                end
                poke(13'h15c0+chip*256,0);poke(13'h15c1+chip*256,chip==0?32:chip==1?16:0);poke(13'h15c2+chip*256,0);
            end
            instruction2(8'h04,8'h55);byte_out(8'hf0);
            byte_out(8'h30);store(13'h1c00);byte_out(8'h70);byte_out(8'h30);store(13'h1c01);
            for(integer chip=0;chip<3;chip=chip+1)begin load(13'h15ca+chip*256);store(13'h1c02+chip);end
            instruction2(8'h04,8'h66);byte_out(8'hf0);byte_out(8'h40);
            check(size<4096,"assembly_program_size",4096,size);
            for(integer n=0;n<size;n=n+1)begin dl_wr=1;dl_addr=n;dl_data=program_bytes[n];tick;end
            for(integer n=0;n<6144;n=n+1)begin dl_addr=16'ha800+n;dl_data=0;tick;end
            for(integer n=0;n<2048;n=n+1)begin dl_addr=16'hc000+n;dl_data=(n/256)^(n%8);tick;end
        end
        dl_wr=0;reset_na=1;video_reset=0;repeat(4)tick;reset=0;
        if(boot)begin
            for(integer n=0;n<1500000;n=n+1)tick;
            $display("BDSM {\"status\":\"ERROR\",\"reason\":\"Bootstrap did not complete within bounded fixture\"}");$finish(0);
        end else begin
            for(integer n=0;n<1500000 && video_fx!=8'h55;n=n+1)tick;
            check(video_fx==8'h55,"assembly_cpu_initialization",85,video_fx);
            ready=0;scan_run=1;
            for(integer n=0;n<1200000 && pixels<58112;n=n+1)tick;
            check(pixels==58112,"assembly_complete_field",58112,pixels);
            check(collision===8'hff,"assembly_accumulated",255,collision);
            scan_run=0;repeat(8)tick;ready=1;
            for(integer n=0;n<15000 && video_fx!=8'h66;n=n+1)tick;
            check(video_fx==8'h66 && stores==5,"assembly_cpu_completion",5,stores);
            $display("BDSM {\"status\":\"PASS\",\"cycle\":%0d,\"observed\":\"Actual CPU/RAM/three PVIs/character/raster: 58112 independent pixels, sync/latency and five collision/status readbacks\"}",cycle);$finish(0);
        end
    end
endmodule
