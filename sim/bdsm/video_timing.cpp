#include "Vcvs_video_timing.h"
#include "common.hpp"
#ifndef V_LINES_EXPECTED
#define V_LINES_EXPECTED 312
#endif
// Independent linear time oracle. Constants transcribed in video-timing.md,
// never obtained by introspecting RTL counter values or parameters.
int main(int argc,char** argv){
    setup(argc,argv);Bench<Vcvs_video_timing> b(argc,argv);
    constexpr unsigned lines=V_LINES_EXPECTED, frame_ticks=227*lines;
    uint64_t enabled=0,ticks=0,frames=0,line_events=0;
    uint64_t hrst_ticks=0,vrst_ticks=0,hs_ticks=0,vs_ticks=0,cbf_ticks=0;
    try{
        b.rtl.reset=1;b.rtl.run=1;b.tick();b.rtl.reset=0;
        auto step=[&](bool run){
            b.rtl.run=run;b.rtl.eval();
            unsigned h=ticks%227;
            unsigned v=((ticks+uint64_t(frame_ticks)-6)/227)%lines+1;
            bool consume=run && enabled%16==15;
            b.check(bool(b.rtl.ce_position)==consume,"position_enable",consume,b.rtl.ce_position);
            bool new_line=consume && h==5,new_frame=new_line && v==lines;
            b.check(bool(b.rtl.line_start)==new_line,"line_strobe",new_line,b.rtl.line_start);
            b.check(bool(b.rtl.frame_start)==new_frame,"frame_strobe",new_frame,b.rtl.frame_start);
            if(new_line)++line_events;if(new_frame)++frames;
            // Count a complete steady frame of sampled positions, not repeated
            // master edges. [6,frame_ticks+6) begins at the first VRST edge.
            if(consume && ticks>=6 && ticks<frame_ticks+6){
                hrst_ticks+=h>=6 && h<50;vrst_ticks+=v<43;
                hs_ticks+=h>=11 && h<28;cbf_ticks+=h>=31 && h<40;
                uint64_t frame_pos=(ticks+frame_ticks-6)%frame_ticks;
                vs_ticks+=frame_pos>=10*227+22 && frame_pos<14*227+5;
            }
            b.tick();if(run)++enabled;if(consume)++ticks;
            h=ticks%227;v=((ticks+uint64_t(frame_ticks)-6)/227)%lines+1;
            b.check(b.rtl.h_count==h,"horizontal_position",h,b.rtl.h_count);
            b.check(b.rtl.v_count==v,"vertical_position",v,b.rtl.v_count);
            bool hrst=h>=6 && h<50,vrst=v<43;
            bool hs=h>=11 && h<28,cbf=h>=31 && h<40;
            uint64_t frame_pos=(ticks+frame_ticks-6)%frame_ticks;
            bool vs=frame_pos>=10*227+22 && frame_pos<14*227+5;
            b.check(bool(b.rtl.hrst)==hrst,"horizontal_reset",hrst,b.rtl.hrst);
            b.check(bool(b.rtl.vrst)==vrst,"vertical_reset",vrst,b.rtl.vrst);
            b.check(bool(b.rtl.blank)==(hrst||vrst),"composite_blank",hrst||vrst,b.rtl.blank);
            b.check(bool(b.rtl.cbf)==cbf,"burst_interval",cbf,b.rtl.cbf);
            b.check(bool(b.rtl.hsync_n)==!hs,"horizontal_sync",!hs,b.rtl.hsync_n);
            b.check(bool(b.rtl.vsync_n)==!vs,"vertical_sync",!vs,b.rtl.vsync_n);
        };
        for(unsigned n=0;n<7;++n)step(true);for(unsigned n=0;n<19;++n)step(false);
        // Two full frames and both VS boundaries; deterministic stalls preserve
        // phase while traversing every position under both count profiles.
        while(ticks<2*frame_ticks+30)step(b.cycle%97>=3);
        b.check(frames==3,"frame_count",3,frames);
        b.check(line_events==2*lines+1,"line_count",2*lines+1,line_events);
        b.check(hrst_ticks==44*lines,"horizontal_reset_width",44*lines,hrst_ticks);
        b.check(vrst_ticks==42*227,"vertical_reset_width",42*227,vrst_ticks);
        b.check(hs_ticks==17*lines,"horizontal_sync_width",17*lines,hs_ticks);
        b.check(cbf_ticks==9*lines,"burst_width",9*lines,cbf_ticks);
        b.check(vs_ticks==4*227-17,"vertical_sync_width",4*227-17,vs_ticks);
        // Reset at an arbitrary phase with run disabled; then verify restart.
        b.rtl.reset=1;b.rtl.run=0;b.tick();b.rtl.eval();
        b.check(b.rtl.h_count==0 && b.rtl.v_count==lines,"raster_reset",lines,b.rtl.v_count);
        b.check(!b.rtl.ce_position && !b.rtl.line_start && !b.rtl.frame_start,"reset_strobes",0,b.rtl.ce_position);
        b.rtl.reset=0;enabled=0;ticks=0;for(unsigned n=0;n<300;++n)step(n%5!=0);
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
