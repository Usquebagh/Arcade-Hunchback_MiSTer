// SPDX-License-Identifier: BSD-3-Clause
// Real engine/serial memory, independent field transcript and wide PCM model.
#include "Vcvs_tms5100_engine_rom_tb.h"
#include "common.hpp"
#include "tms5100_engine_model.hpp"
#include <vector>
struct EngineFilterModel {
    std::array<int64_t,10> x{};unsigned previous_energy=0;
    static int64_t wrap(int64_t v,unsigned bits){int64_t m=int64_t(1)<<bits,l=((v%m)+m)%m;return l>=m/2?l-m:l;}
    static int64_t divide(int64_t v,int64_t d){return v>=0?v/d:-((-v+d-1)/d);}
    static int64_t matrix(int64_t a,int64_t b){return divide(wrap(a,10)*wrap(b,15),512);}
    int pcm(const SequenceModel& s){
        std::array<int64_t,11> u{};u[10]=matrix(previous_energy,s.excitation*64);
        for(int n=9;n>=0;--n)u[n]=u[n+1]-matrix(s.k[n],x[n]);
        for(int n=9;n>0;--n)x[n]=x[n-1]+matrix(s.k[n-1],u[n-1]);
        x[0]=u[0];previous_energy=s.e;int64_t raw=wrap(u[0],15),q=divide(std::clamp(raw,int64_t(-2048),int64_t(2047)),16)*16;
        return int(q*16+((q&0x7f0)/8)+((q&0x400)/1024));
    }
};
int main(int argc,char** argv) {
    setup(argc,argv);Bench<Vcvs_tms5100_engine_rom_tb> b(argc,argv);auto& m=b.rtl;
    try {
        std::vector<SequenceFrame> frames={
            {9,23,0,{31,17,15,8,13,12,11,7,6,5}},{7,31,1,{}},
            {12,0,0,{3,4,5,6,0,0,0,0,0,0}},{5,0,1,{}},{0,0,0,{}},
            {7,29,1,{}},{14,13,0,{4,29,9,12,7,14,3,1,6,4}},{15,0,0,{}}};
        std::vector<unsigned> stream,lengths;
        for(const auto& f:frames){
            unsigned before=stream.size();auto field=[&](unsigned value,unsigned width){for(unsigned n=width;n>0;--n)stream.push_back((value>>(n-1))&1);};
            field(f.e,4);if(f.e && f.e!=15){field(f.rep,1);field(f.p,5);if(!f.rep)for(unsigned i=0;i<(f.p?10u:4u);++i)field(f.indices[i],tmc0281_reference::widths[i]);}
            lengths.push_back(stream.size()-before);
        }
        std::array<unsigned,4096> rom{};
        auto place=[&](unsigned bit_start,unsigned first){for(unsigned n=first;n<stream.size();++n){unsigned a=(bit_start+n-first)%32768;rom[a/8]=(rom[a/8]&~(1u<<(a%8)))+(stream[n]<<(a%8));}};
        for(unsigned n=0;n<4096;++n)rom[n]=(n*53+91)%256;
        place(32760,0);place(0x200,6);
        SequenceModel model;EngineFilterModel filter;
        unsigned pointer=0,consumed=0,decoded=0,last_decoded=0,samples=0,parameter_events=0;
        bool monitor_frames=false,in_talk_output=false;
        auto master=[&](){
            m.serial_enable=(b.cycle%7)>=2;m.clk=0;m.eval();
            bool accepted=m.bit_req && m.bit_ready;
            unsigned index=pointer%32768,bit=(rom[index/8]>>(index%8))&1;
            bool write=m.cpu_req && m.cpu_ready;
            if(write && (m.cpu_address==0x1d00 || m.cpu_address==0x1d40))b.check(!accepted,"tms_engine_pointer_priority",0,accepted);
            b.tick();
            if(write){if(m.cpu_address==0x1d00)pointer=((pointer&0xf800)+unsigned(m.cpu_data)*8)%65536;else if(m.cpu_address==0x1d40)pointer=((pointer%2048)+unsigned(m.cpu_data)*2048)%65536;}
            if(accepted){pointer=index+1;++consumed;b.check(m.bit_valid && m.bit_data==bit,"tms_engine_serial",bit,m.bit_data);}
            b.check(m.bit_address==pointer,"tms_engine_pointer",pointer,m.bit_address);
            b.check(!m.protocol_error,"tms_engine_protocol",0,m.protocol_error);
            if(m.parameter_valid)++parameter_events;
            if(m.sample_valid)++samples;
            if(m.decoded_frame && monitor_frames){
                b.check(decoded<frames.size(),"tms_engine_frame_count",frames.size(),decoded);
                b.check(consumed-last_decoded==lengths[decoded],"tms_engine_frame_bits",lengths[decoded],consumed-last_decoded);last_decoded=consumed;
                SequenceModel target=model;target.frame(frames[decoded]);uint64_t want=0;for(unsigned i=0;i<10;++i)want+=uint64_t(target.raw_k[i])<<(5*i);
                b.check(m.energy_index==target.raw_e && m.pitch_index==target.raw_p && m.coefficient_indices==want,"tms_engine_frame_fields",want,m.coefficient_indices);++decoded;
            }
        };
        auto pointer_write=[&](unsigned addr,unsigned value){m.cpu_req=1;m.cpu_address=addr;m.cpu_data=value;master();m.cpu_req=0;};
        auto pulse=[&](unsigned ctl){m.ctl=ctl;m.pdc=0;master();m.pdc=1;master();m.pdc=0;master();for(unsigned n=0;n<20;++n)master();};
        auto check_parameters=[&](){
            b.check(m.interpolation_period==model.ip && m.parameter_counter==model.pc && m.subcycle==model.sub,"tms_engine_phase",model.ip*100+model.pc*3+model.sub,m.interpolation_period*100+m.parameter_counter*3+m.subcycle);
            b.check(m.parameter_energy==model.e && m.parameter_pitch==model.p,"tms_engine_parameters",model.e*256+model.p,m.parameter_energy*256+m.parameter_pitch);
            for(unsigned i=0;i<10;++i){unsigned pos=i*10,v=m.parameter_coefficients[pos/32]>>(pos%32);if(pos%32>22)v|=m.parameter_coefficients[pos/32+1]<<(32-pos%32);int got=int(EngineFilterModel::wrap(v&1023,10));b.check(got==model.k[i],"tms_engine_k",model.k[i],got);}
            b.check(m.rng==model.rng && m.pitch_count==model.pitch_count,"tms_engine_excitation_state",model.rng,m.rng);
            b.check(m.talk_status==model.status(),"tms_engine_talk",model.status(),m.talk_status);
            if(in_talk_output)b.check(m.ctl_output && m.ctl_read==model.status(),"tms_engine_ctl_status",model.status(),m.ctl_read);
        };
        m.reset=1;m.sample_tick=m.pdc=m.cpu_req=m.data_dl_wr=0;m.cpu_ready=1;m.ctl=m.cpu_address=m.cpu_data=0;m.serial_enable=1;b.tick();
        for(unsigned slow=0;slow<2;++slow){
            m.reset=1;b.tick();model=SequenceModel{};filter=EngineFilterModel{};pointer=consumed=decoded=last_decoded=samples=parameter_events=0;monitor_frames=in_talk_output=false;
            for(unsigned n=0;n<4096;++n){m.data_dl_wr=1;m.data_dl_addr=n;m.dl_data=rom[n];master();}m.data_dl_wr=0;m.reset=0;
            pointer_write(0x1d00,255);pointer_write(0x1d40,15);
            for(unsigned n=0;n<4;++n)pulse(8);
            b.check(consumed==4,"tms_engine_control_reads",4,consumed);
            pulse(4);b.check(!m.ctl_output && m.ctl_read==4,"tms_engine_buffer_arm",4,m.ctl_read);
            pulse(4);b.check(m.ctl_output && m.ctl_read==9,"tms_engine_buffer_data",9,m.ctl_read);
            pulse(4);pulse(0);b.check(m.bit_address==32764 && !m.talk_status,"tms_engine_reset_keeps_pointer",32764,m.bit_address);
            pointer_write(0x1d00,255);pointer_write(0x1d40,15);consumed=last_decoded=0;monitor_frames=true;
            pulse(slow?6:10);model.speak(slow);check_parameters();
            b.check(!m.ctl_output && m.ctl_read==(slow?6:10),"tms_engine_status_input",slow?6:10,m.ctl_read);
            pulse(14);b.check(!m.ctl_output && m.ctl_read==14,"tms_engine_talk_arm",14,m.ctl_read);
            pulse(14);in_talk_output=true;check_parameters();
            unsigned logical=0,frame_index=0,last_frame=0,stop_step=0;bool relocated=false;
            for(unsigned n=0;n<5000 && (frame_index<frames.size() || model.status());++n){
                uint64_t due_cycle=b.cycle;bool due=model.frame_due();unsigned before_samples=samples,before_parameters=parameter_events;
                m.sample_tick=1;master();m.sample_tick=0;
                for(unsigned wait=0;wait<400 && samples==before_samples;++wait){
                    if(!slow && !relocated && consumed==6){m.clk=0;m.eval();if(m.bit_req){pointer_write(0x1d40,0);pointer_write(0x1d00,0x40);relocated=true;}}
                    master();
                }
                b.check(samples==before_samples+1 && parameter_events==before_parameters+1,"tms_engine_sample_completion",before_samples+1,samples);
                const SequenceFrame* f=due?&frames[frame_index]:nullptr;model.step(f);int expected=model.active?filter.pcm(model):-1;
                b.check(int(EngineFilterModel::wrap(m.pcm,16))==expected,"tms_engine_pcm",expected,EngineFilterModel::wrap(m.pcm,16));check_parameters();++logical;
                if(due){++frame_index;b.check(decoded==frame_index,"tms_engine_decoded_order",frame_index,decoded);if(frame_index>1)b.check(logical-last_frame==(slow?304u:200u),"tms_engine_frame_cadence",slow?304:200,logical-last_frame);last_frame=logical;if(f->e==15)stop_step=logical;}
                while(b.cycle<due_cycle+512){master();b.check(samples==before_samples+1 && !m.sample_valid,"tms_engine_sample_hold",before_samples+1,samples);}
            }
            b.check(frame_index==frames.size() && decoded==frames.size() && consumed==stream.size() && !m.talk_status,"tms_engine_stop",frames.size(),frame_index);
            b.check(logical-stop_step==(slow?266u:175u),"tms_engine_drain",slow?266:175,logical-stop_step);
            b.check(slow || relocated,"tms_engine_relocated",1,relocated);
            pulse(14);in_talk_output=false;b.check(!m.ctl_output && m.ctl_read==14,"tms_engine_talk_return",14,m.ctl_read);
            unsigned saved_pointer=pointer;pulse(0);model=SequenceModel{};filter=EngineFilterModel{};check_parameters();
            b.check(pointer==saved_pointer && !m.talk_status && m.pcm==0,"tms_engine_soft_reset",saved_pointer,pointer);
        }
        // Cancel a frame after the real ROM has issued a response. Software
        // RESET clears engine work without resetting the CPU-owned pointer.
        monitor_frames=false;in_talk_output=false;
        pointer_write(0x1d00,255);pointer_write(0x1d40,15);consumed=0;
        pulse(10);model.speak(false);
        for(unsigned n=0;n<1000 && !model.frame_due();++n){
            unsigned before=samples;m.sample_tick=1;master();m.sample_tick=0;
            for(unsigned wait=0;wait<100 && samples==before;++wait)master();
            b.check(samples==before+1,"tms_engine_cancel_sample",before+1,samples);
            model.step(nullptr);filter.pcm(model);check_parameters();
            for(unsigned idle=0;idle<40;++idle)master();
        }
        b.check(model.frame_due(),"tms_engine_cancel_fixture",1,model.frame_due());
        unsigned before_abort=samples;m.sample_tick=1;master();m.sample_tick=0;
        for(unsigned wait=0;wait<30 && consumed==0;++wait)master();
        b.check(consumed>0 && m.bit_valid,"tms_engine_cancel_response",1,m.bit_valid);
        pulse(0);model=SequenceModel{};filter=EngineFilterModel{};check_parameters();
        b.check(samples==before_abort && pointer>32760 && pointer<32768 && m.pcm==0 && m.coefficient_indices==0,"tms_engine_cancel_no_sample",before_abort,samples);
        unsigned saved=pointer,expected_next=(rom[(pointer%32768)/8]>>((pointer%32768)%8))&1;
        pulse(8);b.check(pointer==saved+1,"tms_engine_cancel_owner",saved+1,pointer);
        pulse(4);pulse(4);b.check(m.ctl_output && m.ctl_read==expected_next*8,"tms_engine_cancel_buffer",expected_next*8,m.ctl_read);
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
