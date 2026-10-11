// SPDX-License-Identifier: BSD-3-Clause
// Long actual-machine diagnostic. No post-initialization game/video oracle.
#include "Vcvs_machine.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

int main(int argc,char** argv) {
    if(argc!=5)return 2;
    uint64_t limit=std::stoull(argv[1]);
    unsigned seed=std::stoul(argv[2]),resume_pc=std::stoul(argv[3]);
    bool controls=std::stoul(argv[4])!=0;
    VerilatedContext context;context.randReset(2);context.randSeed(seed);
    Vcvs_machine m(&context);
    std::ifstream image("image.bin",std::ios::binary),expected("startup.expect");
    std::vector<unsigned char> bytes((std::istreambuf_iterator<char>(image)),{});
    std::vector<uint32_t> want;std::string line;
    while(std::getline(expected,line))want.push_back(std::stoul(line,nullptr,16));
    if(bytes.size()!=51232 || want.empty())return 2;
    uint64_t cycle=0,frames=0,irqs=0,writes=0,stores=0,pixels=0;
    bool initialized=false,last_ack=false;
    unsigned field_pixels=0,coin_samples=0,start_samples=0,input_reads=0,right_samples=0,jump_samples=0;
    std::array<unsigned char,227*256*3> field{};
    std::ofstream bus("bus.log"),captures("captures.log");
    auto fail=[&](const char* label,uint64_t expected_value,uint64_t observed_value) {
        std::cout<<"BDSM {\"status\":\"FAIL\",\"label\":\""<<label<<"\",\"cycle\":"<<cycle
                 <<",\"expected\":"<<expected_value<<",\"observed\":"<<observed_value<<"}"<<std::endl;
        std::exit(1);
    };
    m.clk=0;m.reset=1;m.reset_na=0;m.video_reset=1;m.scan_run=0;m.ready=1;m.dl_wr=0;
    m.in0=m.in1=m.in2=m.in3=255;
    // Pinned MAME's Hunchback switch defaults: DSW2=0C, DSW3=0F.
    // Raw compatibility bytes, not a physical switch/input wiring audit.
    m.dsw1=0x0c;m.dsw2=0x0f;
    auto tick=[&]() {
        bool coin=controls && frames>=170 && frames<172;
        bool start=controls && frames>=178 && frames<180;
        bool right=controls && frames>=300 && frames<330;
        bool jump=controls && frames>=306 && frames<309;
        m.in0=255-(coin?8:0)-(start?1:0)-(jump?32:0);
        m.in1=255-(right?16:0);
        m.clk=0;m.eval();
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
            if(x==0 && y==0) {
                if(frames && field_pixels!=227*256)fail("observe_field_count",227*256,field_pixels);
                ++frames;field_pixels=0;
                if(frames%16==0)std::cout<<"Observed frame "<<frames<<", IRQ acknowledgements="<<irqs<<std::endl;
            }
            if(x!=field_pixels%227 || y!=field_pixels/227)fail("observe_pixel_order",field_pixels,x+227*y);
            unsigned offset=field_pixels*3;
            field[offset]=m.red;field[offset+1]=m.green;field[offset+2]=m.blue;
            ++field_pixels;++pixels;
            if(field_pixels==227*256 && frames>=128 && (frames%16==0 || frames==156 || frames==172 || frames==180 || frames==196)) {
                std::string name="frame-"+std::to_string(frames)+".ppm";
                std::ofstream out(name,std::ios::binary);out<<"P6\n227 256\n255\n";
                out.write(reinterpret_cast<const char*>(field.data()),field.size());
                if(!out)std::exit(2);
                captures<<frames<<" "<<cycle<<" "<<name<<"\n";
            }
        }
    };
    tick();
    for(unsigned n=0;n<bytes.size();++n) {m.dl_wr=1;m.dl_addr=n;m.dl_data=bytes[n];tick();}
    m.dl_wr=0;m.reset_na=1;m.video_reset=0;for(unsigned n=0;n<4;++n)tick();m.reset=0;
    while(cycle<limit)tick();
    if(!initialized)fail("observe_startup_missing",want.size(),stores);
    std::cout<<"OBSERVED {\"cycles\":"<<cycle<<",\"frames_started\":"<<frames<<",\"irq_acknowledgements\":"<<irqs
             <<",\"pixels\":"<<pixels<<",\"writes\":"<<writes<<",\"initialization_writes\":"<<stores
             <<",\"last_bus_address\":"<<m.address<<",\"input_reads\":"<<input_reads
             <<",\"coin_read_samples\":"<<coin_samples<<",\"start_read_samples\":"<<start_samples
             <<",\"right_read_samples\":"<<right_samples<<",\"jump_read_samples\":"<<jump_samples<<"}"<<std::endl;
    m.final();return 0;
}
