#include "Vcvs_decode.h"
#include "common.hpp"
int main(int argc,char** argv) {
    setup(argc,argv); Bench<Vcvs_decode> b(argc,argv);
    try {
        // Independent expected pin truth clauses from U15L's eight equations.
        // Output 0 selects all address bits high; output 7 selects all low.
        const unsigned group[8]={7,6,5,4,3,2,1,0};
        for(unsigned dec5=0;dec5<2;++dec5)for(unsigned dec6=0;dec6<2;++dec6)
            for(unsigned address=0;address<8;++address) {
                b.rtl.dec5_n=dec5;b.rtl.dec6_n=dec6;b.rtl.address_hi=address;b.rtl.eval();b.dump(0);
                unsigned expected=255;
                for(unsigned pin=0;pin<8;++pin)
                    if((!dec5 || !dec6) && address==group[pin]) expected &= ~(1u<<pin);
                b.check(b.rtl.pal_dec_n==expected,"pal_decode",expected,b.rtl.pal_dec_n);
                // No clock is consumed; increment only to give each input a stable ID.
                ++b.cycle;
            }
        b.pass();return 0;
    } catch(const Failure&) { return 1; }
}
