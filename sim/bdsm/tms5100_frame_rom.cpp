// SPDX-License-Identifier: BSD-3-Clause
// Independently encoded frames downloaded into real bus ROMs, no game bytes.
#include "Vcvs_tms5100_frame_rom_tb.h"
#include "common.hpp"
#include <array>
#include <vector>
struct Packet {unsigned energy,pitch,repeat;std::array<unsigned,10> k;std::vector<unsigned> bits;};
int main(int argc,char** argv) {
    setup(argc,argv);Bench<Vcvs_tms5100_frame_rom_tb> b(argc,argv);auto& m=b.rtl;
    try {
        constexpr std::array<unsigned,10> widths={5,5,4,4,4,4,4,3,3,3};
        auto encode=[&](Packet& f){
            auto field=[&](unsigned value,unsigned width){for(unsigned n=width;n>0;--n)f.bits.push_back((value>>(n-1))&1);};
            field(f.energy,4);if(f.energy && f.energy!=15){field(f.repeat,1);field(f.pitch,5);if(!f.repeat)for(unsigned k=0;k<(f.pitch?10u:4u);++k)field(f.k[k],widths[k]);}
        };
        std::vector<Packet> packets;
        for(unsigned e=0;e<16;++e)for(unsigned p=0;p<32;++p)for(unsigned rep=0;rep<2;++rep){
            Packet f{e,p,rep,{},{}};for(unsigned k=0;k<10;++k)f.k[k]=(e*11+p*7+rep*3+k*5)%(1u<<widths[k]);encode(f);packets.push_back(f);
        }
        // Place voiced/unvoiced/voiced-repeat retention before the exhaustive set.
        std::array<unsigned,10> initial={31,17,15,8,13,12,11,7,6,5};
        Packet voiced{9,23,0,initial,{}};encode(voiced);
        Packet unvoiced{5,0,0,{3,4,5,6,0,0,0,0,0,0},{}};encode(unvoiced);
        Packet repeated{7,31,1,{},{}};encode(repeated);
        packets.insert(packets.begin(),{voiced,unvoiced,repeated});
        std::vector<unsigned> stream;for(const auto& f:packets)stream.insert(stream.end(),f.bits.begin(),f.bits.end());
        b.check(stream.size()<32768,"tms_frame_rom_fixture_size",32768,stream.size());
        std::array<unsigned,4096> rom{};for(unsigned n=0;n<4096;++n)rom[n]=(n*53+91)%256;
        auto place=[&](const std::vector<unsigned>& bits,unsigned start){for(unsigned n=0;n<bits.size();++n){unsigned a=(start+n)%32768;rom[a/8]=(rom[a/8]&~(1u<<(a%8)))+(bits[n]<<(a%8));}};
        place(stream,32760);
        m.reset=1;m.frame_req=m.cpu_req=m.data_dl_wr=0;m.cpu_ready=1;m.cpu_address=m.cpu_data=0;b.tick();
        auto download=[&](){for(unsigned n=0;n<4096;++n){m.data_dl_wr=1;m.data_dl_addr=n;m.dl_data=rom[n];b.tick();}m.data_dl_wr=0;};
        download();m.reset=0;
        auto pointer_write=[&](unsigned address,unsigned value){m.cpu_req=1;m.cpu_address=address;m.cpu_data=value;b.tick();m.cpu_req=0;};
        pointer_write(0x1d00,255);pointer_write(0x1d40,15);
        unsigned pointer=32760,consumed=0,e=0,p=0,rep=0,mask=0;std::array<unsigned,10> oldk{};
        auto packed=[&](){uint64_t v=0;for(unsigned k=0;k<10;++k)v+=uint64_t(oldk[k])<<(k*5);return v;};
        auto tick=[&](){
            m.clk=0;m.eval();bool accepted=m.serial_req && m.serial_ready;
            unsigned index=pointer%32768,want=(rom[index/8]>>(index%8))&1;
            b.tick();if(accepted){pointer=index+1;++consumed;b.check(m.serial_valid && m.serial_bit==want,"tms_frame_rom_serial",want,m.serial_bit);}
            b.check(m.bit_address==pointer,"tms_frame_rom_pointer",pointer,m.bit_address);
            b.check(!m.protocol_error && m.control_latches==0 && m.ctl==0 && !m.pdc && !m.ctl_wr && !m.pdc_wr && m.cpu_ack==m.cpu_ready,"tms_frame_rom_isolation",0,m.protocol_error);
        };
        for(const auto& f:packets){
            unsigned before=consumed;m.frame_req=1;tick();m.frame_req=0;
            for(unsigned n=0;n<200 && !m.frame_valid;++n)tick();
            b.check(m.frame_valid && consumed-before==f.bits.size(),"tms_frame_rom_length",f.bits.size(),consumed-before);
            e=f.energy;rep=mask=0;if(e && e!=15){p=f.pitch;rep=f.repeat;mask=p==0;if(!rep)for(unsigned k=0;k<(p?10u:4u);++k)oldk[k]=f.k[k];}
            b.check(m.energy_index==e && m.pitch_index==p && m.repeat_frame==rep && m.unvoiced_mask==mask && m.stop_frame==(e==15) && m.coefficient_indices==packed(),"tms_frame_rom_fields",packed(),m.coefficient_indices);
            tick();b.check(!m.frame_valid && m.frame_ready,"tms_frame_rom_valid",1,m.frame_ready);
        }
        b.check(consumed==stream.size(),"tms_frame_rom_total",stream.size(),consumed);
        // Relocate a frame halfway through a field. CPU high/low writes win twice.
        m.reset=1;b.tick();place(voiced.bits,32760);
        std::vector<unsigned> suffix(voiced.bits.begin()+6,voiced.bits.end());place(suffix,0x200);download();m.reset=0;
        pointer_write(0x1d00,255);pointer_write(0x1d40,15);pointer=32760;consumed=0;
        m.frame_req=1;tick();m.frame_req=0;
        for(unsigned n=0;n<100 && consumed<6;++n)tick();
        for(unsigned n=0;n<4 && !m.serial_req;++n)tick();
        b.check(consumed==6 && m.serial_req,"tms_frame_rom_priority_fixture",6,consumed);
        for(unsigned n=0;n<2;++n){
            m.cpu_req=1;m.cpu_address=n?0x1d00:0x1d40;m.cpu_data=n?0x40:0;m.clk=0;m.eval();
            b.check(!m.serial_ready,"tms_frame_rom_cpu_priority",0,m.serial_ready);
            b.tick();pointer=n?0x200:pointer%2048;
            b.check(m.bit_address==pointer && !m.serial_valid && m.serial_req,"tms_frame_rom_cpu_priority",pointer,m.bit_address);
        }
        m.cpu_req=0;
        for(unsigned n=0;n<200 && !m.frame_valid;++n)tick();
        uint64_t expected=0;for(unsigned k=0;k<10;++k)expected+=uint64_t(initial[k])<<(5*k);
        b.check(m.frame_valid && consumed==49 && m.energy_index==9 && m.pitch_index==23 && m.coefficient_indices==expected && m.bit_address==0x22b,"tms_frame_rom_retry_fields",expected,m.coefficient_indices);
        // Shared reset cancels a response already issued by the actual ROM bus.
        tick();m.frame_req=1;tick();m.frame_req=0;tick();b.check(m.serial_valid,"tms_frame_rom_reset_fixture",1,m.serial_valid);
        m.reset=1;b.tick();m.reset=0;b.tick();
        b.check(m.frame_ready && !m.frame_valid && !m.busy && !m.serial_valid && m.bit_address==0 && m.coefficient_indices==0,"tms_frame_rom_reset",0,m.bit_address);
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
