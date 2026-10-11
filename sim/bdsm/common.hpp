// SPDX-License-Identifier: MIT
// From MiSTer-BDSM at 5c8988540c3a1c50cec9ccb06fc3f923e959b61a.
#pragma once
#include <verilated.h>
#include <verilated_vcd_c.h>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <cstdint>

struct Failure : std::runtime_error { using std::runtime_error::runtime_error; };
template<class Model> struct Bench {
    Model rtl;
    uint64_t cycle=0, trace_start=UINT64_MAX;
    std::unique_ptr<VerilatedVcdC> trace;
    Bench(int argc,char** argv) {
        for(int n=1;n+1<argc;++n) if(std::string(argv[n])=="--trace-start") trace_start=std::stoull(argv[n+1]);
        if(trace_start!=UINT64_MAX) {trace=std::make_unique<VerilatedVcdC>();rtl.trace(trace.get(),2);trace->open("failure.vcd");}
    }
    ~Bench(){if(trace)trace->close();rtl.final();}
    void tick(){rtl.clk=0;rtl.eval();dump(0);rtl.clk=1;rtl.eval();dump(1);++cycle;}
    void dump(unsigned edge){if(trace && cycle>=trace_start && cycle<trace_start+2048)trace->dump(cycle*20+edge*10);}
    void check(bool condition,const char* label,int64_t expected,int64_t observed){
        if(!condition){std::cout<<"BDSM {\"status\":\"FAIL\",\"label\":\""<<label<<"\",\"cycle\":"<<cycle
            <<",\"expected\":"<<expected<<",\"observed\":"<<observed<<"}\n";throw Failure(label);}
    }
    void pass(){std::cout<<"BDSM {\"status\":\"PASS\",\"cycle\":"<<cycle<<",\"observed\":\"all directed assertions satisfied\"}\n";}
};
inline void setup(int argc,char** argv){Verilated::commandArgs(argc,argv);Verilated::traceEverOn(true);}
