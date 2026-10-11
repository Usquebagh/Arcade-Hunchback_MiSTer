// SPDX-License-Identifier: BSD-3-Clause
// Table-based MAME digital compatibility oracle, not analog board measurements.
#include "Vcvs_audio_bus.h"
#include "common.hpp"
#include <array>
int main(int argc,char** argv){
    setup(argc,argv);Bench<Vcvs_audio_bus> b(argc,argv);
    try{
        std::array<unsigned,4096> rom{};std::array<unsigned,128> ram{};
        unsigned dac8=0,dac4=0,discrete=0;
        b.rtl.reset=1;b.rtl.ready=1;b.rtl.req=0;b.rtl.wr=0;b.rtl.memory_space=1;
        b.rtl.dl_wr=0;b.rtl.command=0x9b;b.rtl.command_trigger=0;b.rtl.intack=0;b.tick();
        auto latch_check=[&](){
            b.check(b.rtl.dac8==dac8 && b.rtl.dac4==dac4 && b.rtl.discrete==discrete,
                    "audio_latches",dac8+256*dac4+4096*discrete,b.rtl.dac8+256*b.rtl.dac4+4096*b.rtl.discrete);
        };
        for(unsigned a=0;a<4096;++a){rom[a]=(a*37+(a/256)*11+83)%256;b.rtl.dl_wr=1;b.rtl.dl_addr=a;b.rtl.dl_data=rom[a];b.tick();}
        b.rtl.dl_wr=0;b.rtl.reset=0;
        auto write=[&](unsigned addr,unsigned data){b.rtl.req=1;b.rtl.wr=1;b.rtl.address=addr;b.rtl.din=data;b.tick();};
        auto read=[&](unsigned addr,unsigned expected){b.rtl.req=1;b.rtl.wr=0;b.rtl.address=addr;b.tick();b.check(b.rtl.dout==expected,"audio_read",expected,b.rtl.dout);};
        for(unsigned a=0;a<128;++a){ram[a]=(a*53+29)%256;write(0x1000+a,ram[a]);}
        for(unsigned a=0;a<32768;++a){unsigned want=a<4096?rom[a]:(a>=0x1000 && a<0x1080)?ram[a-0x1000]:a==0x1800?0x9b:255;read(a,want);}
        for(unsigned a=0;a<4096;++a){write(a,255-rom[a]);read(a,rom[a]);}
        for(unsigned data=0;data<256;++data){
            write(0x1840,data);dac8=data;latch_check();b.check(b.rtl.dac8_wr && !b.rtl.dac4_wr && !b.rtl.discrete_wr,"audio_dac8_strobe",1,b.rtl.dac8_wr);
            for(unsigned bit=0;bit<4;++bit){
                write(0x1880+bit,data);unsigned mask=1u<<bit;dac4=(dac4&~mask)+(data>=128?mask:0);
                b.check(b.rtl.dac4==dac4,"audio_dac4_bit",dac4,b.rtl.dac4);latch_check();
                b.check(!b.rtl.dac8_wr && b.rtl.dac4_wr && !b.rtl.discrete_wr,"audio_dac4_strobe",1,b.rtl.dac4_wr);
                write(0x1884+bit,data);discrete=(discrete&~mask)+(data%2?mask:0);
                b.check(b.rtl.discrete==discrete,"audio_discrete_bit",discrete,b.rtl.discrete);latch_check();
                b.check(!b.rtl.dac8_wr && !b.rtl.dac4_wr && b.rtl.discrete_wr,"audio_discrete_strobe",1,b.rtl.discrete_wr);
            }
        }
        b.rtl.req=0;b.tick();b.check(!b.rtl.dac8_wr && !b.rtl.dac4_wr && !b.rtl.discrete_wr,"audio_pulse_width",0,b.rtl.discrete_wr);
        unsigned held=b.rtl.dout;b.rtl.address=0;b.rtl.command=0x42;b.tick();b.check(b.rtl.dout==held,"audio_read_hold",held,b.rtl.dout);
        b.rtl.ready=0;write(0x1840,0);latch_check();read(0,held);b.check(!b.rtl.ack && !b.rtl.dac8_wr,"audio_stall",0,b.rtl.ack);
        b.rtl.ready=1;b.rtl.memory_space=0;write(0x1840,0);latch_check();read(0x1000,255);
        b.rtl.memory_space=1;b.rtl.req=1;b.rtl.wr=0;b.rtl.address=0;b.rtl.dl_wr=1;b.rtl.dl_addr=0;b.rtl.dl_data=0x6d;b.tick();rom[0]=0x6d;
        b.check(b.rtl.dout==rom[0],"audio_download_forward",rom[0],b.rtl.dout);b.rtl.dl_wr=0;
        auto irq=[&](bool event,bool ack,bool want){b.rtl.req=0;b.rtl.command_trigger=event;b.rtl.intack=ack;b.tick();b.check(bool(b.rtl.irq)==want,"audio_irq",want,b.rtl.irq);};
        irq(1,0,1);read(0x1800,0x42);b.check(b.rtl.irq,"audio_command_retention",1,b.rtl.irq);
        irq(1,1,1);irq(0,1,1);irq(0,0,1);irq(0,1,0);
        irq(1,1,1);irq(0,1,1);irq(0,0,1);irq(0,1,0);
        b.rtl.reset=1;irq(1,1,0);dac8=dac4=discrete=0;latch_check();write(0x1840,255);latch_check();
        b.rtl.reset=0;irq(0,0,0);read(0x1000,ram[0]);read(0,rom[0]);
        // Writes outside each exact window must not modify any control latch.
        for(unsigned a:{0x1080u,0x17ffu,0x1800u,0x183fu,0x1841u,0x187fu,0x1888u,0x3840u,0x7880u}){write(a,255);latch_check();}
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
