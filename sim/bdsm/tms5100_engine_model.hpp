// SPDX-License-Identifier: BSD-3-Clause
// Frozen independent logical reference copied from the demonstrated standalone
// sequence oracle, not extracted from HDL; duplicate kept to preserve its proof.
#pragma once
#include <array>
#include <algorithm>
#include "tms5100_reference.hpp"
struct SequenceFrame {unsigned e,p,rep;std::array<unsigned,10> indices;};
struct SequenceModel {
    unsigned ip=0,pc=0,sub=0,reload=1,rng=8191,pitch_count=0,e=0,p=0,raw_e=0,raw_p=0;
    bool spen=0,talk=0,talkd=0,old_e=1,old_p=1,inhibit=1,pitch_zero=0,zpar=0,uvzero=0;
    bool active=0;int excitation=0;
    std::array<unsigned,10> raw_k{};std::array<int,10> k{},target_k{};
    unsigned target_e=0,target_p=0;
    bool frame_due()const{return talkd && ip==0 && pc==12 && sub==1;}
    bool status()const{return spen || talkd;}
    void speak(bool slow){spen=talk=1;reload=!slow;old_e=old_p=zpar=uvzero=1;}
    static int floor_shift(int value,unsigned shift){int divisor=1<<shift;return value>=0?value/divisor:-((-value+divisor-1)/divisor);}
    void frame(const SequenceFrame& f){
        raw_e=f.e;uvzero=0;zpar=0;
        if(f.e && f.e!=15){raw_p=f.p;uvzero=f.p==0;if(!f.rep)for(unsigned i=0;i<(f.p?10u:4u);++i)raw_k[i]=f.indices[i];}
        target_e=tmc0281_reference::energy[raw_e];target_p=tmc0281_reference::pitch[raw_p];
        for(unsigned i=0;i<10;++i)target_k[i]=tmc0281_reference::k[i][raw_k[i]];
        inhibit=(old_p!=(raw_p==0)) || (old_e && raw_e!=0);
        if(raw_e==15)spen=talk=0;
    }
    void step(const SequenceFrame* f){
        active=talkd;
        if(active){
            if(f)frame(*f);
            else if(sub==2){
                unsigned shift=tmc0281_reference::interpolation[ip];bool blocked=inhibit && ip!=0;
                auto next=[&](int old,int target,bool zero){return zero?0:old+(blocked?0:floor_shift(target-old,shift));};
                if(pc==0){e=next(e,target_e,zpar);if(ip==0)pitch_zero=0;}
                else if(pc==1)p=next(p,target_p,zpar);
                else if(pc<12)k[pc-2]=next(k[pc-2],target_k[pc-2],(pc<6)?zpar:uvzero);
            }
            excitation=old_p?(rng%2?-64:64):int(tmc0281_reference::chirp[std::min(pitch_count,51u)]);
            if(excitation>=128)excitation-=256;
            for(unsigned n=0;n<20;++n){unsigned bit=((rng/4096)%2)^((rng/8)%2)^((rng/4)%2)^(rng%2);rng=(rng*2+bit)%8192;}
        }
        ++sub;
        if(sub==2 && pc==12){
            if(ip==7){
                if(active){if(inhibit)pitch_zero=1;old_e=raw_e==0;old_p=raw_p==0;}
                bool old_talk=talk;talkd=old_talk;if(!old_talk && spen)talk=1;
            }
            sub=reload;pc=0;ip=(ip+1)%8;
        }else if(sub==3){sub=reload;++pc;}
        if(active){++pitch_count;if(pitch_count>=p || pitch_zero)pitch_count=0;pitch_count%=512;}
    }
};
