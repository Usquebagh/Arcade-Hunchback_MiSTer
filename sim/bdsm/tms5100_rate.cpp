// SPDX-License-Identifier: BSD-3-Clause
// Absolute-time cadence oracle; no recursive accumulator reference.
#include "Vcvs_tms5100_rate.h"
#include "common.hpp"
int main(int argc,char** argv) {
    setup(argc,argv);Bench<Vcvs_tms5100_rate> b(argc,argv);auto& m=b.rtl;
    try {
        constexpr uint64_t master=57272724,rate=7750;
        auto epoch=[&](uint64_t edges){
            uint64_t count=0,last=0;bool previous=false;
            for(uint64_t n=1;n<=edges;++n){
                m.clk=0;m.eval();bool due=(n*rate)/master!=((n-1)*rate)/master;
                b.check(m.sample_tick==due,"tms_rate_linear_time",due,m.sample_tick);
                b.check(!due || !previous,"tms_rate_one_edge",0,previous);
                if(due){++count;if(last)b.check(n-last==7390 || n-last==7391,"tms_rate_interval",7390,n-last);last=n;}
                previous=due;b.tick();
            }
            b.check(count==(edges*rate)/master,"tms_rate_count",(edges*rate)/master,count);
        };
        m.reset=1;b.tick();m.reset=0;epoch(16000000);
        for(unsigned phase:{1u,2u,191u,4096u,7389u,7390u,14779u}){
            m.reset=1;m.eval();b.check(!m.sample_tick,"tms_rate_reset_gate",0,m.sample_tick);b.tick();m.reset=0;epoch(phase);
            m.reset=1;m.eval();b.check(!m.sample_tick,"tms_rate_reset_gate",0,m.sample_tick);b.tick();m.reset=0;epoch(50000);
        }
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
