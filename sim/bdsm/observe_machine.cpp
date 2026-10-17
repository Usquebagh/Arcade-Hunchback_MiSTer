// SPDX-License-Identifier: BSD-3-Clause
// Long actual-machine diagnostic. No post-initialization game/video oracle.
#ifdef AUDIO_OBSERVE
#include "Vcvs_full_machine.h"
using Machine=Vcvs_full_machine;
#else
#include "Vcvs_hps_coin_machine.h"
using Machine=Vcvs_hps_coin_machine;
#endif
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <set>
#include <string>
#include <vector>

int main(int argc,char** argv) {
    if(argc!=7)return 2;
    uint64_t limit=std::stoull(argv[1]);
    unsigned seed=std::stoul(argv[2]),resume_pc=std::stoul(argv[3]);
    bool controls=std::stoul(argv[4])!=0,credit_test=std::stoul(argv[5])!=0;
#ifdef AUDIO_OBSERVE
    bool require_audio_activity=std::stoul(argv[6])!=0;
    std::set<int> mixed_audio_levels;
    int mixed_audio_min=32767,mixed_audio_max=-32768;
    uint64_t nonzero_audio_samples=0;
#else
    (void)argv[6];
#endif
    VerilatedContext context;context.randReset(2);context.randSeed(seed);
    Machine m(&context);
    std::ifstream image("image.bin",std::ios::binary),expected("startup.expect");
    std::vector<unsigned char> bytes((std::istreambuf_iterator<char>(image)),{});
    std::vector<uint32_t> want;std::string line;
    while(std::getline(expected,line))want.push_back(std::stoul(line,nullptr,16));
    if(bytes.size()!=51232 || want.empty())return 2;
    uint64_t cycle=0,frames=0,irqs=0,writes=0,stores=0,pixels=0;
    bool initialized=false,last_ack=false;
    unsigned field_pixels=0,coin_samples=0,start_samples=0,input_reads=0,right_samples=0,jump_samples=0;
    std::array<unsigned char,244*248*3> field{};
    std::array<unsigned char,1024> system_ram{},ram_before_coin{};
    std::array<bool,1024> system_ram_valid{},ram_before_coin_valid{};
    bool ram_coin_snapshot=false,ram_coin_delta_reported=false;
    std::ofstream bus("bus.log"),captures("captures.log");
#ifdef AUDIO_OBSERVE
    std::ofstream audio_bus("audio-bus.log"),audio_events("audio-events.log");
    std::ofstream audio_samples("audio-samples.log"),audio_output_samples("audio-output-samples.log");
    uint64_t audio_acks=0,audio_reads=0,audio_writes=0,dac8_writes=0,dac4_writes=0,discrete_writes=0,command_events=0;
    uint64_t audio_sample_origin=0;
    bool last_audio_ack=false;
    m.audio_ready=1;m.audio_sense=0;m.speech_ready=1;m.speech_sense=0;
#endif
    auto fail=[&](const char* label,uint64_t expected_value,uint64_t observed_value) {
        std::cout<<"BDSM {\"status\":\"FAIL\",\"label\":\""<<label<<"\",\"cycle\":"<<cycle
                 <<",\"expected\":"<<expected_value<<",\"observed\":"<<observed_value<<"}"<<std::endl;
        std::exit(1);
    };
    m.clk=0;m.reset=1;m.reset_na=0;m.video_reset=1;m.scan_run=0;m.ready=1;m.dl_wr=0;
    m.in2=m.in3=255;
    // Pinned MAME's Hunchback switch defaults: DSW2=0C, DSW3=0F.
    // Raw compatibility bytes, not a physical switch/input wiring audit.
    m.dsw1=0x0c;m.dsw2=0x0f;
    auto tick=[&]() {
        bool coin=controls && frames>=170 && frames<172;
        bool start=controls && !credit_test && frames>=178 && frames<180;
        bool right=controls && !credit_test && frames>=300 && frames<330;
        bool jump=controls && !credit_test && frames>=306 && frames<309;
#ifdef AUDIO_OBSERVE
        // Audio-only observer retains its isolated audio wrapper.
        m.in0=255-(coin?8:0)-(start?1:0)-(jump?32:0);
        m.in1=255-(right?16:0);
#else
        // MRA button list slots map consecutively: Jump=4, Start2=5,
        // Start1=6, Coin=7. The defaults choose physical gamepad buttons.
        // This drives the same HDL mapper used by emu; no CVS port is forced.
        m.joystick_0=(coin?1u<<7:0)|(start?1u<<6:0)|(jump?1u<<4:0)|
                     ((!credit_test && controls && frames>=178 && frames<180)?1u<<6:0)|
                     (right?1u<<3:0);
        m.joystick_1=0;
#endif
#ifdef AUDIO_OBSERVE
        // Nominal external RC fixture only, not a physical audio clock model.
        m.audio_sense=((cycle*760ull/57272724ull)&1u);
        m.speech_sense=m.audio_sense;
#endif
        m.clk=0;m.eval();
#ifdef AUDIO_OBSERVE
        bool audio_command_read=!m.reset && m.audio_req && m.audio_ready &&
            m.audio_memory_space && !m.audio_wr && m.audio_address==0x1800;
        if(!m.reset && m.audio_req && m.audio_ready && m.audio_wr) {
            ++audio_writes;
            audio_bus<<cycle<<" W "<<std::hex<<unsigned(m.audio_address)<<" "<<unsigned(m.audio_write_data)<<std::dec
                     <<" "<<unsigned(m.audio_memory_space)<<"\n";
        }
#endif
        bool resume=false;
        bool io_read=false;
        unsigned io_address=0;
        if(!m.reset && m.req && m.ready) {
            if(!m.memory_space && !m.wr && m.extended) {
                ++input_reads;
                if((m.address&15)==0) {if(coin)++coin_samples;if(start)++start_samples;if(jump)++jump_samples;}
                if((m.address&15)==2 && right)++right_samples;
                io_read=true;io_address=m.address;
            }
            if(m.wr) {
                if(m.memory_space && (m.address&0x1c00u)==0x1c00u) {
                    unsigned ram_address=m.address&0x03ffu;
                    system_ram[ram_address]=m.write_data;
                    system_ram_valid[ram_address]=true;
                }
                uint32_t header=m.memory_space?4u:((m.extended<<1)|m.data_port);
                uint32_t record=(header<<24)|(m.address<<9)|(m.flag<<8)|m.write_data;
                if(!initialized) {
                    if(stores>=want.size())fail("observe_startup_extra",want.size(),stores+1);
                    if(record!=want[stores])fail("observe_startup_write",want[stores],record);
                    ++stores;
                }
                ++writes;
                bus<<cycle<<" W "<<std::hex<<unsigned(m.address)<<" "<<unsigned(m.write_data)<<std::dec
                   <<" "<<unsigned(m.memory_space)<<" "<<unsigned(m.flag)<<" "<<unsigned(m.extended)<<" "<<unsigned(m.data_port)<<"\n";
            } else if(!initialized && m.memory_space && m.phase==0 && m.address==resume_pc && stores==want.size())resume=true;
        }
        m.clk=1;m.eval();++cycle;
#ifdef AUDIO_OBSERVE
        if(m.reset)last_audio_ack=false;
        else {
            if(m.audio_trigger) {
                ++command_events;audio_events<<cycle<<" COMMAND "<<unsigned(m.audio_command)<<"\n";
            }
            if(m.audio_intack && !last_audio_ack) {
                ++audio_acks;audio_events<<cycle<<" ACK\n";
            }
            last_audio_ack=m.audio_intack;
            if(audio_command_read) {
                ++audio_reads;
                audio_bus<<cycle-1<<" R 1800 "<<std::hex<<unsigned(m.audio_read_data)<<std::dec<<"\n";
            }
            if(m.dac8_wr) {++dac8_writes;audio_events<<cycle<<" DAC8 "<<unsigned(m.dac8)<<"\n";}
            if(m.dac4_wr) {++dac4_writes;audio_events<<cycle<<" DAC4 "<<unsigned(m.dac4)<<"\n";}
            if(m.discrete_wr) {++discrete_writes;audio_events<<cycle<<" DISCRETE "<<unsigned(m.discrete)<<"\n";}
            if(m.sample_ce) {
                // Match the engineering top-level audio path: routed byte DAC,
                // schematic-weighted discrete network and independent speech.
                int mixed=int(int16_t(m.speech_pcm))+int(int16_t(m.discrete_pcm));
                if(mixed>32767)mixed=32767;
                if(mixed< -32768)mixed=-32768;
                mixed_audio_levels.insert(mixed);
                if(mixed<mixed_audio_min)mixed_audio_min=mixed;
                if(mixed>mixed_audio_max)mixed_audio_max=mixed;
                if(mixed!=0)++nonzero_audio_samples;
                audio_samples<<cycle<<" "<<int(int16_t(m.pcm8))<<" "<<int(int16_t(m.pcm4))<<" "<<int(int16_t(m.discrete_pcm))<<"\n";
                audio_output_samples<<cycle<<" "<<mixed<<"\n";
            }
        }
#endif
        if(m.reset)last_ack=false;
        else {
            if(m.intack && !last_ack)++irqs;
            last_ack=m.intack;
        }
        if(io_read)bus<<cycle-1<<" R "<<std::hex<<io_address<<" "<<unsigned(m.read_data)<<std::dec<<"\n";
        if(resume) {
            // Scan stayed paused and the independently modeled call inhibited
            // interrupts. Diagnostic accounting must exclude reset pin values.
            if(irqs!=0)fail("observe_reset_irq_count",0,irqs);
            initialized=true;m.scan_run=1;
            std::cout<<"Initialization checkpoint: cycle="<<cycle<<", writes="<<stores<<std::endl;
        }
        if(initialized && m.pixel_valid) {
            unsigned x=m.out_x,y=m.out_y;
            if(x==0 && y==8) {
                if(frames && field_pixels!=244*248)fail("observe_field_count",244*248,field_pixels);
                ++frames;field_pixels=0;
                if(frames==170) {
                    ram_before_coin=system_ram;
                    ram_before_coin_valid=system_ram_valid;
                    ram_coin_snapshot=true;
                }
                if(frames==178 && ram_coin_snapshot && !ram_coin_delta_reported) {
                    unsigned before=ram_before_coin[0x70],after=system_ram[0x70];
                    if(credit_test) {
                        if(!coin_samples)fail("hps_coin_port_sampled",1,0);
                        if(!ram_before_coin_valid[0x70] || !system_ram_valid[0x70])
                            fail("credit_ram_write_observed",1,0);
                        if(before!=0 || after!=1)fail("coin_increments_credit_ram",1,after);
                        std::cout<<"BDSM {\"status\":\"PASS\",\"label\":\"hps_coin_to_credit_ram\",\"input\":\"joystick_0[7]\",\"port\":\"IN0[3]\",\"address\":\"0x1c70\",\"before\":"<<before<<",\"after\":"<<after<<"}"<<std::endl;
                    }
                    for(unsigned address=0;address<system_ram.size();++address) {
                        if(ram_before_coin_valid[address] && system_ram_valid[address] &&
                           ram_before_coin[address]!=system_ram[address])
                            std::cout<<"RAMDELTA {\"coin_enabled\":"<<(controls?"true":"false")
                                     <<",\"frame\":178,\"address\":\"0x"<<std::hex
                                     <<(0x1c00u+address)<<"\",\"before\":"<<unsigned(ram_before_coin[address])
                                     <<",\"after\":"<<unsigned(system_ram[address])<<std::dec<<"}"<<std::endl;
                    }
                    ram_coin_delta_reported=true;
                }
                if(frames%16==0)std::cout<<"Observed frame "<<frames<<", IRQ acknowledgements="<<irqs<<std::endl;
            }
            unsigned expected_x=field_pixels%244;
            if(x!=expected_x || y!=8+field_pixels/244)fail("observe_pixel_order",expected_x+256*(8+field_pixels/244),x+256*y);
            unsigned offset=field_pixels*3;
            field[offset]=m.red;field[offset+1]=m.green;field[offset+2]=m.blue;
            ++field_pixels;++pixels;
            if(field_pixels==244*248 && frames>=128 && (frames%16==0 || frames==156 || frames==172 || frames==180 || frames==196)) {
                std::string name="frame-"+std::to_string(frames)+".ppm";
                std::ofstream out(name,std::ios::binary);out<<"P6\n244 248\n255\n";
                out.write(reinterpret_cast<const char*>(field.data()),field.size());
                if(!out)std::exit(2);
                captures<<frames<<" "<<cycle<<" "<<name<<"\n";
            }
        }
    };
    tick();
    for(unsigned n=0;n<bytes.size();++n) {m.dl_wr=1;m.dl_addr=n;m.dl_data=bytes[n];tick();}
    m.dl_wr=0;m.reset_na=1;m.video_reset=0;for(unsigned n=0;n<4;++n)tick();m.reset=0;
#ifdef AUDIO_OBSERVE
    audio_sample_origin=cycle;
#endif
    while(cycle<limit)tick();
#ifdef AUDIO_OBSERVE
    if(require_audio_activity && (mixed_audio_levels.size()<2 || mixed_audio_min==mixed_audio_max || !nonzero_audio_samples))
        fail("attract_audio_output_varies",2,mixed_audio_levels.size());
#endif
    if(!initialized)fail("observe_startup_missing",want.size(),stores);
    std::cout<<"OBSERVED {\"cycles\":"<<cycle<<",\"frames_started\":"<<frames<<",\"irq_acknowledgements\":"<<irqs
             <<",\"pixels\":"<<pixels<<",\"writes\":"<<writes<<",\"initialization_writes\":"<<stores
             <<",\"last_bus_address\":"<<m.address<<",\"input_reads\":"<<input_reads
             <<",\"coin_read_samples\":"<<coin_samples<<",\"start_read_samples\":"<<start_samples
             <<",\"right_read_samples\":"<<right_samples<<",\"jump_read_samples\":"<<jump_samples;
#ifdef AUDIO_OBSERVE
    std::cout<<",\"audio_irq_acknowledgements\":"<<audio_acks<<",\"audio_command_events\":"<<command_events
             <<",\"audio_command_reads\":"<<audio_reads<<",\"audio_writes\":"<<audio_writes
             <<",\"dac8_writes\":"<<dac8_writes<<",\"dac4_writes\":"<<dac4_writes
             <<",\"discrete_writes\":"<<discrete_writes<<",\"audio_sample_origin\":"<<audio_sample_origin
             <<",\"mixed_audio_min\":"<<mixed_audio_min<<",\"mixed_audio_max\":"<<mixed_audio_max
             <<",\"mixed_audio_unique_levels\":"<<mixed_audio_levels.size()
             <<",\"nonzero_audio_samples\":"<<nonzero_audio_samples;
#endif
    std::cout<<"}"<<std::endl;
    m.final();return 0;
}
