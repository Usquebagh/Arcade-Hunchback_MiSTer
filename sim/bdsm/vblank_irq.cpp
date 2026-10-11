#include "Vcvs_vblank_irq.h"
#include "common.hpp"
int main(int argc,char** argv){
    setup(argc,argv);Bench<Vcvs_vblank_irq> b(argc,argv);
    try{
        bool previous=false,pending=false;
        auto step=[&](bool blank,bool ack,bool reset=false){
            b.rtl.vblank=blank;b.rtl.intack=ack;b.rtl.reset=reset;
            // Independent event queue: reset discards history; a new event is
            // retained over a simultaneous acknowledgement; a held high is inert.
            if(reset){previous=false;pending=false;}
            else {bool new_event=blank&&!previous;previous=blank;
                  if(ack)pending=false;if(new_event)pending=true;}
            b.tick();b.check(bool(b.rtl.irq)==pending,"vblank_pending",pending,b.rtl.irq);
        };
        step(false,false,true);step(true,false);
        for(unsigned n=0;n<100;++n)step(true,false); // hold until acknowledged
        step(true,true);for(unsigned n=0;n<100;++n)step(true,false); // no retrigger
        step(false,false);step(true,true); // new event wins simultaneous ack
        step(true,true);step(false,true);step(true,false);step(true,false,true);
        // Every sequence of five blank/ack pairs, including sustained ack and
        // all edge histories. Each sequence starts from a real reset edge.
        for(unsigned sequence=0;sequence<1024;++sequence){
            step(false,false,true);
            for(unsigned k=0;k<5;++k)step((sequence>>(k*2))&1,(sequence>>(k*2+1))&1);
        }
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
