// SPDX-License-Identifier: BSD-3-Clause
#include "Vcvs_main_memory.h"
#include "common.hpp"
static unsigned byte(unsigned a,unsigned salt){return (a*73+(a/256)*19+salt*37)&255;}
int main(int argc,char** argv){
    setup(argc,argv);Bench<Vcvs_main_memory> b(argc,argv);
    try{
        b.rtl.dl_wr=0;b.rtl.cpu_rd=0;b.rtl.cpu_wr=0;b.rtl.sprite_din=0xff;
        b.rtl.video_tile_rd=0;b.rtl.video_glyph_rd=0;b.rtl.video_palette_rd=0;
        auto write=[&](unsigned addr,unsigned flag,unsigned page,unsigned data){
            b.rtl.cpu_addr=addr;b.rtl.cpu_flag=flag;b.rtl.char_page=page;b.rtl.cpu_din=data;
            b.rtl.cpu_wr=1;b.tick();b.rtl.cpu_wr=0;
        };
        for(unsigned a=0;a<1024;++a){
            write(0x1800+a,1,0,byte(a,0));write(0x1800+a,0,0,byte(a,1));
            for(unsigned plane=0;plane<3;++plane)write(0x1700-plane*256+(a%256),1,a/256,byte(a,plane+2));
        }
        for(unsigned a=0;a<256;++a)write(0x1400+a,0,0,byte(a,5));
        for(unsigned a=0;a<16;++a)write(0x1400+a,1,0,byte(a,6));
        // Independently address every word, all planes/pages, palette aliases
        // and unrelated CPU addresses/FLAG: display must not use CPU bank state.
        for(unsigned a=0;a<1024;++a){
            b.rtl.cpu_addr=(a*17)&0x7fff;b.rtl.cpu_flag=a&1;b.rtl.char_page=(a+1)%4;
            b.rtl.video_tile_rd=1;b.rtl.video_tile_addr=a;b.rtl.video_bullet_addr=a%256;
            b.rtl.video_glyph_rd=1;b.rtl.video_glyph_addr=a;b.rtl.video_palette_rd=1;b.rtl.video_palette_addr=a%16;b.tick();
            b.check(b.rtl.video_code==byte(a,0),"display_code",byte(a,0),b.rtl.video_code);
            b.check(b.rtl.video_attr==byte(a,1),"display_attribute",byte(a,1),b.rtl.video_attr);
            b.check(b.rtl.video_bullet==byte(a%256,5),"display_bullet",byte(a%256,5),b.rtl.video_bullet);
            unsigned want=byte(a,2)|(byte(a,3)<<8)|(byte(a,4)<<16);
            b.check(b.rtl.video_glyph==want,"display_glyph",want,b.rtl.video_glyph);
            b.check(b.rtl.video_palette==byte(a%16,6),"display_palette",byte(a%16,6),b.rtl.video_palette);
        }
        // Every shared-RAM write collision must forward exactly one new byte.
        b.rtl.video_tile_addr=0x231;b.rtl.video_bullet_addr=0x31;b.rtl.video_glyph_addr=0x231;b.rtl.video_palette_addr=1;
        for(unsigned n=0;n<7;++n){
            unsigned addr=n<2?0x1a31:n<5?0x1731-(n-2)*256:0x1431;
            unsigned flag=n!=1 && n!=5;
            write(addr,flag,2,0xb0+n);
            unsigned got=n==0?b.rtl.video_code:n==1?b.rtl.video_attr:n<5?(b.rtl.video_glyph>>(8*(n-2)))&255:n==5?b.rtl.video_bullet:b.rtl.video_palette;
            b.check(got==0xb0+n,"display_forward",0xb0+n,got);
        }
        unsigned held[]={b.rtl.video_code,b.rtl.video_attr,b.rtl.video_bullet,b.rtl.video_glyph,b.rtl.video_palette};
        b.rtl.video_tile_rd=0;b.rtl.video_glyph_rd=0;b.rtl.video_palette_rd=0;
        b.rtl.video_tile_addr=0;b.rtl.video_bullet_addr=0;b.rtl.video_glyph_addr=0;b.rtl.video_palette_addr=0;
        for(unsigned a=0;a<16;++a){write(0x1800+a,1,0,a);b.check(b.rtl.video_code==held[0] && b.rtl.video_attr==held[1] && b.rtl.video_bullet==held[2] && b.rtl.video_glyph==held[3] && b.rtl.video_palette==held[4],"display_hold",held[0],b.rtl.video_code);}
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
