// SPDX-License-Identifier: BSD-3-Clause
// Independent field encoder and persistent raw-index model, not an LPC model.
#include "Vcvs_tms5100_frames.h"
#include "common.hpp"
#include <array>
#include <vector>
int main(int argc,char** argv) {
    setup(argc,argv);Bench<Vcvs_tms5100_frames> b(argc,argv);auto& m=b.rtl;
    try {
        unsigned energy=0,pitch=0,repeat=0,mask=0;
        std::array<unsigned,10> indices{};
        constexpr std::array<unsigned,10> widths={5,5,4,4,4,4,4,3,3,3};
        auto packed=[&](){uint64_t value=0;for(unsigned i=0;i<10;++i)value+=uint64_t(indices[i])<<(i*5);return value;};
        auto outputs=[&](const char* label){
            b.check(m.energy_index==energy && m.pitch_index==pitch && m.repeat_frame==repeat && m.unvoiced_mask==mask && m.stop_frame==(energy==15) && m.coefficient_indices==packed(),label,packed(),m.coefficient_indices);
        };
        m.reset=1;m.clear=m.frame_req=m.bit_ready=m.bit_valid=m.bit_data=0;b.tick();m.reset=0;
        auto emit=[](std::vector<unsigned>& bits,unsigned value,unsigned width){for(unsigned n=width;n>0;--n)bits.push_back((value/(1u<<(n-1)))%2);};
        auto encode=[&](unsigned e,unsigned p,unsigned rep,const std::array<unsigned,10>& k){
            std::vector<unsigned> bits;emit(bits,e,4);
            if(e!=0 && e!=15){emit(bits,rep,1);emit(bits,p,5);if(!rep)for(unsigned i=0;i<(p?10u:4u);++i)emit(bits,k[i],widths[i]);}
            return bits;
        };
        auto start=[&](){m.eval();b.check(m.frame_ready && !m.busy,"tms_frame_ready",1,m.frame_ready);m.frame_req=1;b.tick();m.frame_req=0;b.check(m.busy && !m.frame_ready && !m.frame_valid,"tms_frame_start",1,m.busy);};
        auto one_bit=[&](unsigned bit,unsigned number,bool final){
            b.check(m.bit_req,"tms_frame_request",1,m.bit_req);
            unsigned stalls=number%7;
            for(unsigned n=0;n<stalls;++n){m.bit_valid=(n%2)==0;m.bit_data=1-bit;b.tick();outputs("tms_frame_atomic");b.check(m.bit_req && !m.frame_valid,"tms_frame_retry",1,m.bit_req);}
            m.bit_valid=0;m.bit_ready=1;b.tick();m.bit_ready=0;
            b.check(!m.bit_req && m.busy,"tms_frame_one_outstanding",0,m.bit_req);
            for(unsigned n=0;n<number%5;++n){b.tick();outputs("tms_frame_atomic");b.check(!m.bit_req && !m.frame_valid,"tms_frame_response_wait",0,m.frame_valid);}
            m.bit_data=bit;m.bit_valid=1;b.tick();m.bit_valid=0;
            if(!final){outputs("tms_frame_atomic");b.check(m.busy && !m.frame_valid,"tms_frame_length",0,m.frame_valid);}
            else b.check(m.frame_valid && !m.busy && !m.bit_req,"tms_frame_length",1,m.frame_valid);
        };
        unsigned frames=0;
        auto frame=[&](unsigned e,unsigned p,unsigned rep,const std::array<unsigned,10>& k){
            auto bits=encode(e,p,rep,k);unsigned expected_length=e==0 || e==15?4:rep?10:p?49:28;
            b.check(bits.size()==expected_length,"tms_encoder_length",expected_length,bits.size());start();
            for(unsigned n=0;n<bits.size();++n)one_bit(bits[n],n+frames,n+1==bits.size());
            energy=e;repeat=0;mask=0;
            if(e!=0 && e!=15){pitch=p;repeat=rep;mask=p==0;if(!rep)for(unsigned i=0;i<(p?10u:4u);++i)indices[i]=k[i];}
            outputs("tms_frame_fields");
            for(unsigned n=0;n<3;++n){m.bit_valid=1;m.bit_data=n%2;b.tick();outputs("tms_frame_hold");b.check(!m.frame_valid && !m.busy && !m.bit_req,"tms_frame_valid_pulse",0,m.frame_valid);}
            m.bit_valid=0;++frames;
        };
        std::array<unsigned,10> k={31,17,15,8,13,12,11,7,6,5};
        frame(9,23,0,k);k={3,4,5,6,0,0,0,0,0,0};frame(5,0,0,k);frame(7,31,1,k);
        b.check((m.coefficient_indices>>20)==(uint64_t(13)+(uint64_t(12)<<5)+(uint64_t(11)<<10)+(uint64_t(7)<<15)+(uint64_t(6)<<20)+(uint64_t(5)<<25)),"tms_retained_high_k",13,(m.coefficient_indices>>20)&31);
        frame(0,0,0,k);frame(15,0,0,k);frame(4,1,1,k);
        for(unsigned e=0;e<16;++e)for(unsigned p=0;p<32;++p)for(unsigned rep=0;rep<2;++rep){
            for(unsigned i=0;i<10;++i)k[i]=(e*13+p*7+i*11+rep)% (1u<<widths[i]);frame(e,p,rep,k);
        }
        for(unsigned slot=0;slot<10;++slot)for(unsigned value=0;value<(1u<<widths[slot]);++value){
            for(unsigned i=0;i<10;++i)k[i]=(slot*3+i*7+value)%(1u<<widths[i]);k[slot]=value;frame(1+value%14,1+slot,0,k);
        }
        // Abort after every bit position, both with and without an accepted read.
        for(unsigned length:{4u,10u,28u,49u})for(unsigned pos=0;pos<length;++pos)for(unsigned waiting=0;waiting<2;++waiting){
            auto bits=encode(length==4?15:6,length==28?0:19,length==10,k);start();
            for(unsigned n=0;n<pos;++n)one_bit(bits[n],n,false);
            if(waiting){m.bit_ready=1;b.tick();m.bit_ready=0;}
            m.clear=(pos%2)==0;m.reset=!m.clear;b.tick();m.clear=m.reset=0;
            energy=pitch=repeat=mask=0;indices.fill(0);outputs("tms_frame_clear");
            b.check(!m.busy && !m.bit_req && !m.frame_valid && !m.protocol_error,"tms_frame_cancel",0,m.busy);
            m.bit_valid=1;m.bit_data=1;b.tick();m.bit_valid=0;outputs("tms_frame_stale_response");
            b.check(!m.frame_valid && m.frame_ready,"tms_frame_restart",1,m.frame_ready);
        }
        start();m.frame_req=1;b.tick();m.frame_req=0;
        b.check(m.protocol_error && m.busy && m.bit_req,"tms_frame_busy_request",1,m.protocol_error);
        m.clear=1;b.tick();m.clear=0;energy=pitch=repeat=mask=0;indices.fill(0);
        frame(8,7,0,k);b.check(!m.protocol_error,"tms_frame_error_clear",0,m.protocol_error);
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
