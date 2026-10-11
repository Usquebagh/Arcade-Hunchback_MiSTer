#include "Vcvs_main_bus.h"
#include "common.hpp"
int main(int argc,char** argv){
    setup(argc,argv);Bench<Vcvs_main_bus> b(argc,argv);
    try{
        b.rtl.reset=1;b.rtl.ready=1;b.rtl.req=0;b.rtl.wr=0;b.rtl.memory_space=0;
        b.rtl.extended=0;b.rtl.data_port=0;b.rtl.flag=0;b.rtl.address=0;b.rtl.din=0;
        b.rtl.dl_wr=0;b.rtl.dl_addr=0;b.rtl.dl_data=0;b.rtl.sprite_din=0x8b;
        b.rtl.in0=0x91;b.rtl.in1=0x26;b.rtl.in2=0xe3;b.rtl.in3=0x58;
        b.rtl.dsw1=0xad;b.rtl.dsw2=0x72;b.rtl.collision=0x39;b.tick();
        b.check(b.rtl.char_page==0 && b.rtl.char_mode==0 && b.rtl.scroll==0 &&
                b.rtl.video_fx==0 && b.rtl.audio_command==0 && !b.rtl.audio_trigger &&
                !b.rtl.collision_clear,"io_reset",0,b.rtl.char_page);
        b.rtl.reset=0;
        auto access=[&](bool memory,bool ext,bool data,unsigned address,unsigned value,bool write){
            b.rtl.req=1;b.rtl.memory_space=memory;b.rtl.extended=ext;b.rtl.data_port=data;
            b.rtl.address=address;b.rtl.din=value;b.rtl.wr=write;b.tick();return unsigned(b.rtl.dout);
        };
        const unsigned ports[16]={0x91,0,0x26,0xe3,0x58,0,0x72,0xad,0,0,0,0,0,0,0,0};
        for(unsigned a=0;a<256;++a){
            unsigned got=access(false,true,false,a,0,false);
            b.check(got==ports[a&15],"input_byte",ports[a&15],got);
            b.check(b.rtl.char_page==(a>>6),"io_page",a>>6,b.rtl.char_page);
            b.check(b.rtl.char_mode==((a>>4)&3),"io_mode",(a>>4)&3,b.rtl.char_mode);
        }
        // Writes, unaccepted requests and idle clocks do not change bank latches.
        access(false,true,false,0,0x25,true);
        b.check(b.rtl.char_page==3 && b.rtl.char_mode==3,"write_bank_hold",3,b.rtl.char_page);
        b.check(b.rtl.scroll==0xda,"scroll_invert",0xda,b.rtl.scroll);
        b.rtl.ready=0;b.rtl.wr=0;b.tick();
        b.check(b.rtl.char_page==3 && b.rtl.char_mode==3 && !b.rtl.ack,"stalled_bank_hold",3,b.rtl.char_page);
        b.rtl.req=0;b.rtl.ready=1;b.tick();
        b.check(b.rtl.char_page==3 && b.rtl.char_mode==3,"idle_bank_hold",3,b.rtl.char_page);
        b.check(access(false,false,false,0,0,false)==0x39,"collision_read",0x39,b.rtl.dout);
        access(false,false,true,0,0,false);
        b.check(b.rtl.dout==0 && b.rtl.collision_clear,"collision_clear",1,b.rtl.collision_clear);
        b.rtl.req=0;b.tick();b.check(!b.rtl.collision_clear,"clear_pulse",0,b.rtl.collision_clear);
        access(false,false,true,0,0x31,true);
        b.check(b.rtl.video_fx==0x31,"video_fx",0x31,b.rtl.video_fx);
        for(unsigned v: {0x80u,0x81u,0x00u,0xffu,0xffu}){
            unsigned previous=b.rtl.audio_command;
            access(false,false,false,0,v,true);
            unsigned want=!(previous&128) && (v&128);
            b.check(b.rtl.audio_command==v,"audio_command",v,b.rtl.audio_command);
            b.check(unsigned(b.rtl.audio_trigger)==want,"audio_edge",want,b.rtl.audio_trigger);
            b.rtl.req=0;b.tick();b.check(!b.rtl.audio_trigger,"audio_pulse",0,b.rtl.audio_trigger);
        }
        // Write a real memory byte; I/O writes to the same numeric address cannot alter it.
        access(true,false,false,0x1c53,0x67,true);
        access(false,true,false,0x1c53,0x9a,true);
        unsigned got=access(true,false,false,0x1c53,0,false);
        b.check(got==0x67,"io_memory_isolation",0x67,got);
        b.rtl.req=0;b.rtl.memory_space=0;b.tick();
        b.check(b.rtl.dout==0x67,"bus_response_hold",0x67,b.rtl.dout);
        access(false,true,false,0x82,0,false); // in1, character page 2
        b.rtl.req=0;b.rtl.memory_space=1;b.tick();
        b.check(b.rtl.dout==0x26,"bus_response_hold",0x26,b.rtl.dout);
        b.rtl.flag=1;access(true,false,false,0x1753,0xb4,true);
        access(false,true,false,0xc0,0,false); // change to page 3
        b.rtl.flag=1;access(true,false,false,0x1753,0xe5,true);
        access(false,true,false,0x80,0,false); // restore page 2
        got=access(true,false,false,0x7753,0,false);
        b.check(got==0xb4,"latched_character_byte",0xb4,got);
        b.rtl.reset=1;access(false,true,false,0xff,0xff,true);
        b.check(b.rtl.char_page==0 && b.rtl.scroll==0 && !b.rtl.audio_trigger,"reset_io_isolation",0,b.rtl.scroll);
        access(true,false,false,0x1c53,0xff,true);
        b.rtl.reset=0;got=access(true,false,false,0x1c53,0,false);
        b.check(got==0x67,"reset_ram_hold",0x67,got);
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
