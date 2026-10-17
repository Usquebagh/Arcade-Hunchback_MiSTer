#include "Vcvs_s2636_objects.h"
#include "common.hpp"
#include <array>
#include <fstream>
#include <vector>
struct Object {unsigned hc,hcb,vc,vcb,scale,colour;std::array<unsigned,10> shape;};
static const unsigned bases[4]={0,0x10,0x20,0x40};
static unsigned pair_flags(unsigned mask){
    const unsigned pairs[6][3]={{0,1,32},{0,2,16},{0,3,8},{1,2,4},{1,3,2},{2,3,1}};
    unsigned flags=0;
    for(auto &p:pairs)if((mask&(1u<<p[0])) && (mask&(1u<<p[1])))flags+=p[2];
    return flags;
}
// Independent geometric oracle: identify an analytic rectangle instance, then
// expand its pattern bit. No countdown/active/next-row engine is copied.
static unsigned reference(const std::array<Object,4>& objects,unsigned x,unsigned y,unsigned& colour){
    unsigned mask=0;colour=0;
    for(unsigned i=0;i<4;++i){
        auto &o=objects[i];unsigned magnification=1u<<o.scale,height=10*magnification;
        if(y<o.vc)continue;
        unsigned period=height+o.vcb+1,instance=(y-o.vc)/period,relative_y=(y-o.vc)%period;
        int left=int(instance?o.hcb:o.hc)-26;
        if(relative_y>=height || int(x)<left || int(x)>=left+int(8*magnification))continue;
        unsigned row=relative_y/magnification,column=unsigned(int(x)-left)/magnification;
        if(o.shape[row]&(128u>>column)){mask|=1u<<i;colour|=o.colour;}
    }
    return mask;
}
static void picture(const char* name,const std::vector<unsigned>& pixels){
    // A P3 synthetic pixel diagnostic in a .log allows the pinned runner to
    // retain it without exporting ROM/register data or changing the framework.
    std::ofstream out(name);out<<"P3\n244 256\n255\n";
    for(unsigned c:pixels)out<<((c&1)?255:0)<<' '<<((c&2)?255:0)<<' '<<((c&4)?255:0)<<'\n';
}
int main(int argc,char** argv){
    setup(argc,argv);Bench<Vcvs_s2636_objects> b(argc,argv);
    try{
        b.rtl.reset=1;b.rtl.cpu_rd=0;b.rtl.cpu_wr=0;b.rtl.cpu_addr=0;b.rtl.cpu_din=0;
        b.rtl.vrst=0;b.rtl.line_start=0;b.rtl.ce_pixel=0;b.rtl.pixel_x=0;b.rtl.intack=0;b.tick();
        b.rtl.reset=0;
        auto write=[&](unsigned a,unsigned d){b.rtl.cpu_addr=a;b.rtl.cpu_din=d;b.rtl.cpu_wr=1;b.tick();b.rtl.cpu_wr=0;};
        auto peek=[&](unsigned a){b.rtl.cpu_addr=a;b.rtl.eval();return unsigned(b.rtl.cpu_dout);};
        auto read=[&](unsigned a){unsigned d=peek(a);b.rtl.cpu_rd=1;b.tick();b.rtl.cpu_rd=0;return d;};
        auto clear_irq=[&](){b.rtl.intack=1;b.tick();b.rtl.intack=0;b.check(!b.rtl.irq,"object_irq_ack",0,b.rtl.irq);};
        auto field=[&](){
            b.rtl.ce_pixel=0;b.rtl.line_start=0;b.rtl.vrst=1;b.tick();
            b.check(peek(0xcb)&64,"vertical_leading_flag",64,peek(0xcb));
            b.check(b.rtl.irq,"vertical_irq",1,b.rtl.irq);
            unsigned got=read(0xfb);b.check(got&64,"status_alias",64,got);
            b.check(peek(0xcb)==0,"status_read_clear",0,peek(0xcb));
            b.check(b.rtl.irq,"read_is_not_ack",1,b.rtl.irq);
            clear_irq();b.rtl.vrst=0;b.tick();
            b.check(peek(0xca)==0 && peek(0xcb)==0,"vertical_trailing_clear",0,peek(0xcb));
        };
        auto configure=[&](const std::array<Object,4>& objects){
            b.rtl.vrst=1;b.rtl.ce_pixel=0;b.rtl.line_start=0;
            unsigned sizes=0;
            for(unsigned i=0;i<4;++i){
                auto &o=objects[i];unsigned a=bases[i];
                for(unsigned r=0;r<10;++r)write(a+r,o.shape[r]);
                write(a+10,o.hc);write(a+11,o.hcb);write(a+12,o.vc);write(a+13,o.vcb);
                sizes|=o.scale<<(2*i);
            }
            write(0xc0,sizes);write(0xc1,(objects[0].colour<<3)|objects[1].colour);
            write(0xc2,(objects[2].colour<<3)|objects[3].colour);
        };
        // All retained descriptor/scratch/background bytes are written first.
        for(unsigned a=0;a<=0xad;++a){
            bool stored=a<0x2e || (a>=0x40 && a<=0x6d) || a>=0x80;
            write(a,(a*37+19)&255);
            unsigned want=stored?((a*37+19)&255):255;
            b.check(peek(a)==want,"register_byte",want,peek(a));
        }
        for(unsigned offset:{0u,1u,2u,3u,6u,7u,8u,9u}){
            write(0xc0|offset,0x53+offset);
            unsigned previous_write=0x53+offset;
            for(unsigned mirror=0;mirror<4;++mirror){
                unsigned a=0xc0+16*mirror+offset;
                b.check(peek(a)==previous_write,"control_alias",previous_write,peek(a));
                write(a,0x65+offset+mirror);
                previous_write=0x65+offset+mirror;
                b.check(peek(0xc0|offset)==previous_write,"control_alias_write",previous_write,peek(0xc0|offset));
            }
        }
        write(0xca,255);write(0xdb,255);
        b.check(peek(0xca)==0 && peek(0xcb)==0,"readonly_status",0,peek(0xca));
        for(unsigned a:{0xc4u,0xc5u,0xccu,0xcdu,0xceu,0xcfu}){
            write(a,0x18);b.check(peek(a)==255,"unsupported_bus_value",255,peek(a));
        }
        std::array<Object,4> objects;
        auto scan=[&](bool export_image){
            configure(objects);field();
            std::vector<unsigned> observed(244*256),expected(244*256);
            for(unsigned y=0;y<256;++y){
                b.rtl.line_start=1;b.tick();b.rtl.line_start=0;
                unsigned completed=0;
                for(unsigned i=0;i<4;++i){
                    unsigned height=10u<<objects[i].scale,period=height+objects[i].vcb+1;
                    if(y>=objects[i].vc && (y-objects[i].vc)%period==height-1)completed|=8u>>i;
                }
                unsigned got=read(0xca+(y%4)*16);
                b.check(got==completed,"object_completion",completed,got);
                b.check(peek(0xca)==0,"completion_read_clear",0,peek(0xca));
                b.check(bool(b.rtl.irq)==bool(completed),"completion_irq",bool(completed),b.rtl.irq);
                clear_irq();unsigned collisions=0;
                for(unsigned x=0;x<244;++x){
                    unsigned colour=0,mask=reference(objects,x,y,colour);
                    b.rtl.ce_pixel=1;b.rtl.pixel_x=x;b.tick();
                    b.check(b.rtl.object_mask==mask,"object_pixel",mask,b.rtl.object_mask);
                    b.check(b.rtl.pixel_colour==colour,"object_colour",colour,b.rtl.pixel_colour);
                    b.check(bool(b.rtl.pixel_present)==bool(mask),"black_object_presence",bool(mask),b.rtl.pixel_present);
                    collisions|=pair_flags(mask);observed[y*244+x]=b.rtl.pixel_colour;expected[y*244+x]=colour;
                }
                b.rtl.ce_pixel=0;
                got=read(0xcb+(y%4)*16);b.check(got==collisions,"object_collision",collisions,got);
                b.check(peek(0xcb)==0,"collision_read_clear",0,peek(0xcb));
                unsigned held=b.rtl.object_mask;b.rtl.pixel_x=0;b.tick();
                b.check(b.rtl.object_mask==held,"pixel_hold",held,b.rtl.object_mask);
            }
            if(export_image){picture("synthetic-sprite-frame.log",observed);picture("expected-sprite-frame.log",expected);}
        };
        // One descriptor must produce one horizontal 8-pixel run per object
        // row. Keep this first so a coordinate-alias mutant fails this focused
        // assertion rather than a later generic geometry comparison.
        for(auto &o:objects){o={255,255,12,255,0,0,{}};o.shape.fill(0);}
        objects[0]={61,255,12,255,0,1,{}};objects[0].shape.fill(255);
        configure(objects);field();
        unsigned scanline_hits=0,total_hits=0;
        for(unsigned y=0;y<256;++y){
            b.rtl.line_start=1;b.tick();b.rtl.line_start=0;scanline_hits=0;
            for(unsigned x=0;x<244;++x){
                unsigned want=(y>=12 && y<22 && x>=35 && x<43)?1u:0u;
                b.rtl.ce_pixel=1;b.rtl.pixel_x=x;b.tick();
                b.check(b.rtl.object_mask==want,"single_object_horizontal_run",want,b.rtl.object_mask);
                scanline_hits+=b.rtl.object_mask;total_hits+=b.rtl.object_mask;
            }
            if(y>=12 && y<22)b.check(scanline_hits==8,"single_object_scanline_width",8,scanline_hits);
            else b.check(scanline_hits==0,"single_object_vertical_extent",0,scanline_hits);
            b.rtl.ce_pixel=0;
        }
        b.check(total_hits==80,"single_object_total_pixels",80,total_hits);
        // Every object at every scale, distinct pattern rows, primary/duplicates,
        // clipping, OR colour, and analytic repeated-start positions.
        for(unsigned variant=0;variant<4;++variant){
            for(unsigned i=0;i<4;++i){
                objects[i]={16+47*i,35+43*i,8+19*i,17+11*i,(i+variant)%4,(i==3?3u:1u<<i),{}};
                for(unsigned r=0;r<10;++r)objects[i].shape[r]=((0x81u>>(r%3))^(17u*r+7u*i))&255;
            }
            scan(variant==0);
        }
        // Shared colour bits prove wire-OR mixing, rather than addition/XOR.
        for(auto &o:objects){o={20,255,3,255,0,0,{}};o.shape.fill(255);}
        objects[0].colour=1;objects[1].colour=1;objects[2].colour=4;scan(false);
        // Six isolated pairs distinguish collision bit ordering; bounding boxes
        // alone cannot collide when shape is zero. Black pixels still count.
        for(unsigned first=0;first<4;++first)for(unsigned second=first+1;second<4;++second){
            for(unsigned i=0;i<4;++i){
                objects[i]={255,255,3,255,0,0,{}};objects[i].shape.fill(255);
            }
            objects[first].hc=20;objects[second].hc=20;scan(false);
            objects[first].shape.fill(0);scan(false);
        }
        // VC changes wait until next field; duplicate HCB is latched per line.
        for(auto &o:objects){o={255,255,4,255,0,1,{}};o.shape.fill(255);}
        objects[0]={31,52,4,0,0,1,{}};objects[0].shape.fill(255);
        configure(objects);field();write(0x0c,25);
        for(unsigned y=0;y<35;++y){
            // Capture gap=6 on primary's last line; a later write chooses gap=2
            // for subsequent duplicates, never changes the already latched gap.
            if(y==8)write(0x0d,5);
            b.rtl.line_start=1;b.tick();b.rtl.line_start=0;
            if(y==13)write(0x0d,1);
            if(y==20)write(0x0b,71); // after HRST: current duplicate still x=26
            for(unsigned x=0;x<100;++x){
                bool draw=(y>=4 && y<14)||(y>=20 && y<30)||(y>=32);
                unsigned left=y<20?5:(y==20?26:45),want=draw && x>=left && x<left+8 ? 1:0;
                b.rtl.ce_pixel=1;b.rtl.pixel_x=x;b.tick();
                b.check(b.rtl.object_mask==want,"latch_cadence",want,b.rtl.object_mask);
            }
            b.rtl.ce_pixel=0;
        }
        field();
        for(unsigned y=0;y<27;++y){
            b.rtl.line_start=1;b.tick();b.rtl.line_start=0;b.rtl.ce_pixel=1;b.rtl.pixel_x=10;b.tick();b.rtl.ce_pixel=0;
            unsigned want=y>=25?1:0;b.check(b.rtl.object_mask==want,"vertical_field_latch",want,b.rtl.object_mask);
        }
        // A new field must not retain any pixels from an object's previous
        // position. PVI output is streamed, not stored in a frame bitmap.
        for(auto &o:objects){o={255,255,20,255,0,0,{}};o.shape.fill(0);}
        objects[0].hc=12;objects[0].colour=1;objects[0].shape.fill(255);
        configure(objects);field();
        auto scan_position=[&](){
            for(unsigned y=0;y<256;++y){
                b.rtl.line_start=1;b.tick();b.rtl.line_start=0;
                for(unsigned x=0;x<244;++x){
                    unsigned colour=0,want=reference(objects,x,y,colour);
                    b.rtl.ce_pixel=1;b.rtl.pixel_x=x;b.tick();
                    b.check(b.rtl.object_mask==want,"field_sprite_position",want,b.rtl.object_mask);
                }
                b.rtl.ce_pixel=0;
            }
        };
        scan_position();
        objects[0].hc=90;
        configure(objects);field();scan_position();
        // Simultaneous read/event retains the new event, while the captured
        // read value is the preceding status. An event also wins IRQ ack.
        for(auto &o:objects){o={255,255,0,255,0,1,{}};o.shape.fill(255);}
        objects[0].hc=46;objects[1].hc=46;configure(objects);field();
        for(unsigned y=0;y<10;++y){
            b.rtl.line_start=1;
            if(y==9){
                b.check(peek(0xca)==0,"completion_preceding_read",0,peek(0xca));
                b.rtl.cpu_addr=0xca;b.rtl.cpu_rd=1;b.rtl.intack=1;
            }
            b.tick();b.rtl.line_start=0;b.rtl.cpu_rd=0;b.rtl.intack=0;
            if(y==9){
                b.check(peek(0xca)==15,"completion_event_retained",15,peek(0xca));
                b.check(b.rtl.irq,"completion_over_ack",1,b.rtl.irq);
            }
            if(y==0){
                b.rtl.cpu_addr=0xcb;b.rtl.cpu_rd=1;b.rtl.pixel_x=20;b.rtl.ce_pixel=1;b.tick();
                b.rtl.cpu_rd=0;b.rtl.ce_pixel=0;
                b.check(peek(0xcb)==32,"collision_event_retained",32,peek(0xcb));
                read(0xcb);
            }
        }
        read(0xca);b.check(b.rtl.irq,"read_is_not_ack",1,b.rtl.irq);clear_irq();
        // Reset discards flags/engines but retains CPU register RAM.
        write(0x0c,25);
        b.rtl.reset=1;b.tick();b.rtl.reset=0;
        b.check(peek(0x0c)==25 && peek(0xca)==0 && peek(0xcb)==0,"pvi_reset",25,peek(0x0c));
        b.check(!b.rtl.pixel_present && !b.rtl.irq,"pvi_reset_outputs",0,b.rtl.pixel_present);
        b.pass();return 0;
    }catch(const Failure&){return 1;}
}
