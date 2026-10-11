// SPDX-License-Identifier: BSD-3-Clause
// Independent map/bit-order/address-equation oracle, no speech waveform model.
#include "Vcvs_speech_bus.h"
#include "common.hpp"
#include <array>
int main(int argc,char** argv) {
    setup(argc,argv);Bench<Vcvs_speech_bus> b(argc,argv);auto& m=b.rtl;
    try {
        std::array<unsigned,2048> program{};std::array<unsigned,4096> serial{};
        unsigned pointer=0,latches=0,pdc=0,last_bit=0;
        m.reset=1;m.ready=1;m.req=m.wr=m.bit_req=m.program_dl_wr=m.data_dl_wr=0;
        m.memory_space=1;m.command=0x42;m.ctl_status=0;b.tick();
        for(unsigned a=0;a<2048;++a) {program[a]=(a*37+(a/256)*19+83)%256;m.program_dl_wr=1;m.program_dl_addr=a;m.dl_data=program[a];b.tick();}
        m.program_dl_wr=0;
        for(unsigned a=0;a<4096;++a) {serial[a]=(a*53+(a/8)*29+0x96)%256;m.data_dl_wr=1;m.data_dl_addr=a;m.dl_data=serial[a];b.tick();}
        m.data_dl_wr=0;m.reset=0;
        auto controls=[&]() {
            unsigned ctl=((latches/2)%2)*10+((latches/4)%2)*4;
            b.check(m.control_latches==latches && m.ctl==ctl && m.pdc==pdc,"speech_controls",latches+16*ctl+256*pdc,m.control_latches+16*m.ctl+256*m.pdc);
            b.check(m.bit_address==pointer,"speech_pointer",pointer,m.bit_address);
        };
        auto write=[&](unsigned addr,unsigned data) {
            m.req=1;m.wr=1;m.memory_space=1;m.address=addr;m.din=data;b.tick();
            if(addr==0x1d00)pointer=((pointer&0xf800)+data*8)&65535;
            else if(addr==0x1d40)pointer=((pointer&2047)+data*2048)&65535;
            else if(addr>=0x1ddc && addr<=0x1dde){unsigned bit=addr-0x1ddc;latches=(latches&~(1u<<bit))+((data<128?1u:0u)<<bit);}
            else if(addr==0x1ddf)pdc=data<128;
            controls();
            b.check(m.ctl_wr==(addr>=0x1ddc && addr<=0x1dde) && m.pdc_wr==(addr==0x1ddf),"speech_strobes",0,m.ctl_wr+2*m.pdc_wr);
        };
        auto read=[&](unsigned addr,unsigned expected) {m.req=1;m.wr=0;m.memory_space=1;m.address=addr;b.tick();b.check(m.dout==expected,"speech_read",expected,m.dout);};
        for(unsigned a=0;a<32768;++a)read(a,a<2048?program[a]:a==0x1d80?0xc2:255);
        for(unsigned a=0;a<2048;++a){write(a,255-program[a]);read(a,program[a]);}
        for(unsigned command=0;command<128;++command)for(unsigned status=0;status<2;++status){m.command=command;m.ctl_status=status;read(0x1d80,command+(status?0:128));}
        for(unsigned data=0;data<256;++data)for(unsigned a=0x1ddc;a<=0x1ddf;++a)write(a,data);
        for(unsigned low=0;low<256;++low)for(unsigned high=0;high<256;++high){write(0x1d00,low);write(0x1d40,high);}
        write(0x1d00,0);write(0x1d40,0);m.req=0;m.bit_req=1;m.clk=0;m.eval();
        for(unsigned n=0;n<65552;++n) {
            unsigned index=pointer%32768,expected=(serial[index/8]>>(index%8))&1;
            b.check(m.bit_ready,"speech_bit_ready",1,m.bit_ready);b.tick();pointer=index+1;last_bit=expected;
            b.check(m.bit_valid && m.bit_data==expected,"speech_serial_bit",expected,m.bit_data);controls();
        }
        m.bit_req=0;for(unsigned n=0;n<8;++n){b.tick();b.check(!m.bit_valid && m.bit_data==last_bit,"speech_bit_hold",last_bit,m.bit_data);controls();}
        // Held CPU reads and rejected writes cannot change response or latches.
        m.command=0x55;m.ctl_status=0;read(0x1d80,0xd5);m.ready=0;
        for(unsigned a:{0x1d00u,0x1d40u,0x1ddcu,0x1dddu,0x1ddeu,0x1ddfu}) {
            m.wr=1;m.address=a;m.din=1;b.tick();controls();b.check(!m.ctl_wr && !m.pdc_wr && m.dout==0xd5,"speech_stall",0xd5,m.dout);
        }
        m.ready=1;m.req=0;m.wr=0;m.address=0;m.command=0;b.tick();b.check(m.dout==0xd5,"speech_read_hold",0xd5,m.dout);
        // Pointer write wins; consumer retains request and retries next edge.
        m.bit_req=1;m.req=1;m.wr=1;m.address=0x1d00;m.din=0x7b;m.clk=0;m.eval();
        b.check(!m.bit_ready,"speech_pointer_priority",0,m.bit_ready);write(0x1d00,0x7b);
        b.check(!m.bit_valid,"speech_pointer_priority",0,m.bit_valid);
        m.req=0;unsigned index=pointer%32768;b.tick();pointer=index+1;last_bit=(serial[index/8]>>(index%8))&1;
        b.check(m.bit_valid && m.bit_data==last_bit,"speech_pointer_retry",last_bit,m.bit_data);controls();
        // Same-byte serial download forwards its new selected bit.
        index=pointer%32768;m.data_dl_wr=1;m.data_dl_addr=index/8;m.dl_data=serial[index/8]^255;
        serial[index/8]=m.dl_data;b.tick();pointer=index+1;last_bit=(serial[index/8]>>(index%8))&1;
        b.check(m.bit_data==last_bit,"speech_serial_forward",last_bit,m.bit_data);controls();m.data_dl_wr=0;m.bit_req=0;
        m.reset=1;m.req=1;m.wr=1;m.address=0x1ddc;m.din=0;b.tick();latches=pdc=pointer=last_bit=0;controls();
        b.check(!m.bit_valid && !m.bit_ready && !m.ctl_wr && !m.pdc_wr,"speech_reset",0,m.bit_valid);
        m.wr=0;m.program_dl_wr=1;m.program_dl_addr=0;m.address=0;m.dl_data=0x5a;program[0]=0x5a;b.tick();
        b.check(m.dout==0x5a,"speech_program_forward",0x5a,m.dout);m.program_dl_wr=0;m.reset=0;read(0,0x5a);
        // Address-looking I/O writes must not alias speech control registers.
        for(unsigned a:{0x1d00u,0x1d40u,0x1ddcu,0x1ddfu}){m.memory_space=0;m.wr=1;m.address=a;m.din=0;b.tick();controls();m.wr=0;b.tick();b.check(m.dout==255,"speech_io_unmapped",255,m.dout);}
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
