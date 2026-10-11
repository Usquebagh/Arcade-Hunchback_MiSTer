// SPDX-License-Identifier: BSD-3-Clause
// Independent coordinate/glyph/palette model, not HDL pipeline state.
#include "Vcvs_character_tb.h"
#include "common.hpp"
#include <array>
#include <deque>
#include <fstream>
struct Pixel {unsigned x,y,raw,pen,bullet,bg,events,r,g,b;bool capture;};
struct Pending {uint64_t due;Pixel pixel;};
int main(int argc,char** argv){
    setup(argc,argv);Bench<Vcvs_character_tb> b(argc,argv);
    try{
        std::array<unsigned,1024> codes{},attrs{};
        std::array<unsigned,256> bullets{};
        std::array<unsigned,16> palette{};
        std::array<std::array<unsigned,2048>,3> rom{};
        std::array<std::array<unsigned,1024>,3> ram{};
        std::array<unsigned,2048> prom{};
        std::deque<Pending> queue;
        unsigned collision=0, held_rgb=0;
        std::array<unsigned,7> held_payload{};
        bool initialized_hold=false;
        std::ofstream observed("synthetic-character-frame.log"),expected("expected-character-frame.log");
        observed<<"P3\n256 256\n255\n";expected<<"P3\n256 256\n255\n";
        b.rtl.reset=1;b.rtl.pixel_ce=0;b.rtl.cpu_wr=0;b.rtl.cpu_rd=0;b.rtl.dl_wr=0;
        b.rtl.collision_clear=0;b.rtl.visible=1;b.rtl.char_mode=0;b.rtl.scroll=0;b.rtl.sprites=0;
        auto oracle=[&](unsigned x,unsigned y,unsigned mode,unsigned scroll,unsigned sprites,bool visible,bool capture){
            unsigned source_y=(y+256-((x/32>=1 && x/32<=5)?scroll:0))%256;
            unsigned tile=(source_y/8)*32+x/8,code=codes[tile],attr=attrs[tile];
            static constexpr unsigned starts[]={224,192,256,128};
            unsigned raw=0;
            for(unsigned plane=0;plane<3;++plane){
                unsigned data=code<starts[mode]?rom[plane][code*8+source_y%8]:ram[plane][(code-128)*8+source_y%8];
                raw=raw*2+((data/(1u<<(7-x%8)))%2);
            }
            unsigned collision_mask=(attr&128)?6:((attr%4)==3)?4:((attr%2)==0)?2:0;
            bool bg=(raw&collision_mask)!=0;
            bool bullet=false;
            if(y>=8 && bullets[y])for(int n=0;n<4;++n)if(int(x)==248-int(bullets[y])-n)bullet=true;
            unsigned mapped=prom[raw*256+attr],pen=((mapped&1)*4)+(mapped&2)+((mapped&4)/4);
            if(bullet)pen=7;
            std::array<bool,3> present{};
            unsigned mixed=0;
            for(unsigned chip=0;chip<3;++chip){unsigned nibble=(sprites>>(chip*4))&15;present[chip]=nibble>=8;mixed|=nibble%8;}
            if(present[0] || present[1] || present[2])pen=8+mixed;
            unsigned events=0;
            static constexpr unsigned pairs[][3]={{0,1,0},{1,2,1},{0,2,2}};
            for(auto& pair:pairs)if(present[pair[0]] && present[pair[1]])events+=1u<<pair[2];
            if(bullet && (present[0] || present[1] || present[2]))events+=8;
            for(unsigned chip=0;chip<3;++chip)if(present[chip] && bg)events+=16u<<chip;
            if(bullet && bg)events+=128;
            unsigned active=255-palette[pen],r=(active%4)*85,g=(active/4)%8,blue=active/32;
            g=g*32+g*4+g/2;blue=blue*32+blue*4+blue/2;
            return Pixel{x,y,raw,pen,unsigned(bullet && visible),unsigned(bg && visible),visible?events:0,visible?r:0,visible?g:0,visible?blue:0,capture};
        };
        auto tick=[&](bool capture=false){
            if(b.rtl.reset){queue.clear();collision=0;initialized_hold=false;}
            else if(b.rtl.pixel_ce)queue.push_back({b.cycle+5,oracle(b.rtl.pixel_x,b.rtl.pixel_y,b.rtl.char_mode,b.rtl.scroll,b.rtl.sprites,b.rtl.visible,capture)});
            bool clear=b.rtl.collision_clear;b.tick();
            bool valid=!queue.empty() && queue.front().due==b.cycle;
            b.check(bool(b.rtl.pixel_valid)==valid,"character_latency",valid,b.rtl.pixel_valid);
            if(b.rtl.reset){b.check(b.rtl.collision==0 && b.rtl.red==0 && b.rtl.green==0 && b.rtl.blue==0,"character_reset",0,b.rtl.collision);return;}
            if(clear)collision=0;
            if(valid){
                auto p=queue.front().pixel;queue.pop_front();
                b.check(b.rtl.out_x==p.x && b.rtl.out_y==p.y,"character_coordinates",p.x+256*p.y,b.rtl.out_x+256*b.rtl.out_y);
                b.check(b.rtl.raw_pixel==p.raw,"character_pixel",p.raw,b.rtl.raw_pixel);
                b.check(b.rtl.bullet_present==p.bullet,"character_bullet",p.bullet,b.rtl.bullet_present);
                b.check(b.rtl.background_collision==p.bg,"character_foreground",p.bg,b.rtl.background_collision);
                b.check(b.rtl.palette_index==p.pen,"character_palette_index",p.pen,b.rtl.palette_index);
                b.check(b.rtl.collision_events==p.events,"character_collision_events",p.events,b.rtl.collision_events);
                unsigned rgb=p.r+256*p.g+65536*p.b,got=b.rtl.red+256*b.rtl.green+65536*b.rtl.blue;
                b.check(got==rgb,"character_rgb",rgb,got);held_rgb=rgb;initialized_hold=true;
                held_payload={b.rtl.out_x,b.rtl.out_y,b.rtl.raw_pixel,b.rtl.palette_index,b.rtl.bullet_present,b.rtl.background_collision,b.rtl.collision_events};
                collision|=p.events;
                if(p.capture){observed<<unsigned(b.rtl.red)<<' '<<unsigned(b.rtl.green)<<' '<<unsigned(b.rtl.blue)<<'\n';expected<<p.r<<' '<<p.g<<' '<<p.b<<'\n';}
            }else if(initialized_hold){
                b.check(b.rtl.red+256*b.rtl.green+65536*b.rtl.blue==held_rgb,"character_hold",held_rgb,b.rtl.red+256*b.rtl.green+65536*b.rtl.blue);
                std::array<unsigned,7> got={b.rtl.out_x,b.rtl.out_y,b.rtl.raw_pixel,b.rtl.palette_index,b.rtl.bullet_present,b.rtl.background_collision,b.rtl.collision_events};
                b.check(got==held_payload,"character_payload_hold",held_payload[0],got[0]);
            }
            b.check(b.rtl.collision==collision,"character_collision_latch",collision,b.rtl.collision);
        };
        auto poke=[&](unsigned addr,unsigned flag,unsigned page,unsigned data){b.rtl.cpu_addr=addr;b.rtl.cpu_flag=flag;b.rtl.char_page=page;b.rtl.cpu_din=data;b.rtl.cpu_wr=1;tick();b.rtl.cpu_wr=0;};
        tick();b.rtl.reset=0;
        for(unsigned a=0;a<1024;++a){
            codes[a]=(a*37+a/32*11)%256;attrs[a]=(a*19+a/16)%256;
            poke(0x1800+a,1,0,codes[a]);poke(0x1800+a,0,0,attrs[a]);
            for(unsigned p=0;p<3;++p){ram[p][a]=(a*29+(a/8)*11+p*83+0x53)%256;poke(0x1700-p*256+a%256,1,a/256,ram[p][a]);}
        }
        for(unsigned y=0;y<256;++y){bullets[y]=(y*53)%256;poke(0x1400+y,0,0,bullets[y]);}
        for(unsigned p=0;p<16;++p){palette[p]=(p*71+23)%256;poke(0x1400+p,1,0,palette[p]);}
        for(unsigned p=0;p<3;++p)for(unsigned a=0;a<2048;++a){rom[p][a]=(a*43+(a/8)*17+p*101+0x9b)%256;b.rtl.dl_wr=1;b.rtl.dl_addr=p*2048+a;b.rtl.dl_data=rom[p][a];tick();}
        for(unsigned a=0;a<2048;++a){prom[a]=((a*37)^((a/256)*13)^(a/8))%8;b.rtl.dl_addr=6144+a;b.rtl.dl_data=prom[a];tick();}
        b.rtl.dl_wr=0;
        auto drain=[&](){b.rtl.pixel_ce=0;for(int n=0;n<5;++n)tick();b.check(queue.empty(),"character_fixture_drained",0,queue.size());};
        // Every byte/mode boundary appears in complete fields. Vary metadata
        // on back-to-back clocks, with independent holes and visible blanking.
        for(unsigned frame=0;frame<5;++frame){
            b.rtl.char_mode=frame%4;b.rtl.scroll=frame==0?7:frame==1?193:frame==2?255:frame==3?1:0;
            for(unsigned y=0;y<256;++y)for(unsigned x=0;x<256;++x){
                if(frame && ((x+y*3)%17)==0){b.rtl.pixel_ce=0;tick();}
                b.rtl.pixel_ce=1;b.rtl.pixel_x=x;b.rtl.pixel_y=y;
                b.rtl.visible=frame!=4 || ((x+y)%11)!=0;
                b.rtl.sprites=frame==0?0:((x*29+y*17)&4095);
                b.rtl.collision_clear=(x%41)==0;tick(frame==0);
            }
            drain();
        }
        // Exhaust all 256 attributes x 8 raw pixels x 8 presence masks using
        // initialized RAM glyphs, with mapped colour independent of foreground.
        b.rtl.char_mode=3;b.rtl.scroll=0;b.rtl.pixel_x=0;b.rtl.pixel_y=8;b.rtl.visible=1;
        codes[32]=128;poke(0x1820,1,0,128);
        for(unsigned attr=0;attr<256;++attr){attrs[32]=attr;poke(0x1820,0,0,attr);
            for(unsigned raw=0;raw<8;++raw){
                for(unsigned p=0;p<3;++p){ram[p][0]=(raw&(4>>p))?128:0;poke(0x1700-p*256,1,0,ram[p][0]);}
                for(unsigned mask=0;mask<8;++mask){b.rtl.sprites=((mask&1)?8:0)+((mask&2)?128:0)+((mask&4)?2048:0);b.rtl.pixel_ce=1;b.rtl.collision_clear=1;tick();drain();}
            }
        }
        // All palette bytes; black sprite presence forces palette 8.
        for(unsigned value=0;value<256;++value){palette[8]=value;poke(0x1408,1,0,value);b.rtl.sprites=8;b.rtl.pixel_ce=1;tick();drain();}
        // Every bullet position byte against every x, including negative clips.
        b.rtl.sprites=0;
        for(unsigned value=0;value<256;++value){bullets[8]=value;poke(0x1408,0,0,value);
            for(unsigned x=0;x<256;++x){b.rtl.pixel_x=x;b.rtl.pixel_ce=1;tick();}drain();
        }
        // Exhaust all packed presence/colour combinations and their OR priority.
        b.rtl.pixel_x=0;
        for(unsigned sprites=0;sprites<4096;++sprites){b.rtl.sprites=sprites;b.rtl.pixel_ce=1;tick();}drain();
        // Reset mid-pipeline flushes requests, retains all initialized memories.
        for(unsigned source=0;source<2;++source){
            codes[32]=source?32:128;poke(0x1820,1,0,codes[32]);
            for(unsigned depth=0;depth<5;++depth){b.rtl.pixel_ce=1;tick();b.rtl.pixel_ce=0;for(unsigned n=0;n<depth;++n)tick();b.rtl.reset=1;tick();b.rtl.reset=0;drain();b.rtl.pixel_ce=1;tick();drain();}
        }
        observed.close();expected.close();b.pass();return 0;
    }catch(const Failure&){return 1;}
}
