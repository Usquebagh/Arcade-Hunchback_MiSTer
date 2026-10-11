#include "Vcvs_clock.h"
#include "common.hpp"
int main(int argc,char** argv) {
    setup(argc,argv); Bench<Vcvs_clock> b(argc,argv);
    try {
        b.rtl.reset=1;b.tick();
        b.check(!b.rtl.ce_main && !b.rtl.ce_audio,"reset_clock",0,b.rtl.ce_main+b.rtl.ce_audio);
        b.rtl.reset=0; unsigned main_count=0,audio_count=0;
        for(unsigned n=1;n<=4096;++n) {
            b.tick();
            unsigned want_main=n%32==31, want_audio=n%64==63;
            b.check(b.rtl.ce_main==want_main,"main_cadence",want_main,b.rtl.ce_main);
            b.check(b.rtl.ce_audio==want_audio,"audio_cadence",want_audio,b.rtl.ce_audio);
            main_count+=b.rtl.ce_main;audio_count+=b.rtl.ce_audio;
            b.check(!b.rtl.ce_audio || b.rtl.ce_main,"phase_alignment",1,b.rtl.ce_main);
        }
        b.check(main_count==128,"main_count",128,main_count);
        b.check(audio_count==64,"audio_count",64,audio_count);
        b.rtl.reset=1;b.tick();b.rtl.reset=0;
        for(unsigned n=1;n<32;++n){b.tick();b.check(b.rtl.ce_main==(n==31),"restart_phase",n==31,b.rtl.ce_main);}
        b.pass();return 0;
    } catch(const Failure&) { return 1; }
}
