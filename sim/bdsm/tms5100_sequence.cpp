// SPDX-License-Identifier: BSD-3-Clause
// Independent logical-sample transcript model, decoded target fixture only.
#include "Vcvs_tms5100_sequence_tb.h"
#include "common.hpp"
#include "tms5100_reference.hpp"
#include <array>
#include <vector>
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
int main(int argc,char** argv) {
    setup(argc,argv);Bench<Vcvs_tms5100_sequence_tb> b(argc,argv);auto& m=b.rtl;
    try {
        SequenceModel model;
        auto pack=[&](const std::array<int,10>& k){for(unsigned i=0;i<4;++i)m.frame_coefficients[i]=0;for(unsigned i=0;i<10;++i){unsigned pos=i*10,v=unsigned(k[i])&1023;m.frame_coefficients[pos/32]|=v<<(pos%32);if(pos%32>22)m.frame_coefficients[pos/32+1]|=v>>(32-pos%32);}};
        auto signed_value=[](unsigned value,unsigned bits){return int(value)-((value>>(bits-1))?int(1u<<bits):0);};
        auto compare=[&](){
            b.check(m.interpolation_period==model.ip && m.parameter_counter==model.pc && m.subcycle==model.sub,"tms_sequence_phase",model.ip*100+model.pc*3+model.sub,m.interpolation_period*100+m.parameter_counter*3+m.subcycle);
            b.check(m.talk_status==model.status(),"tms_sequence_talk",model.status(),m.talk_status);
            b.check(m.parameter_energy==model.e && m.parameter_pitch==model.p,"tms_sequence_parameters",model.e*256+model.p,m.parameter_energy*256+m.parameter_pitch);
            for(unsigned i=0;i<10;++i){unsigned pos=i*10,v=m.parameter_coefficients[pos/32]>>(pos%32);if(pos%32>22)v|=m.parameter_coefficients[pos/32+1]<<(32-pos%32);int got=signed_value(v&1023,10);b.check(got==model.k[i],"tms_sequence_k",model.k[i],got);}
            b.check(m.rng==model.rng,"tms_sequence_rng",model.rng,m.rng);
            b.check(m.pitch_count==model.pitch_count && m.pitch_zero==model.pitch_zero,"tms_sequence_pitch_count",model.pitch_count+512*model.pitch_zero,m.pitch_count+512*m.pitch_zero);
            b.check(m.old_silence==model.old_e && m.old_unvoiced==model.old_p && m.inhibit==model.inhibit && m.zero_all==model.zpar && m.zero_high==model.uvzero,"tms_sequence_flags",model.old_e+2*model.old_p+4*model.inhibit+8*model.zpar+16*model.uvzero,m.old_silence+2*m.old_unvoiced+4*m.inhibit+8*m.zero_all+16*m.zero_high);
            b.check(m.chirp_address==std::min(model.pitch_count,51u) && m.table_shift==tmc0281_reference::interpolation[model.ip] && m.table_energy==0 && m.table_pitch==0 && signed_value(m.table_coefficient,10)==-501,"tms_sequence_rom",std::min(model.pitch_count,51u),m.chirp_address);
        };
        m.reset=1;m.clear=m.start=m.slow=m.sample_tick=m.frame_valid=0;
        m.frame_energy_index=m.frame_pitch_index=m.frame_energy=m.frame_pitch=m.frame_unvoiced_mask=0;pack(model.target_k);b.tick();m.reset=0;compare();
        unsigned logical=0,frames=0;
        auto tick_sample=[&](const SequenceFrame& f,unsigned delay){
            bool due=model.frame_due();m.sample_tick=1;b.tick();m.sample_tick=0;
            if(due){
                b.check(m.frame_req && m.frame_ready && !m.parameter_valid && m.busy,"tms_sequence_frame_request",1,m.frame_req);
                compare();for(unsigned n=0;n<delay;++n){b.tick();compare();b.check(!m.parameter_valid && m.busy && !m.frame_req,"tms_sequence_frame_wait",1,m.busy);}
                // Model conversion uses retained raw indices, without executing a sample yet.
                SequenceModel target=model;target.frame(f);
                m.frame_energy_index=target.raw_e;m.frame_pitch_index=target.raw_p;m.frame_energy=target.target_e;
                m.frame_pitch=target.target_p;m.frame_unvoiced_mask=target.uvzero;pack(target.target_k);
                m.frame_valid=1;b.tick();m.frame_valid=0;model.step(&f);++frames;
            }else model.step(nullptr);
            b.check(m.parameter_valid && !m.busy && m.active_sample==model.active,"tms_sequence_valid",model.active,m.active_sample);
            b.check(signed_value(m.excitation,8)==model.excitation,"tms_sequence_excitation",model.excitation,signed_value(m.excitation,8));compare();
            b.tick();b.check(!m.parameter_valid && !m.frame_req,"tms_sequence_pulse",0,m.parameter_valid);compare();++logical;return due;
        };
        SequenceFrame continuous{9,23,0,{31,17,15,8,13,12,11,7,6,5}};
        std::vector<SequenceFrame> script={continuous,{7,31,1,{}},{12,0,0,{3,4,5,6,0,0,0,0,0,0}},{5,0,1,{}},{0,0,0,{}},{7,29,1,{}},{14,13,0,{4,29,9,12,7,14,3,1,6,4}},{15,0,0,{}}};
        for(unsigned slow=0;slow<2;++slow)for(unsigned phase:{0u,1u,11u,75u,199u}){
            m.clear=1;b.tick();m.clear=0;model=SequenceModel{};logical=frames=0;compare();
            for(unsigned n=0;n<phase;++n)tick_sample(continuous,0);
            unsigned ip=model.ip,pc=model.pc,sub=model.sub;
            m.slow=slow;m.start=1;b.tick();m.start=0;model.speak(slow);compare();
            b.check(model.ip==ip && model.pc==pc && model.sub==sub,"tms_sequence_speak_phase",ip*100+pc,model.ip*100+model.pc);
            unsigned last_frame=0,stop_step=0;
            for(unsigned n=0;n<5000 && (frames<script.size() || model.status());++n){
                auto f=script[std::min(size_t(frames),script.size()-1)];bool due=tick_sample(f,(frames*7)%19);
                if(due){if(frames>1)b.check(logical-last_frame==(slow?304u:200u),"tms_sequence_frame_cadence",slow?304:200,logical-last_frame);last_frame=logical;if(f.e==15)stop_step=logical;}
            }
            b.check(frames==script.size() && !m.talk_status && stop_step>0,"tms_sequence_stop",script.size(),frames);
            b.check(logical-stop_step==(slow?266u:175u),"tms_sequence_drain",slow?266:175,logical-stop_step);
            unsigned rng=model.rng,pcount=model.pitch_count;for(unsigned n=0;n<500;++n)tick_sample(continuous,0);
            b.check(model.rng==rng && model.pitch_count==pcount,"tms_sequence_idle_hold",rng,model.rng);
            m.frame_valid=1;b.tick();m.frame_valid=0;compare();b.check(!m.parameter_valid,"tms_sequence_unsolicited",0,m.parameter_valid);
        }
        // Retain the busy-deadline diagnostic, then cancel a pending frame.
        m.clear=1;b.tick();m.clear=0;model=SequenceModel{};frames=logical=0;
        m.start=1;m.slow=0;b.tick();m.start=0;model.speak(false);
        for(unsigned n=0;n<1000 && !model.frame_due();++n)tick_sample(continuous,0);
        b.check(model.frame_due(),"tms_sequence_cancel_fixture",1,model.frame_due());
        m.sample_tick=1;b.tick();m.sample_tick=0;compare();b.check(m.busy,"tms_sequence_pending",1,m.busy);
        m.sample_tick=1;b.tick();m.sample_tick=0;b.check(m.protocol_error && m.busy,"tms_sequence_deadline",1,m.protocol_error);compare();
        m.reset=1;b.tick();m.reset=0;model=SequenceModel{};compare();m.frame_valid=1;b.tick();m.frame_valid=0;compare();
        b.check(!m.protocol_error && !m.busy && !m.parameter_valid,"tms_sequence_cancel",0,m.busy);
        // Independently diagnose SPEAK during a pending decoded-frame response.
        m.start=1;b.tick();m.start=0;model.speak(false);
        for(unsigned n=0;n<1000 && !model.frame_due();++n)tick_sample(continuous,0);
        m.sample_tick=1;b.tick();m.sample_tick=0;
        b.check(m.busy && !m.protocol_error,"tms_sequence_overlap_fixture",1,m.busy);
        m.start=1;b.tick();m.start=0;model.speak(false);compare();
        b.check(m.busy && m.protocol_error,"tms_sequence_speak_overlap",1,m.protocol_error);
        m.clear=1;b.tick();m.clear=0;model=SequenceModel{};compare();
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
