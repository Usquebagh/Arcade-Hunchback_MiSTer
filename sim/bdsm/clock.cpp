#include "Vcvs_clock.h"
#include "common.hpp"
int main(int argc,char** argv) {
    setup(argc,argv); Bench<Vcvs_clock> b(argc,argv);
    try {
        b.rtl.reset=1;b.tick();
        b.check(!b.rtl.ce_main && !b.rtl.ce_audio,"reset_clock",0,b.rtl.ce_main+b.rtl.ce_audio);
        b.rtl.reset=0; unsigned main_count=0,audio_count=0,main_steps=0,audio_steps=0;
        for(unsigned n=1;n<=4096;++n) {
            b.tick();
            unsigned want_main=n%32==31, want_audio=n%64==63;
            b.check(b.rtl.ce_main==want_main,"main_cadence",want_main,b.rtl.ce_main);
            b.check(b.rtl.ce_audio==want_audio,"audio_cadence",want_audio,b.rtl.ce_audio);
            b.check(b.rtl.ce_main_step==(n%96==95),"main_step_cadence",n%96==95,b.rtl.ce_main_step);
            b.check(b.rtl.ce_audio_step==(n%192==191),"audio_step_cadence",n%192==191,b.rtl.ce_audio_step);
            main_count+=b.rtl.ce_main;audio_count+=b.rtl.ce_audio;
            main_steps+=b.rtl.ce_main_step;audio_steps+=b.rtl.ce_audio_step;
            b.check(!b.rtl.ce_audio || b.rtl.ce_main,"phase_alignment",1,b.rtl.ce_main);
        }
        b.check(main_count==128,"main_count",128,main_count);
        b.check(audio_count==64,"audio_count",64,audio_count);
        b.check(main_steps==42,"main_step_count",42,main_steps);
        b.check(audio_steps==21,"audio_step_count",21,audio_steps);
        b.rtl.reset=1;b.tick();b.rtl.reset=0;
        for(unsigned n=1;n<32;++n){b.tick();b.check(b.rtl.ce_main==(n==31),"restart_phase",n==31,b.rtl.ce_main);}
        b.pass();return 0;
    } catch(const Failure&) { return 1; }
}
