#include "Vcvs_memory.h"
#include "common.hpp"
static unsigned pattern(unsigned address) { return (address*73+(address>>8)*19+(address>>13)*41)^0x5a; }
int main(int argc,char** argv) {
    setup(argc,argv);Bench<Vcvs_memory> b(argc,argv);
    try {
        b.rtl.cpu_rd=0;b.rtl.cpu_wr=0;b.rtl.dl_wr=1;b.rtl.cpu_addr=0;b.rtl.cpu_din=0;
        for(unsigned a=0;a<32768;++a){b.rtl.dl_addr=a;b.rtl.dl_data=pattern(a);b.tick();}
        b.rtl.dl_wr=0;b.rtl.cpu_rd=1;
        for(unsigned a=0;a<32768;++a) {
            if((a&0x1fff)>=0x1400)continue;
            b.rtl.cpu_addr=a;unsigned old=b.rtl.cpu_dout;b.rtl.clk=0;b.rtl.eval();
            b.check(b.rtl.cpu_dout==old,"read_latency",old,b.rtl.cpu_dout);
            b.tick();unsigned want=pattern(a)&255;
            b.check(b.rtl.cpu_dout==want,"rom_byte",want,b.rtl.cpu_dout);
        }
        b.rtl.cpu_wr=1;b.rtl.cpu_din=0xa6;
        for(unsigned a=0;a<32768;a+=0x400){if((a&0x1fff)>=0x1400)continue;b.rtl.cpu_addr=a;b.tick();
            b.check(b.rtl.cpu_dout==(pattern(a)&255),"rom_readonly",pattern(a)&255,b.rtl.cpu_dout);}
        for(unsigned a=0;a<1024;++a){b.rtl.cpu_addr=0x1c00+a;b.rtl.cpu_din=pattern(a);b.tick();
            b.check(b.rtl.cpu_dout==(pattern(a)&255),"ram_write_through",pattern(a)&255,b.rtl.cpu_dout);}
        b.rtl.cpu_wr=0;
        for(unsigned bank=0;bank<4;++bank)for(unsigned a=0;a<1024;++a){
            b.rtl.cpu_addr=(bank<<13)+0x1c00+a;b.tick();
            b.check(b.rtl.cpu_dout==(pattern(a)&255),"ram_mirror",pattern(a)&255,b.rtl.cpu_dout);}
        for(unsigned bank=0;bank<4;++bank)for(unsigned a=0x1400;a<0x1c00;++a){
            b.rtl.cpu_addr=(bank<<13)+a;b.tick();b.check(b.rtl.cpu_dout==255,"unimplemented_window",255,b.rtl.cpu_dout);}
        b.rtl.cpu_addr=0x6000;b.rtl.dl_addr=0x6000;b.rtl.dl_data=0xd3;b.rtl.dl_wr=1;b.tick();
        b.check(b.rtl.cpu_dout==0xd3,"download_collision",0xd3,b.rtl.cpu_dout);
        b.rtl.dl_wr=0;b.tick();b.check(b.rtl.cpu_dout==0xd3,"download_persistence",0xd3,b.rtl.cpu_dout);
        b.rtl.cpu_rd=0;b.rtl.cpu_addr=0;b.tick();b.check(b.rtl.cpu_dout==0xd3,"read_hold",0xd3,b.rtl.cpu_dout);
        b.pass();return 0;
    } catch(const Failure&) { return 1; }
}
