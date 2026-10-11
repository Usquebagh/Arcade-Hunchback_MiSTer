#include "Vcvs_reset.h"
#include "common.hpp"
int main(int argc,char** argv) {
    setup(argc,argv); Bench<Vcvs_reset> b(argc,argv);
    try {
        b.rtl.reset_async=1; b.rtl.pll_locked=1; b.rtl.load_active=0; b.rtl.rom_loaded=1;
        b.tick(); b.check(b.rtl.reset,"reset_assert",1,b.rtl.reset);
        b.rtl.reset_async=0;
        b.tick(); b.check(b.rtl.reset,"release_early",1,b.rtl.reset);
        b.tick(); b.check(!b.rtl.reset,"reset_release",0,b.rtl.reset);
        for(int blocker=0;blocker<3;++blocker) {
            b.rtl.pll_locked=blocker!=0; b.rtl.load_active=blocker==1; b.rtl.rom_loaded=blocker!=2;
            b.rtl.eval(); b.check(b.rtl.reset,"qualification",1,b.rtl.reset);
        }
        b.rtl.pll_locked=1;b.rtl.load_active=0;b.rtl.rom_loaded=1;b.rtl.eval();
        b.check(!b.rtl.reset,"ready",0,b.rtl.reset);
        b.rtl.clk=0;b.rtl.eval();b.rtl.reset_async=1;b.rtl.eval();
        b.check(b.rtl.reset,"async_assert",1,b.rtl.reset);
        b.rtl.reset_async=0;b.tick();b.check(b.rtl.reset,"second_release_early",1,b.rtl.reset);
        b.tick();b.check(!b.rtl.reset,"second_release",0,b.rtl.reset);
        b.pass(); return 0;
    } catch(const Failure&) { return 1; }
}
