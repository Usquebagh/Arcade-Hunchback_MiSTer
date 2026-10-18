// SPDX-License-Identifier: BSD-3-Clause
#include "Vcvs_sound_bench.h"
#include "verilated.h"
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr double master_hz = 57272724.0;
struct Command { uint64_t edge; unsigned byte; };
void little(std::ostream& out, uint32_t value, unsigned bytes) {
    for (unsigned i=0; i<bytes; ++i) out.put(char(value >> (8*i)));
}
class Wav {
    std::ofstream out;
    uint32_t samples=0;
public:
    explicit Wav(const std::string& path):out(path,std::ios::binary) {
        out.exceptions(std::ios::badbit | std::ios::failbit);
        out.write("RIFF",4);little(out,0,4);out.write("WAVEfmt ",8);
        little(out,16,4);little(out,1,2);little(out,1,2);little(out,48000,4);
        little(out,96000,4);little(out,2,2);little(out,16,2);
        out.write("data",4);little(out,0,4);
    }
    void put(uint16_t value) {little(out,value,2);++samples;}
    void finish() {
        out.seekp(4);little(out,36+samples*2,4);
        out.seekp(40);little(out,samples*2,4);out.close();
    }
};
}

// Arguments are prepared by sound_bench.py; the timeline here uses integer edges.
int main(int argc, char** argv) {
    try {
        if(argc<7) throw std::runtime_error("image timeline output edges reset_edges release_ps [Verilator plusargs]");
        VerilatedContext context;
        context.commandArgs(argc,argv);
        // --x-initial unique consults randReset; seed alone does not enable it.
#ifdef SOUND_X_RANDOM
        context.randReset(2);
#endif
        auto model=std::make_unique<Vcvs_sound_bench>(&context);
        auto& m=*model;
        const uint64_t edges=std::stoull(argv[4]), reset_edges=std::stoull(argv[5]);
        const unsigned release_ps=std::stoul(argv[6]);
        const std::string output=argv[3];
        std::ifstream input(argv[1],std::ios::binary);
        input.exceptions(std::ios::badbit | std::ios::failbit);
        input.seekg(0x8000);
        std::vector<unsigned char> rom(4096);
        input.read(reinterpret_cast<char*>(rom.data()),rom.size());
        std::ifstream timeline(argv[2]);
        if(!timeline) throw std::runtime_error("Cannot read prepared timeline");
        std::vector<Command> commands;
        Command c{};
        while(timeline>>c.edge>>c.byte) commands.push_back(c);
        if(!timeline.eof()) throw std::runtime_error("Malformed prepared timeline");
        std::ofstream dac(output+"/dac-events.csv"), irq(output+"/irq-events.csv");
        dac.exceptions(std::ios::badbit | std::ios::failbit);
        irq.exceptions(std::ios::badbit | std::ios::failbit);
        dac<<"seconds,audio_cpu_cycle,address,value\n"<<std::fixed<<std::setprecision(9);
        irq<<"seconds,command,trigger,irq,intack,ii\n"<<std::fixed<<std::setprecision(9);
        Wav mix(output+"/mix.wav"), wav8(output+"/dac8.wav"), wav4(output+"/dac4.wav");
        m.clk=0;m.core_reset=1;m.dl_wr=0;
        m.dl_addr=0;m.dl_data=0;m.command_wr=0;m.command_data=0;m.eval();
        auto tick=[&]() {
            m.clk=0;m.eval();context.timeInc(8729);
            m.clk=1;m.eval();context.timeInc(8730);
        };
        // Download only through the real 0x8000..0x8fff mapping, under reset.
        for(unsigned i=0;i<rom.size();++i) {
            m.dl_wr=1;m.dl_addr=0x8000+i;m.dl_data=rom[i];tick();
        }
        m.dl_wr=0;
        for(uint64_t i=0;i<reset_edges;++i) tick();
        m.clk=0;m.eval();context.timeInc(release_ps);
        m.core_reset=0;m.eval();
        uint64_t cycles=0, event_count=0, first_ce=0, reads=0;
        size_t next=0;
        unsigned last_irq=~0u;
        auto record_irq=[&](uint64_t edge) {
            unsigned state=(m.command<<4)|(m.trigger<<3)|(m.irq<<2)|(m.intack<<1)|m.ii;
            if(state!=last_irq) {
                irq<<double(edge)/master_hz<<",0x"<<std::hex<<std::setw(2)<<std::setfill('0')
                   <<unsigned(m.command)<<std::dec<<','<<unsigned(m.trigger)<<','<<unsigned(m.irq)
                   <<','<<unsigned(m.intack)<<','<<unsigned(m.ii)<<'\n';
                last_irq=state;
            }
        };
        record_irq(0);
        // Edge zero is the first active master edge, at t=0 after release.
        // Count/time samples by completed active edges, independent of host time.
        for(uint64_t edge=0;edge<edges;++edge) {
            if(edge && edge % 57272724==0) std::cout<<"Simulated "<<edge/57272724<<" seconds\n"<<std::flush;
            m.clk=0;
            m.command_wr=next<commands.size() && commands[next].edge==edge;
            if(m.command_wr) m.command_data=commands[next++].byte;
            m.eval();
            if(m.audio_ce) {++cycles;if(!first_ce) first_ce=edge;}
            if(m.req && !m.wr) ++reads;
            // Capture the accepted transfer BEFORE the CPU changes address/data.
            if(m.req && m.wr && m.memory_space &&
                (m.address==0x1840 || (m.address>=0x1880 && m.address<=0x1887))) {
                dac<<double(edge)/master_hz<<','<<cycles<<",0x"<<std::hex<<std::setw(4)
                   <<std::setfill('0')<<unsigned(m.address)<<",0x"<<std::setw(2)
                   <<unsigned(m.write_data)<<std::dec<<'\n';
                ++event_count;
            }
            // Shell/output logic consumes the pre-edge sample_ce and PCM values.
            if(m.sample_ce) {mix.put(m.audio_pcm);wav8.put(m.pcm8);wav4.put(m.pcm4);}
            context.timeInc(edge==0 ? 8729-release_ps : 8729);
            m.clk=1;m.eval();context.timeInc(8730);
            record_irq(edge);
        }
        // Flush the last generated raw-sample strobe at the duration boundary.
        if(m.sample_ce) {mix.put(m.audio_pcm);wav8.put(m.pcm8);wav4.put(m.pcm4);}
        m.final();mix.finish();wav8.finish();wav4.finish();
        std::ofstream stats(output+"/run-stats.json");
        stats<<"{\"audio_cpu_cycles\":"<<cycles<<",\"dac_events\":"<<event_count
             <<",\"first_audio_ce_edge\":"<<first_ce<<",\"read_transfers\":"<<reads
             <<",\"final_address\":"<<unsigned(m.address)<<"}\n";
        std::cout<<"Completed "<<edges<<" edges, "<<cycles<<" audio CE pulses, "<<event_count<<" DAC events\n";
        return 0;
    } catch(const std::exception& exc) {std::cerr<<exc.what()<<'\n';return 2;}
}
