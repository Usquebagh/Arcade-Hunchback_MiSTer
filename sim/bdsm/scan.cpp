// SPDX-License-Identifier: BSD-3-Clause
#include "Vcvs_scan.h"
#include "common.hpp"
int main(int argc,char** argv){
    setup(argc,argv);Bench<Vcvs_scan> b(argc,argv);
    try{
        constexpr uint64_t frame=227*312;
        uint64_t enabled=0,ticks=0,requests=0,lines=0;
        unsigned delay=0;
        b.rtl.reset=1;b.rtl.run=1;b.tick();b.rtl.reset=0;
        auto step=[&](bool run){
            b.rtl.run=run;b.rtl.eval();
            unsigned h=ticks%227,v=((ticks+frame-6)/227)%312+1;
            bool ce=run && enabled%16==15,view=v>=43 && v<=298;
            bool pixel=ce && view,line=run && (delay&2);
            unsigned x=(h+221)%227,y=(v+256-43)%256;
            b.check(bool(b.rtl.pixel_ce)==pixel,"scan_request",pixel,b.rtl.pixel_ce);
            b.check(bool(b.rtl.line_start)==line,"scan_line_delay",line,b.rtl.line_start);
            b.check(b.rtl.pixel_x==x && b.rtl.pixel_y==y,"scan_coordinates",x+256*y,b.rtl.pixel_x+256*b.rtl.pixel_y);
            bool visible=view && !(h>=6 && h<50);
            b.check(bool(b.rtl.visible)==visible,"scan_visible",visible,b.rtl.visible);
            if(pixel)++requests;if(line)++lines;
            bool rawline=ce && h==5;
            if(run)delay=((delay*2)|rawline)&3;
            b.tick();if(run)++enabled;if(ce)++ticks;
        };
        while(ticks<2*frame+6)step(b.cycle%101>=5);
        b.check(requests==2*227*256,"scan_field_size",2*227*256,requests);
        b.check(lines==624,"scan_line_count",624,lines);
        b.rtl.reset=1;b.rtl.run=0;b.tick();b.rtl.eval();
        b.check(!b.rtl.line_start && !b.rtl.pixel_ce,"scan_reset",0,b.rtl.line_start);
        b.rtl.reset=0;enabled=0;ticks=0;delay=0;
        for(unsigned n=0;n<300;++n)step(n%7!=0);
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
