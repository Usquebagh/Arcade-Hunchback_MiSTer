// SPDX-License-Identifier: BSD-3-Clause
// Wide-integer recurrence and floor-division oracle; HDL stores modular state.
#include "Vcvs_tms5100_lattice_tb.h"
#include "tms5100_reference.hpp"
#include "common.hpp"
#include <array>
#include <algorithm>
int main(int argc,char** argv) {
    setup(argc,argv);Bench<Vcvs_tms5100_lattice_tb> b(argc,argv);auto& m=b.rtl;
    try {
        auto wrap=[](int64_t value,unsigned bits){int64_t mod=int64_t(1)<<bits;int64_t low=((value%mod)+mod)%mod;return low>=mod/2?low-mod:low;};
        auto floor_div=[](int64_t value,int64_t divisor){return value>=0?value/divisor:-((-value+divisor-1)/divisor);};
        auto matrix=[&](int64_t a,int64_t value){return floor_div(wrap(a,10)*wrap(value,15),512);};
        auto pcm=[&](int64_t raw){int64_t c=std::clamp(raw,int64_t(-2048),int64_t(2047));int64_t q=floor_div(c,16)*16;return q*16+((q&0x7f0)/8)+((q&0x400)/1024);};
        std::array<int64_t,10> x{};unsigned previous_energy=0;
        auto model=[&](unsigned energy,int excitation,const std::array<int,10>& k){
            std::array<int64_t,11> u{};u[10]=matrix(previous_energy,excitation*64);
            for(int n=9;n>=0;--n)u[n]=u[n+1]-matrix(k[n],x[n]);
            for(int n=9;n>0;--n)x[n]=x[n-1]+matrix(k[n-1],u[n-1]);
            x[0]=u[0];previous_energy=energy;return wrap(u[0],15);
        };
        auto pack=[&](const std::array<int,10>& k){
            for(unsigned i=0;i<4;++i)m.coefficients[i]=0;
            for(unsigned i=0;i<10;++i){unsigned pos=i*10,v=unsigned(k[i])&1023;m.coefficients[pos/32]|=v<<(pos%32);if(pos%32>22)m.coefficients[pos/32+1]|=v>>(32-pos%32);}
        };
        m.reset=1;m.clear=m.sample_req=0;m.energy=m.excitation=m.probe_raw=0;std::array<int,10> k{};pack(k);b.tick();m.reset=0;
        for(int raw=-16384;raw<16384;++raw){m.probe_raw=raw&32767;m.eval();b.check(wrap(m.probe_pcm,16)==pcm(raw),"tms_lattice_pcm_probe",pcm(raw),wrap(m.probe_pcm,16));}
        int64_t held_raw=0,held_pcm=0;
        auto sample=[&](unsigned energy,int excitation,const std::array<int,10>& k,bool hostile){
            m.eval();b.check(m.sample_ready && !m.busy,"tms_lattice_ready",1,m.sample_ready);
            m.energy=energy;m.excitation=excitation&255;pack(k);m.sample_req=1;b.tick();m.sample_req=0;
            int64_t want=model(energy,excitation,k);
            b.check(m.busy && !m.sample_ready && !m.sample_valid,"tms_lattice_accept",1,m.busy);
            std::array<int,10> live{};for(unsigned i=0;i<10;++i)live[i]=511-k[i];pack(live);m.energy=127-energy;m.excitation=(excitation+57)&255;
            for(unsigned phase=1;phase<=20;++phase){
                m.sample_req=hostile && (phase==5 || phase==15);b.tick();
                b.check(m.sample_valid==(phase==20),"tms_lattice_latency",phase==20,m.sample_valid);
                if(phase<20)b.check(wrap(m.raw_sample,15)==held_raw && wrap(m.pcm_sample,16)==held_pcm,"tms_lattice_atomic",held_raw,wrap(m.raw_sample,15));
            }
            m.sample_req=0;
            b.check(wrap(m.raw_sample,15)==want,"tms_lattice_raw",want,wrap(m.raw_sample,15));
            b.check(wrap(m.pcm_sample,16)==pcm(want),"tms_lattice_pcm",pcm(want),wrap(m.pcm_sample,16));
            held_raw=want;held_pcm=pcm(want);
            for(unsigned n=0;n<2;++n){b.tick();b.check(!m.sample_valid && m.sample_ready && wrap(m.raw_sample,15)==held_raw && wrap(m.pcm_sample,16)==held_pcm,"tms_lattice_hold",held_pcm,wrap(m.pcm_sample,16));}
        };
        // Every unsigned energy and signed excitation combination, with zero K.
        for(unsigned e=0;e<128;++e)for(int excitation=-128;excitation<128;++excitation)sample(e,excitation,k,false);
        // Independent table-derived coefficient histories and signed extremes.
        uint32_t random=0x26500281;
        auto next=[&](){random=random*1664525u+1013904223u;return random;};
        for(unsigned n=0;n<4096;++n){for(unsigned i=0;i<10;++i)k[i]=tmc0281_reference::k[i][next()%(1u<<tmc0281_reference::widths[i])];sample(tmc0281_reference::energy[next()%15],int(next()%256)-128,k,false);}
        for(unsigned n=0;n<64;++n){for(unsigned i=0;i<10;++i)k[i]=(n/(1u<<(i%6)))%2?-512:511;sample((n*19)%128,int(n*31%256)-128,k,false);}
        sample(86,64,k,true);b.check(m.protocol_error,"tms_lattice_busy_reject",1,m.protocol_error);
        // Abort at every edge before completion; verify a fresh nonzero sample.
        for(unsigned phase=0;phase<20;++phase){
            m.clear=1;b.tick();m.clear=0;x.fill(0);previous_energy=0;held_raw=held_pcm=0;
            m.energy=86;m.excitation=95;pack(k);m.sample_req=1;b.tick();m.sample_req=0;
            for(unsigned n=0;n<phase;++n)b.tick();
            m.clear=phase%2;m.reset=!m.clear;b.tick();m.clear=m.reset=0;
            x.fill(0);previous_energy=0;held_raw=held_pcm=0;
            b.check(!m.busy && !m.sample_valid && !m.protocol_error && m.raw_sample==0 && m.pcm_sample==0,"tms_lattice_cancel",0,m.raw_sample);
            sample(86,95,k,false);sample(43,-91,k,false);
        }
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
