#include "Vcvs_main_memory.h"
#include "common.hpp"
static unsigned pattern(unsigned a,unsigned flag,unsigned page=0){return (a*29+(a>>8)*17+flag*83+page*47)&255;}
int main(int argc,char** argv){
    setup(argc,argv);Bench<Vcvs_main_memory> b(argc,argv);
    try{
        b.rtl.video_tile_rd=0;b.rtl.video_tile_addr=0;b.rtl.video_bullet_addr=0;
        b.rtl.video_glyph_rd=0;b.rtl.video_glyph_addr=0;b.rtl.video_palette_rd=0;b.rtl.video_palette_addr=0;
        b.rtl.dl_wr=0;b.rtl.cpu_rd=0;b.rtl.cpu_wr=0;b.rtl.cpu_flag=0;b.rtl.char_page=0;b.rtl.sprite_din=0xe7;
        auto access=[&](unsigned addr,unsigned flag,unsigned page,unsigned data,bool write){
            b.rtl.cpu_addr=addr;b.rtl.cpu_flag=flag;b.rtl.char_page=page;b.rtl.cpu_din=data;
            b.rtl.cpu_wr=write;b.rtl.cpu_rd=1;b.tick();return unsigned(b.rtl.cpu_dout);
        };
        // Write each independent CPU RAM view before reads; unspecified power-up
        // state is never used as expected data.
        for(unsigned f=0;f<2;++f)for(unsigned a=0x1400;a<0x1c00;++a){
            if(!f && a>=0x1500 && a<0x1800)continue;
            if(f && a>=0x1500 && a<0x1800){
                for(unsigned p=0;p<4;++p)access(a,f,p,pattern(a,f,p),true);
            }else if(!(f && a>=0x1410 && a<0x1500))access(a,f,0,pattern(a,f),true);
        }
        for(unsigned mirror=0;mirror<4;++mirror)for(unsigned f=0;f<2;++f)
            for(unsigned a=0x1400;a<0x1c00;++a){
                if(!f && a>=0x1500 && a<0x1800){
                    unsigned got=access((mirror<<13)|a,f,0,0,false),sel=4u>>((a>>8)-0x15);
                    b.check(got==0xe7,"sprite_read_byte",0xe7,got);
                    b.check(b.rtl.sprite_select==sel,"sprite_select",sel,b.rtl.sprite_select);
                    b.check(b.rtl.sprite_rd && !b.rtl.sprite_wr,"sprite_read_strobe",1,b.rtl.sprite_rd);
                    b.check(b.rtl.sprite_addr==(a&255),"sprite_address",a&255,b.rtl.sprite_addr);
                }else{
                    unsigned pages=(f && a>=0x1500 && a<0x1800)?4:1;
                    for(unsigned p=0;p<pages;++p){
                        unsigned logical=(f && a<0x1500)?(0x1400|(a&15)):a;
                        unsigned got=access((mirror<<13)|a,f,p,0,false),want=pattern(logical,f,p);
                        b.check(got==want,"banked_byte",want,got);
                        b.check(b.rtl.sprite_select==0,"flag_isolation",0,b.rtl.sprite_select);
                    }
                }
            }
        for(unsigned unit=0;unit<3;++unit){
            access(0x1500+(unit<<8)+0x53,0,0,0x9b,true);
            b.check(b.rtl.sprite_select==(4u>>unit),"sprite_write_select",4u>>unit,b.rtl.sprite_select);
            b.check(b.rtl.sprite_wr && b.rtl.sprite_dout==0x9b,"sprite_write_data",0x9b,b.rtl.sprite_dout);
        }
        b.rtl.cpu_wr=0;b.rtl.cpu_rd=0;b.rtl.eval();
        b.check(b.rtl.sprite_select==0 && !b.rtl.sprite_wr && !b.rtl.sprite_rd,"sprite_idle",0,b.rtl.sprite_select);
        // A response must survive changing to another window before the next read.
        unsigned held=access(0x1800,1,0,0,false);
        b.rtl.cpu_addr=0;b.rtl.cpu_flag=0;b.rtl.cpu_rd=0;b.rtl.clk=0;b.rtl.eval();
        b.check(b.rtl.cpu_dout==held,"response_hold",held,b.rtl.cpu_dout);
        b.tick();b.check(b.rtl.cpu_dout==held,"response_hold_clock",held,b.rtl.cpu_dout);
        b.rtl.dl_wr=1;b.rtl.dl_addr=0;b.rtl.dl_data=0x5d;b.tick();b.rtl.dl_wr=0;
        unsigned got=access(0,0,0,0,false);b.check(got==0x5d,"fixed_rom_route",0x5d,got);
        access(0x1c31,0,0,0x82,true);got=access(0x7c31,1,3,0,false);
        b.check(got==0x82,"system_ram_route",0x82,got);
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
