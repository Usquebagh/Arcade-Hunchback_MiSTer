// SPDX-License-Identifier: BSD-3-Clause
// Address/sign oracle using separately frozen pinned numeric reference facts.
#include "Vcvs_tms5100_tables.h"
#include "tms5100_reference.hpp"
#include "common.hpp"
int main(int argc,char** argv) {
    setup(argc,argv);Vcvs_tms5100_tables m;
    uint64_t cycle=0;
    uint64_t trace_start=UINT64_MAX;
    std::unique_ptr<VerilatedVcdC> trace;
    for(int n=1;n+1<argc;++n)if(std::string(argv[n])=="--trace-start")trace_start=std::stoull(argv[n+1]);
    if(trace_start!=UINT64_MAX){trace=std::make_unique<VerilatedVcdC>();m.trace(trace.get(),2);trace->open("failure.vcd");}
    auto check=[&](bool condition,const char* label,int expected,int got){
        ++cycle;if(trace && cycle>=trace_start && cycle<trace_start+2048)trace->dump(cycle*20);
        if(!condition){std::cout<<"BDSM {\"status\":\"FAIL\",\"label\":\""<<label<<"\",\"cycle\":"<<cycle<<",\"expected\":"<<expected<<",\"observed\":"<<got<<"}\n";throw Failure(label);}
    };
    auto signed_value=[](unsigned value,unsigned bits){return int(value)-((value>>(bits-1))?int(1u<<bits):0);};
    using namespace tmc0281_reference;
    try {
        m.energy_address=m.pitch_address=m.k_slot=m.k_index=m.chirp_address=m.interpolation_address=0;
        for(unsigned a=0;a<16;++a){m.energy_address=a;m.eval();check(m.energy==energy[a],"tms_energy_table",energy[a],m.energy);}
        for(unsigned a=0;a<32;++a){m.pitch_address=a;m.eval();check(m.pitch==pitch[a],"tms_pitch_table",pitch[a],m.pitch);}
        for(unsigned slot=0;slot<16;++slot)for(unsigned index=0;index<32;++index){
            m.k_slot=slot;m.k_index=index;m.eval();
            int want=slot<10 && index<(1u<<widths[slot])?k[slot][index]:0;
            int got=signed_value(m.coefficient,10);check(got==want,"tms_k_table",want,got);
        }
        for(unsigned a=0;a<64;++a){m.chirp_address=a;m.eval();int want=a<52?signed_value(chirp[a],8):0;int got=signed_value(m.chirp,8);check(want==got,"tms_chirp_table",want,got);}
        for(unsigned a=0;a<8;++a){m.interpolation_address=a;m.eval();check(m.interpolation_shift==interpolation[a],"tms_interp_table",interpolation[a],m.interpolation_shift);}
        // Simultaneously changing every address must not retain another ROM's value.
        for(unsigned n=0;n<4096;++n){
            unsigned e=n%16,p=(n*7)%32,s=(n/32)%16,i=(n*13)%32,c=(n*5)%64,t=(n/7)%8;
            m.energy_address=e;m.pitch_address=p;m.k_slot=s;m.k_index=i;m.chirp_address=c;m.interpolation_address=t;m.eval();
            int want=s<10 && i<(1u<<widths[s])?k[s][i]:0;
            check(m.energy==energy[e] && m.pitch==pitch[p] && signed_value(m.coefficient,10)==want && signed_value(m.chirp,8)==(c<52?signed_value(chirp[c],8):0) && m.interpolation_shift==interpolation[t],"tms_table_isolation",want,signed_value(m.coefficient,10));
        }
        m.final();std::cout<<"BDSM {\"status\":\"PASS\",\"cycle\":"<<cycle<<",\"observed\":\"Exhaustive TMC0281 numeric ROM addresses, signed values, invalid defaults and simultaneous address changes; pinned reference facts, no LPC voice\"}\n";return 0;
    }catch(const Failure&){m.final();return 1;}
}
