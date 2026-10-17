// SPDX-License-Identifier: BSD-3-Clause
#include "Vcvs_scan.h"
#include "common.hpp"
int main(int argc,char** argv){
    setup(argc,argv);Bench<Vcvs_scan> b(argc,argv);
    try{
        constexpr uint64_t frame=227*312;
        uint64_t enabled=0,ticks=0,requests=0,all_requests=0,lines=0;
        unsigned delay=0, pixel_phase=0, active_pixel=0, line_pixels=0;
        bool saw_hrst=false;
        b.rtl.reset=1;b.rtl.run=1;b.tick();b.rtl.reset=0;
        auto step=[&](bool run){
            b.rtl.run=run;b.rtl.eval();
            unsigned h=ticks%227,v=((ticks+frame-6)/227)%312+1;
            bool ce_position=run && enabled%16==15;
            bool hrst=h>=6 && h<50, vrst=v>=1 && v<43;
            bool view=v>=51 && v<=298;
            bool pixel=run && !hrst && pixel_phase==11;
            bool visible=view;
            bool line=run && (delay&2);
            b.check(bool(b.rtl.pixel_ce_all)==pixel,"scan_pck_enable",pixel,b.rtl.pixel_ce_all);
            b.check(bool(b.rtl.pixel_ce)==(pixel&&view),"scan_viewport_enable",pixel&&view,b.rtl.pixel_ce);
            b.check(bool(b.rtl.line_start)==line,"scan_line_delay",line,b.rtl.line_start);
            b.check(b.rtl.pixel_x==active_pixel && b.rtl.pixel_y==((v+256-43)%256),"scan_native_coordinates",active_pixel+256*((v+256-43)%256),b.rtl.pixel_x+256*b.rtl.pixel_y);
            b.check(bool(b.rtl.visible)==visible,"scan_visible",visible,b.rtl.visible);
            if(pixel){ ++all_requests; if(view)++requests; ++line_pixels;
                b.check(active_pixel<244,"scan_pixel_index",243,active_pixel); }
            if(line)++lines;
            bool rawline=ce_position && h==5;
            if(run){
                delay=((delay*2)|rawline)&3;
                if(ce_position && h==5){ pixel_phase=0; active_pixel=0; }
                else if(hrst){ pixel_phase=0; active_pixel=0; line_pixels=0; saw_hrst=true; }
                else if(pixel_phase==11){ pixel_phase=0; ++active_pixel; }
                else ++pixel_phase;
            }
            b.tick();if(run)++enabled;if(ce_position)++ticks;
            if(run && ce_position && h==5){
                if(saw_hrst)b.check(line_pixels==244,"scan_active_width_244",244,line_pixels);
                line_pixels=0;
            }
        };
        bool paused_pending_line=false;
        while(ticks<2*frame+6){
            if(!paused_pending_line && (delay&2)){
                for(unsigned n=0;n<7;++n)step(false);
                paused_pending_line=true;
            }
            step(b.cycle%101>=5);
        }
        b.check(paused_pending_line,"scan_pause_fixture",1,paused_pending_line);
        b.check(requests==2*244*248,"scan_field_size",2*244*248,requests);
        b.check(lines==624,"scan_line_count",624,lines);
        b.check(all_requests>=2*244*312,"scan_full_raster_pixels",2*244*312,all_requests);
        b.rtl.reset=1;b.rtl.run=0;b.tick();b.rtl.eval();
        b.check(!b.rtl.line_start && !b.rtl.pixel_ce_all,"scan_reset",0,b.rtl.line_start);
        b.rtl.reset=0;enabled=0;ticks=0;delay=0;pixel_phase=0;active_pixel=0;line_pixels=0;saw_hrst=false;
        for(unsigned n=0;n<300;++n)step(n%7!=0);
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
