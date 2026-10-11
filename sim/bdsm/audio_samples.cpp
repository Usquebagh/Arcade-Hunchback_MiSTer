// SPDX-License-Identifier: BSD-3-Clause
// Independent linear-time cadence and integer raw-channel oracle.
#include "Vcvs_audio_samples.h"
#include "common.hpp"
#include <cstdint>

int main(int argc,char** argv) {
    setup(argc,argv);Bench<Vcvs_audio_samples> b(argc,argv);auto& m=b.rtl;
    try {
    uint64_t enabled_edges=0;
    unsigned want8=0,want4=0,samples=0;
    auto tick=[&](bool reset) {
        m.reset=reset;
        unsigned input8=m.dac8,input4=m.dac4;
        bool sample=false;
        if(reset) {enabled_edges=0;want8=want4=0;}
        else {
            ++enabled_edges;
            sample=enabled_edges*48000/57272724!=(enabled_edges-1)*48000/57272724;
            if(sample) {want8=uint16_t(int(input8)*256-32768);want4=uint16_t(int(input4)*4096-32768);++samples;}
        }
        b.tick();
        b.check(m.sample_ce==sample,"audio_sample_cadence",sample,m.sample_ce);
        b.check(m.pcm8==want8,"audio_sample8",want8,m.pcm8);
        b.check(m.pcm4==want4,"audio_sample4",want4,m.pcm4);
        return sample;
    };
    m.dac8=255;m.dac4=15;tick(true);
    // Every combination is sampled; after each one, inputs change while the
    // independent oracle requires the old output to hold until the next strobe.
    for(unsigned byte=0;byte<256;++byte)for(unsigned nibble=0;nibble<16;++nibble) {
        m.dac8=byte;m.dac4=nibble;
        while(!tick(false)) {}
        m.dac8=byte^255;m.dac4=nibble^15;
        for(unsigned n=0;n<17;++n)tick(false);
    }
    b.check(samples==4096,"audio_sample_count",4096,samples);
    // Arbitrary phase resets and rapidly changing input streams distinguish
    // pre-edge sampling, output hold and accumulator restart.
    uint32_t state=0x532631u;
    for(unsigned phase=0;phase<37;++phase) {
        for(unsigned n=0;n<phase*73+1;++n) {
            state=state*1664525u+1013904223u;m.dac8=state>>24;m.dac4=(state>>8)&15;tick(false);
        }
        tick(true);tick(true);
        for(unsigned n=0;n<2500;++n) {
            state=state*1664525u+1013904223u;m.dac8=state>>24;m.dac4=(state>>8)&15;tick(false);
        }
    }
    b.pass();return 0;
    } catch(const Failure&) {return 1;}
}
