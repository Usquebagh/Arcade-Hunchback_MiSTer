// SPDX-License-Identifier: BSD-3-Clause
// Directed command transcripts, arithmetic nibble oracle and hostile handshakes.
#include "Vcvs_tms5100_control.h"
#include "common.hpp"
int main(int argc,char** argv) {
    setup(argc,argv);Bench<Vcvs_tms5100_control> b(argc,argv);auto& m=b.rtl;
    try {
        m.reset=1;m.pdc=0;m.ctl=0;m.talk_status=0;
        m.bit_ready=0;m.bit_valid=0;m.bit_data=0;b.tick();m.reset=0;
        auto idle_pulses=[&]() {b.check(!m.start && !m.datapath_reset && !m.address_load && !m.branch,"tms_pulse_hold",0,m.start+2*m.datapath_reset+4*m.address_load+8*m.branch);};
        auto command=[&](unsigned ctl) {
            m.ctl=ctl;m.pdc=0;b.tick();idle_pulses();
            m.pdc=1;b.tick();idle_pulses();
            m.pdc=0;b.tick();
        };
        auto input=[&](unsigned value,const char* label) {
            m.ctl=value;m.eval();b.check(!m.ctl_output && m.ctl_read==value,label,value,m.ctl_read);
        };
        auto bit=[&](unsigned value,unsigned stalls) {
            b.check(m.busy && m.bit_req,"tms_request",1,m.bit_req);
            for(unsigned n=0;n<stalls;++n){b.tick();b.check(m.bit_req && m.busy,"tms_request_retained",1,m.bit_req);idle_pulses();}
            m.bit_ready=1;b.tick();m.bit_ready=0;
            b.check(!m.bit_req && m.busy,"tms_single_request",0,m.bit_req);
            for(unsigned n=0;n<7;++n){b.tick();b.check(!m.bit_req && m.busy,"tms_wait_response",0,m.bit_req);idle_pulses();}
            m.bit_valid=1;m.bit_data=value;b.tick();m.bit_valid=0;
            b.check(!m.busy && !m.bit_req,"tms_complete",0,m.busy);
        };
        // Every CTL1 combination; rising edges and held low never decode.
        for(unsigned ignored=0;ignored<2;++ignored) {
            m.talk_status=0;
            command(10+ignored);b.check(m.start && !m.slow,"tms_falling_command",1,m.start);
            input(0,"tms_status_input");b.tick();idle_pulses();
            command(6+ignored);b.check(m.start && m.slow,"tms_slow",1,m.slow);
            command(14+ignored);input(5,"tms_talk_arm");
            command(0);b.check(m.ctl_output && m.ctl_read==0 && !m.datapath_reset,"tms_talk_direction",1,m.ctl_output+2*m.ctl_read+32*m.datapath_reset);
            m.talk_status=1;m.eval();b.check(m.ctl_read==1,"tms_talk_status",1,m.ctl_read);
            m.ctl=15;m.eval();b.check(m.ctl_read==1,"tms_output_isolation",1,m.ctl_read);
            command(0);input(0,"tms_talk_return");b.check(!m.datapath_reset,"tms_direction_consumes_edge",0,m.datapath_reset);
            m.talk_status=1;input(0,"tms_status_not_busy");
            command(0+ignored);b.check(m.datapath_reset && !m.bit_req,"tms_no_reset_dummy",1,m.datapath_reset);
        }
        unsigned expected=0;
        for(unsigned value:{1u,0u,1u,1u,0u,0u,1u,0u}) {
            command(8+value);bit(value,11);expected=expected/2+value*8;
            command(4+value);input(3,"tms_buffer_arm");
            command(10);b.check(m.ctl_output && m.ctl_read==expected && !m.start,"tms_buffer_shift",expected,m.ctl_read);
            command(10);input(10,"tms_buffer_return");b.check(!m.start,"tms_direction_consumes_edge",0,m.start);
        }
        // All sixteen four-bit transcripts, with independent arithmetic shifts.
        for(unsigned pattern=0;pattern<16;++pattern) {
            command(0);expected=0;
            for(unsigned n=0;n<4;++n){unsigned value=(pattern>>n)&1;command(8+(n%2));bit(value,n);expected=expected/2+value*8;}
            command(4+(pattern%2));command(0);
            b.check(m.ctl_read==expected,"tms_buffer_all_values",expected,m.ctl_read);command(0);
        }
        // All address nibbles including values that resemble other commands.
        for(unsigned nibble=0;nibble<16;++nibble) {
            command(2+(nibble%2));command(nibble);
            b.check(m.address_load && m.address_nibble==nibble && !m.start && !m.branch,"tms_address_capture",nibble,m.address_nibble);
            command(8);bit(nibble%2,3);
            command(4);command(0);b.check(m.ctl_read==expected,"tms_dummy_no_shift",expected,m.ctl_read);command(0);
        }
        for(unsigned code:{10u,6u,0u}) {
            command(2);command(15);command(code);idle_pulses();bit(1,13);
            b.check(code==0 ? m.datapath_reset && !m.start : m.start && !m.datapath_reset && m.slow==(code==6),"tms_dummy_before_action",1,m.start+2*m.datapath_reset);
        }
        command(2);command(9);command(12);b.check(m.branch,"tms_branch",1,m.branch);
        command(13);b.check(m.branch,"tms_branch_ctl1",1,m.branch);
        command(10);b.check(m.start && !m.bit_req,"tms_branch_cancels_dummy",1,m.start);
        // Unsolicited responses cannot alter the buffer or start a datapath.
        command(0);expected=0;m.bit_valid=1;m.bit_data=1;b.tick();idle_pulses();m.bit_valid=0;
        command(4);command(0);b.check(m.ctl_read==0,"tms_unsolicited_response",0,m.ctl_read);command(0);
        // Busy command rejection preserves the outstanding serial transaction.
        command(8);command(10);b.check(m.protocol_error && m.busy && m.bit_req && !m.start,"tms_busy_reject",1,m.protocol_error);
        bit(1,5);command(4);command(0);b.check(m.ctl_read==8,"tms_busy_preserves_work",8,m.ctl_read);command(0);
        // Reset while requesting, while awaiting and in either output direction.
        for(unsigned phase=0;phase<4;++phase) {
            if(phase<2){command(8);if(phase==1){m.bit_ready=1;b.tick();m.bit_ready=0;}}
            else {command(phase==2?4:14);command(0);}
            m.reset=1;m.ctl=0;m.pdc=1;b.tick();
            b.check(!m.busy && !m.bit_req && !m.ctl_output && !m.protocol_error && !m.slow,"tms_reset",0,m.busy);idle_pulses();
            m.reset=0;m.pdc=0;m.bit_valid=1;b.tick();m.bit_valid=0;idle_pulses();
            input(7,"tms_reset_input");
        }
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
