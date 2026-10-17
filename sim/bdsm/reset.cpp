#include "Vcvs_reset.h"
#include "common.hpp"
int main(int argc,char** argv) {
    setup(argc,argv); Bench<Vcvs_reset> b(argc,argv);
    try {
        constexpr int hold_cycles=1'140'000;
        auto release_after_hold=[&](const char* held_label,const char* release_label) {
            b.rtl.reset_async=0;
            b.tick(); b.check(b.rtl.reset,"release_early",1,b.rtl.reset);
            for(int cycle=0;cycle<hold_cycles-2;++cycle)b.tick();
            b.check(b.rtl.reset,held_label,1,b.rtl.reset);
            b.tick(); b.check(!b.rtl.reset,release_label,0,b.rtl.reset);
        };
        b.rtl.reset_async=1; b.rtl.pll_locked=1; b.rtl.load_active=0; b.rtl.rom_loaded=1;
        b.tick(); b.check(b.rtl.reset,"reset_assert",1,b.rtl.reset);
        release_after_hold("reset_minimum_hold","reset_release_after_hold");
        for(int blocker=0;blocker<3;++blocker) {
            b.rtl.pll_locked=blocker!=0; b.rtl.load_active=blocker==1; b.rtl.rom_loaded=blocker!=2;
            b.rtl.eval(); b.check(b.rtl.reset,"qualification",1,b.rtl.reset);
        }
        b.rtl.pll_locked=1;b.rtl.load_active=0;b.rtl.rom_loaded=1;b.rtl.eval();
        b.check(!b.rtl.reset,"ready",0,b.rtl.reset);
        b.rtl.clk=0;b.rtl.eval();b.rtl.reset_async=1;b.rtl.eval();
        b.check(b.rtl.reset,"async_assert",1,b.rtl.reset);
        release_after_hold("second_minimum_hold","second_release_after_hold");
        b.pass(); return 0;
    } catch(const Failure&) { return 1; }
}
