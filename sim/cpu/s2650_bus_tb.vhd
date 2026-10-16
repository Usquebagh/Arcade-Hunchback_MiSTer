-- SPDX-License-Identifier: BSD-3-Clause
-- Synthetic programs; software initializes status/registers before use.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.base_pack.all;

entity s2650_bus_tb is end;
architecture test of s2650_bus_tb is
  signal clk : std_logic := '0';
  signal reset : std_logic := '1';
  signal reset_na : std_logic := '0';
  signal ack, irq, sense : std_logic := '0';
  signal ivec : uv8 := x"30";
  signal ce : std_logic := '1';
  signal req, wr, mio, ene, dc, intack, flag : std_logic;
  signal ad : uv15;
  signal dw, dr : uv8 := (others=>'0');
  signal ph : uv2;
begin
  cpu : entity work.sgs2650
    generic map(VER_B=>false)
    port map(req=>req,ack=>ack,ad=>ad,wr=>wr,dw=>dw,dr=>dr,mio=>mio,
      ene=>ene,dc=>dc,ph=>ph,int=>irq,intack=>intack,ivec=>ivec,
      sense=>sense,flag=>flag,reset=>reset,ce=>ce,clk=>clk,reset_na=>reset_na);
  process
    type memory_type is array(0 to 32767) of uv8;
    type byte_list is array(natural range <>) of natural;
    variable memory : memory_type := (others=>x"40");
    variable clocks, io_writes, irq_acks : natural := 0;
    variable first_store, second_store : natural := 0;
    variable branch_armed, branch_next, branch_seen : boolean := false;
    variable wrap_target_seen, wrap_return_seen : boolean := false;
    variable startup_initialized : boolean := false;
    variable startup_stage : natural := 0;
    variable line_out : line;
    procedure check(condition : boolean; label_text : string; want, got : integer) is
    begin
      if not condition then
        write(line_out,string'("BDSM {""status"":""FAIL"",""label"":"""));write(line_out,label_text);
        write(line_out,string'(""",""cycle"":"));write(line_out,clocks);
        write(line_out,string'(",""expected"":"));write(line_out,want);
        write(line_out,string'(",""observed"":"));write(line_out,got);
        write(line_out,string'("}"));writeline(output,line_out);stop(1);wait;
      end if;
    end procedure;
    procedure program(base : natural; bytes : byte_list) is
    begin
      for n in bytes'range loop memory(base+n-bytes'low):=to_unsigned(bytes(n),8);end loop;
    end procedure;
    procedure tick(ready : std_logic := '1'; enable : std_logic := '1') is
      variable address : natural;
      variable read_value : uv8;
      variable update_read : boolean;
    begin
      clk<='0';ack<=ready;ce<=enable;wait for 5 ns;
      update_read:=false;
      if intack='1' then irq<='0';irq_acks:=irq_acks+1;end if;
      if reset='1' then
        if reset_na='1' then
          check(ad=0 and mio='1' and wr='0' and req='1',"reset_bus",0,to_integer(ad));
          read_value:=memory(to_integer(ad));update_read:=true;
        end if;
      elsif req='1' and ready='1' then
        address:=to_integer(ad);
        if mio='1' then
          if not startup_initialized and address=4 then
            check(startup_stage=3,"startup_status_fetch_sequence",3,startup_stage);
            startup_initialized:=true;
            write(line_out,string'("BDSM {""status"":""INFO"",""label"":""startup_status_initialized"",""time_ns"":"));
            write(line_out,now/1 ns);write(line_out,string'("}"));writeline(output,line_out);
          elsif not startup_initialized then
            case startup_stage is
              when 0 => check(address=1,"startup_cpsl_operand",1,address);startup_stage:=1;
              when 1 =>
                if address=2 then startup_stage:=2;
                else check(address=1,"startup_cpsl_operand_repeat",1,address);end if;
              when 2 =>
                if address=3 then startup_stage:=3;
                else check(address=2,"startup_ppsl_opcode_repeat",2,address);end if;
              when others => check(address=3,"startup_ppsl_operand_repeat",3,address);
            end case;
          end if;
          if branch_next then
            check(address=2,"relative_page",2,address);branch_seen:=true;branch_next:=false;
          elsif branch_armed and address=16#1ffe# then
            branch_next:=true;
          end if;
          if wr='1' then
            memory(address):=dw;
            if address=16#1c00# and first_store=0 then first_store:=clocks;end if;
            if address=16#1c01# and second_store=0 then second_store:=clocks;end if;
          else
            if wrap_target_seen and address=0 then wrap_return_seen:=true;end if;
            if address=16#10# then wrap_target_seen:=true;end if;
            read_value:=memory(address);update_read:=true;
          end if;
        elsif wr='0' then
          if ene='1' then
            check(address=16#a7#,"extended_read_address",16#a7#,address);read_value:=x"d2";update_read:=true;
          else
            check(dc='0',"control_read",0,1);read_value:=x"6d";update_read:=true;
          end if;
        else
          io_writes:=io_writes+1;
          if ene='1' then
            check(address=16#a8#,"extended_write_address",16#a8#,address);
            check(dw=x"d2","extended_write_byte",16#d2#,to_integer(dw));
          else
            check(dc='1',"data_write",1,0);
            check(dw=x"6d","data_write_byte",16#6d#,to_integer(dw));
          end if;
        end if;
      end if;
      clk<='1';wait for 0 ns;
      -- Like a separate synchronous RAM process, data arrives after sampling.
      if update_read then dr<=read_value;end if;
      wait for 5 ns;clocks:=clocks+1;
    end procedure;
    procedure start is
    begin
      irq<='0';reset<='1';reset_na<='0';tick;
      -- The manufacturer startup procedure requires at least three RESET clocks.
      reset_na<='1';for n in 1 to 2 loop tick;end loop;
      reset<='0';
      wait for 1 ns; -- settle the reset-address mux before sampling bus outputs
    end procedure;
    variable held_address : uv15;
  begin
    program(0,(
      16#75#,16#ff#,16#77#,16#0a#, -- CPSL ff; PPSL 0a initializes PSL
      16#04#,16#12#,16#05#,16#34#,16#06#,16#56#,16#07#,16#78#,
      16#01#,16#cc#,16#1c#,0,
      16#04#,16#ff#,16#84#,1,16#cc#,16#1c#,1,
      16#13#,16#cc#,16#1c#,2,
      16#77#,16#10#,16#05#,16#a5#,16#75#,16#10#,16#01#,16#cc#,16#1c#,3,
      16#77#,16#10#,16#01#,16#cc#,16#1c#,4,16#75#,16#10#,
      16#05#,3,16#0d#,16#61#,0,16#cc#,16#1c#,5,
      16#0d#,16#21#,0,16#cc#,16#1c#,6,
      16#0d#,16#41#,0,16#cc#,16#1c#,7,
      16#0c#,16#81#,16#30#,16#cc#,16#1c#,8,
      16#3f#,0,16#c0#,16#cc#,16#1c#,9,
      16#30#,16#f0#,16#55#,16#a7#,16#d5#,16#a8#,
      16#76#,16#40#,16#12#,16#cc#,16#1c#,10,16#40#));
    program(16#c0#,(16#04#,16#bc#,16#17#));
    memory(16#103#):=x"9a";memory(16#104#):=x"a7";
    memory(16#130#):=x"41";memory(16#131#):=x"40";memory(16#4140#):=x"5c";
    sense<='1';start;
    held_address:=ad;
    for n in 1 to 10 loop
      tick('1','0');check(req='0',"disabled_request",0,1);
      check(ad=held_address,"disabled_state",to_integer(held_address),to_integer(ad));
    end loop;
    ack<='0';wait for 1 ns;held_address:=ad;
    for n in 1 to 10 loop tick('0');check(ad=held_address,"bus_stall_address",to_integer(held_address),to_integer(ad));end loop;
    for n in 1 to 400 loop tick;end loop;
    check(memory(16#1c00#)=x"34","register_load",16#34#,to_integer(memory(16#1c00#)));
    check(memory(16#1c01#)=x"00","immediate_add",0,to_integer(memory(16#1c01#)));
    check(memory(16#1c02#)=x"2b","status_flags",16#2b#,to_integer(memory(16#1c02#)));
    check(memory(16#1c03#)=x"34","bank_zero",16#34#,to_integer(memory(16#1c03#)));
    check(memory(16#1c04#)=x"a5","bank_one",16#a5#,to_integer(memory(16#1c04#)));
    check(memory(16#1c05#)=x"9a","absolute_index",16#9a#,to_integer(memory(16#1c05#)));
    check(memory(16#1c06#)=x"a7","preincrement",16#a7#,to_integer(memory(16#1c06#)));
    check(memory(16#1c07#)=x"9a","predecrement",16#9a#,to_integer(memory(16#1c07#)));
    check(memory(16#1c08#)=x"5c","indirect_page",16#5c#,to_integer(memory(16#1c08#)));
    check(memory(16#1c09#)=x"bc","subroutine_return",16#bc#,to_integer(memory(16#1c09#)));
    check(memory(16#1c0a#)=x"c0","sense_flag",16#c0#,to_integer(memory(16#1c0a#)));
    check(io_writes=2,"io_write_count",2,io_writes);check(flag='1',"flag_pin",1,0);
    check(second_store-first_store=8,"instruction_cadence",8,second_store-first_store);

    -- Absolute BCTA indirect reads the pointer before fetching the branch target.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#1c#,16#80#,16#10#,16#40#));
    memory(16#10#):=x"02";memory(16#11#):=x"00";
    program(16#200#,(16#05#,16#7c#,16#cd#,16#1c#,16#97#,16#40#));
    start;for n in 1 to 30 loop tick;end loop;
    check(memory(16#1c97#)=x"7c","absolute_indirect_branch_target",16#7c#,to_integer(memory(16#1c97#)));

    -- BCFA '=' with positive CC takes the false-condition branch through its pointer.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,1,
      16#9c#,16#80#,16#10#,16#05#,16#11#,16#cd#,16#1c#,16#30#,16#40#));
    memory(16#10#):=x"02";memory(16#11#):=x"00";
    program(16#200#,(16#05#,16#33#,16#cd#,16#1c#,16#31#,16#40#));
    start;for n in 1 to 25 loop tick;end loop;
    check(memory(16#1c30#)=x"40","bcfa_indirect_skips_fallthrough",16#40#,to_integer(memory(16#1c30#)));
    check(memory(16#1c31#)=x"33","bcfa_indirect_target",16#33#,to_integer(memory(16#1c31#)));

    -- BCTA '>' with positive CC takes the indirect pointer to target 0200.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,1,
      16#1d#,16#80#,16#10#,16#05#,16#11#,16#cd#,16#1c#,16#32#,16#40#));
    memory(16#10#):=x"02";memory(16#11#):=x"00";
    program(16#200#,(16#05#,16#44#,16#cd#,16#1c#,16#33#,16#40#));
    start;for n in 1 to 25 loop tick;end loop;
    check(memory(16#1c32#)=x"40","bcta_indirect_greater_skips_fallthrough",16#40#,to_integer(memory(16#1c32#)));
    check(memory(16#1c33#)=x"44","bcta_indirect_greater_target",16#44#,to_integer(memory(16#1c33#)));

    -- Direct BXA R3 uses its index after the absolute base address.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#07#,1,16#9f#,2,0,16#40#));
    memory(16#200#):=x"40";
    program(16#201#,(16#05#,16#6d#,16#cd#,16#1c#,16#98#,16#40#));
    start;for n in 1 to 55 loop tick;end loop;
    check(memory(16#1c98#)=x"6d","bxa_indexed_target",16#6d#,to_integer(memory(16#1c98#)));

    -- BXA R3 indirect resolves the base pointer before adding the index.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#07#,1,16#9f#,16#80#,16#10#,16#40#));
    memory(16#10#):=x"03";memory(16#11#):=x"00";
    memory(16#300#):=x"40";
    program(16#301#,(16#05#,16#7d#,16#cd#,16#1c#,16#99#,16#40#));
    start;for n in 1 to 60 loop tick;end loop;
    check(memory(16#1c99#)=x"7d","bxa_indirect_indexed_target",16#7d#,to_integer(memory(16#1c99#)));

    -- Direct BSXA R3 calls through base+index and returns to the caller.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#07#,1,16#bf#,4,0,
      16#05#,16#55#,16#cd#,16#1c#,16#9b#,16#40#));
    memory(16#400#):=x"40";
    program(16#401#,(16#05#,16#a6#,16#cd#,16#1c#,16#9a#,16#17#));
    start;for n in 1 to 70 loop tick;end loop;
    check(memory(16#1c9a#)=x"a6","bsxa_indexed_subroutine",16#a6#,to_integer(memory(16#1c9a#)));
    check(memory(16#1c9b#)=x"55","bsxa_indexed_return",16#55#,to_integer(memory(16#1c9b#)));

    -- Indirect BSXA resolves the pointer, adds R3 and preserves the return PC.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#07#,1,16#bf#,16#80#,16#10#,
      16#05#,16#66#,16#cd#,16#1c#,16#9d#,16#40#));
    memory(16#10#):=x"04";memory(16#11#):=x"00";
    memory(16#400#):=x"40";
    program(16#401#,(16#05#,16#b7#,16#cd#,16#1c#,16#9c#,16#17#));
    start;for n in 1 to 75 loop tick;end loop;
    check(memory(16#1c9c#)=x"b7","bsxa_indirect_indexed_subroutine",16#b7#,to_integer(memory(16#1c9c#)));
    check(memory(16#1c9d#)=x"66","bsxa_indirect_indexed_return",16#66#,to_integer(memory(16#1c9d#)));

    -- Relative BCTR indirect resolves a page-local pointer before fetching its target.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#18#,16#8a#,16#40#));
    memory(16#10#):=x"02";memory(16#11#):=x"00";
    program(16#200#,(16#05#,16#6b#,16#cd#,16#1c#,16#94#,16#40#));
    start;for n in 1 to 55 loop tick;end loop;
    check(memory(16#1c94#)=x"6b","relative_indirect_target",16#6b#,to_integer(memory(16#1c94#)));

    -- Absolute BSTA indirect pushes the caller PC, resolves the pointer and returns.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#3c#,16#80#,16#10#,
      16#05#,16#55#,16#cd#,16#1c#,16#96#,16#40#));
    memory(16#10#):=x"02";memory(16#11#):=x"00";
    program(16#200#,(16#05#,16#44#,16#cd#,16#1c#,16#95#,16#17#));
    start;for n in 1 to 65 loop tick;end loop;
    check(memory(16#1c95#)=x"44","absolute_indirect_subroutine",16#44#,to_integer(memory(16#1c95#)));
    check(memory(16#1c96#)=x"55","absolute_indirect_return",16#55#,to_integer(memory(16#1c96#)));

    -- LODA R1 indirect indexed resolves the pointer, adds R1, then loads R0.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#05#,1,16#0d#,16#e0#,16#10#,
      16#cc#,16#1c#,16#9e#,16#40#));
    memory(16#10#):=x"03";memory(16#11#):=x"00";memory(16#301#):=x"6d";
    start;for n in 1 to 65 loop tick;end loop;
    check(memory(16#1c9e#)=x"6d","absolute_indirect_indexed_load",16#6d#,to_integer(memory(16#1c9e#)));

    -- Indirect pre-increment indexes 0300 with updated R1=2 and retains it.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#05#,1,16#0d#,16#a0#,16#10#,
      16#cc#,16#1c#,16#9f#,16#cd#,16#1c#,16#a1#,16#40#));
    memory(16#10#):=x"03";memory(16#11#):=x"00";memory(16#302#):=x"6e";
    start;for n in 1 to 75 loop tick;end loop;
    check(memory(16#1c9f#)=x"6e","absolute_indirect_preincrement_load",16#6e#,to_integer(memory(16#1c9f#)));
    check(memory(16#1ca1#)=x"02","absolute_indirect_preincrement_register",2,to_integer(memory(16#1ca1#)));

    -- Indirect pre-decrement indexes 0300 with updated R1=0 and retains it.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#05#,1,16#0d#,16#c0#,16#10#,
      16#cc#,16#1c#,16#a0#,16#cd#,16#1c#,16#a2#,16#40#));
    memory(16#10#):=x"03";memory(16#11#):=x"00";memory(16#300#):=x"7b";
    start;for n in 1 to 75 loop tick;end loop;
    check(memory(16#1ca0#)=x"7b","absolute_indirect_predecrement_load",16#7b#,to_integer(memory(16#1ca0#)));
    check(memory(16#1ca2#)=x"00","absolute_indirect_predecrement_register",0,to_integer(memory(16#1ca2#)));

    -- Indirect indexed address 1FFF plus R1=1 wraps to 0000 within page zero.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#05#,1,16#0d#,16#e0#,16#10#,
      16#cc#,16#1c#,16#a4#,16#40#));
    memory(16#10#):=x"1f";memory(16#11#):=x"ff";
    memory(16#2000#):=x"40";
    start;for n in 1 to 65 loop tick;end loop;
    check(memory(16#1ca4#)=x"75","absolute_indirect_indexed_page_wrap",16#75#,to_integer(memory(16#1ca4#)));

    -- Pre-increment R1=0 and pre-decrement R1=2 both wrap 1FFF+1 to 0000.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#05#,0,16#0d#,16#a0#,16#10#,
      16#cc#,16#1c#,16#a5#,16#cd#,16#1c#,16#a6#,16#40#));
    memory(16#10#):=x"1f";memory(16#11#):=x"ff";memory(16#2000#):=x"40";
    start;for n in 1 to 75 loop tick;end loop;
    check(memory(16#1ca5#)=x"75","absolute_indirect_preincrement_page_wrap",16#75#,to_integer(memory(16#1ca5#)));
    check(memory(16#1ca6#)=x"01","absolute_indirect_preincrement_page_wrap_register",1,to_integer(memory(16#1ca6#)));

    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#05#,2,16#0d#,16#c0#,16#10#,
      16#cc#,16#1c#,16#a7#,16#cd#,16#1c#,16#a8#,16#40#));
    memory(16#10#):=x"1f";memory(16#11#):=x"ff";memory(16#2000#):=x"40";
    start;for n in 1 to 75 loop tick;end loop;
    check(memory(16#1ca7#)=x"75","absolute_indirect_predecrement_page_wrap",16#75#,to_integer(memory(16#1ca7#)));
    check(memory(16#1ca8#)=x"01","absolute_indirect_predecrement_page_wrap_register",1,to_integer(memory(16#1ca8#)));

    -- HALT wake, interrupt entry/RETE and resume at the next instruction.
    memory:=(others=>x"40");io_writes:=0;irq_acks:=0;
    program(0,(16#1f#,0,16#60#));
    program(16#30#,(16#04#,16#d7#,16#cc#,16#1c#,2,16#37#));
    program(16#60#,(16#75#,16#ff#,16#77#,16#0a#,16#04#,16#11#,16#cc#,16#1c#,0,
      16#40#,16#04#,16#22#,16#cc#,16#1c#,1,16#40#));
    start;for n in 1 to 50 loop tick;end loop;
    check(memory(16#1c00#)=x"11","before_halt",16#11#,to_integer(memory(16#1c00#)));
    irq<='1';for n in 1 to 150 loop tick;end loop;
    check(memory(16#1c02#)=x"d7","interrupt_handler",16#d7#,to_integer(memory(16#1c02#)));
    check(memory(16#1c01#)=x"22","halt_resume",16#22#,to_integer(memory(16#1c01#)));
    check(irq_acks=1,"interrupt_ack_count",1,irq_acks);

    -- Nested absolute subroutines exercise two distinct return-stack entries.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#bf#,0,16#c0#,
      16#05#,16#a5#,16#cd#,16#1c#,16#21#,16#40#));
    program(16#c0#,(16#bf#,0,16#e0#,16#17#));
    program(16#e0#,(16#04#,16#5a#,16#cc#,16#1c#,16#20#,16#17#));
    start;for n in 1 to 60 loop tick;end loop;
    check(memory(16#1c20#)=x"5a","nested_inner_return",16#5a#,to_integer(memory(16#1c20#)));
    check(memory(16#1c21#)=x"a5","nested_outer_return",16#a5#,to_integer(memory(16#1c21#)));

    -- BIRA increments modulo 256 and branches exactly when the new value is nonzero.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,16#ff#,
      16#dc#,0,16#c0#,16#04#,0,16#dc#,0,16#e0#,
      16#05#,16#11#,16#cd#,16#1c#,16#22#,16#40#));
    program(16#c0#,(16#05#,16#22#,16#cd#,16#1c#,16#22#,16#40#));
    program(16#e0#,(16#05#,16#33#,16#cd#,16#1c#,16#23#,16#40#));
    start;for n in 1 to 50 loop tick;end loop;
    check(memory(16#1c22#)=x"40","bira_wrap_not_taken",16#40#,to_integer(memory(16#1c22#)));
    check(memory(16#1c23#)=x"33","bira_nonzero_taken",16#33#,to_integer(memory(16#1c23#)));

    -- BDRA decrements modulo 256 and branches exactly when the new value is nonzero.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,1,
      16#fc#,0,16#c0#,16#04#,0,16#fc#,0,16#e0#,
      16#05#,16#55#,16#cd#,16#1c#,16#25#,16#40#));
    program(16#c0#,(16#05#,16#44#,16#cd#,16#1c#,16#24#,16#40#));
    program(16#e0#,(16#05#,16#66#,16#cd#,16#1c#,16#26#,16#40#));
    start;for n in 1 to 50 loop tick;end loop;
    check(memory(16#1c24#)=x"40","bdra_zero_not_taken",16#40#,to_integer(memory(16#1c24#)));
    check(memory(16#1c26#)=x"66","bdra_nonzero_taken",16#66#,to_integer(memory(16#1c26#)));

    -- A false '=' condition makes BCFR take across the 1FFF page boundary.
    memory:=(others=>x"40");
    program(0,(16#04#,1,16#1f#,16#1f#,16#fe#));
    program(16#1ffe#,(16#98#,16));
    program(16#10#,(16#05#,16#6c#,16#cd#,16#1c#,16#93#,16#40#));
    start;for n in 1 to 45 loop tick;end loop;
    check(memory(16#1c93#)=x"6c","bcfr_page_wrap_target",16#6c#,to_integer(memory(16#1c93#)));

    -- BIRR relative uses the same post-operand base and modulo register update.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,16#ff#,16#d8#,22,
      16#05#,16#11#,16#cd#,16#1c#,16#22#,16#04#,0,16#d8#,13,
      16#05#,16#22#,16#cd#,16#1c#,16#23#,16#40#));
    program(30,(16#05#,16#33#,16#cd#,16#1c#,16#24#,16#40#));
    start;for n in 1 to 55 loop tick;end loop;
    check(memory(16#1c22#)=x"11","birr_wrap_not_taken",16#11#,to_integer(memory(16#1c22#)));
    check(memory(16#1c23#)=x"40","birr_branch_skips_fallthrough",16#40#,to_integer(memory(16#1c23#)));
    check(memory(16#1c24#)=x"33","birr_nonzero_taken",16#33#,to_integer(memory(16#1c24#)));

    -- BDRR relative covers 1-to-zero non-taken and zero-to-FF taken cases.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,1,16#f8#,22,
      16#05#,16#55#,16#cd#,16#1c#,16#25#,16#04#,0,16#f8#,13,
      16#05#,16#66#,16#cd#,16#1c#,16#26#,16#40#));
    program(30,(16#05#,16#77#,16#cd#,16#1c#,16#27#,16#40#));
    start;for n in 1 to 55 loop tick;end loop;
    check(memory(16#1c25#)=x"55","bdrr_zero_not_taken",16#55#,to_integer(memory(16#1c25#)));
    check(memory(16#1c26#)=x"40","bdrr_branch_skips_fallthrough",16#40#,to_integer(memory(16#1c26#)));
    check(memory(16#1c27#)=x"77","bdrr_nonzero_taken",16#77#,to_integer(memory(16#1c27#)));

    -- BCTA '=' is false for positive CC and true for zero CC.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,1,
      16#1c#,0,16#c0#,16#05#,16#11#,16#cd#,16#1c#,16#30#,
      16#04#,0,16#1c#,0,16#e0#,16#05#,16#22#,16#cd#,16#1c#,16#31#,16#40#));
    program(16#c0#,(16#05#,16#33#,16#cd#,16#1c#,16#32#,16#40#));
    program(16#e0#,(16#05#,16#44#,16#cd#,16#1c#,16#33#,16#40#));
    start;for n in 1 to 60 loop tick;end loop;
    check(memory(16#1c30#)=x"11","bcta_false_fallthrough",16#11#,to_integer(memory(16#1c30#)));
    check(memory(16#1c31#)=x"40","bcta_true_skips_fallthrough",16#40#,to_integer(memory(16#1c31#)));
    check(memory(16#1c32#)=x"40","bcta_false_skips_target",16#40#,to_integer(memory(16#1c32#)));
    check(memory(16#1c33#)=x"44","bcta_zero_taken",16#44#,to_integer(memory(16#1c33#)));

    -- BCTR '=' falls through for positive CC; BCFR '=' takes on that same CC.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,1,
      16#18#,18,16#05#,16#11#,16#cd#,16#1c#,16#40#,
      16#98#,11,16#05#,16#22#,16#cd#,16#1c#,16#41#,16#40#));
    program(26,(16#05#,16#33#,16#cd#,16#1c#,16#42#,16#40#));
    start;for n in 1 to 55 loop tick;end loop;
    check(memory(16#1c40#)=x"11","bctr_false_fallthrough",16#11#,to_integer(memory(16#1c40#)));
    check(memory(16#1c41#)=x"40","bcfr_taken_skips_fallthrough",16#40#,to_integer(memory(16#1c41#)));
    check(memory(16#1c42#)=x"33","bcfr_positive_taken",16#33#,to_integer(memory(16#1c42#)));

    -- RETC '=' must leave the stack intact when false; RETC '>' then returns.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#bf#,0,16#c0#,
      16#cd#,16#1c#,16#34#,16#40#));
    program(16#c0#,(16#04#,1,16#14#,16#05#,16#5a#,16#15#,16#40#));
    start;for n in 1 to 50 loop tick;end loop;
    check(memory(16#1c34#)=x"5a","retc_false_then_true",16#5a#,to_integer(memory(16#1c34#)));

    -- BSTA '=' must skip on positive CC, then call and return on zero CC.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,1,
      16#3c#,0,16#c0#,16#05#,16#11#,16#cd#,16#1c#,16#50#,
      16#04#,0,16#3c#,0,16#e0#,16#05#,16#22#,16#cd#,16#1c#,16#51#,16#40#));
    program(16#c0#,(16#05#,16#33#,16#cd#,16#1c#,16#52#,16#17#));
    program(16#e0#,(16#05#,16#44#,16#cd#,16#1c#,16#53#,16#17#));
    start;for n in 1 to 65 loop tick;end loop;
    check(memory(16#1c50#)=x"11","bsta_false_fallthrough",16#11#,to_integer(memory(16#1c50#)));
    check(memory(16#1c51#)=x"22","bsta_return_marker",16#22#,to_integer(memory(16#1c51#)));
    check(memory(16#1c52#)=x"40","bsta_false_skips_subroutine",16#40#,to_integer(memory(16#1c52#)));
    check(memory(16#1c53#)=x"44","bsta_zero_subroutine",16#44#,to_integer(memory(16#1c53#)));

    -- BSFA '=' calls for positive CC (condition false) and skips for zero CC.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,1,
      16#bc#,0,16#c0#,16#05#,16#11#,16#cd#,16#1c#,16#80#,
      16#04#,0,16#bc#,0,16#e0#,16#05#,16#22#,16#cd#,16#1c#,16#81#,16#40#));
    program(16#c0#,(16#05#,16#33#,16#cd#,16#1c#,16#82#,16#17#));
    program(16#e0#,(16#05#,16#44#,16#cd#,16#1c#,16#83#,16#17#));
    start;for n in 1 to 65 loop tick;end loop;
    check(memory(16#1c80#)=x"11","bsfa_false_condition_return",16#11#,to_integer(memory(16#1c80#)));
    check(memory(16#1c81#)=x"22","bsfa_true_condition_fallthrough",16#22#,to_integer(memory(16#1c81#)));
    check(memory(16#1c82#)=x"33","bsfa_false_subroutine",16#33#,to_integer(memory(16#1c82#)));
    check(memory(16#1c83#)=x"40","bsfa_true_skips_subroutine",16#40#,to_integer(memory(16#1c83#)));

    -- BSTR target calculation crosses 1FFF to address 0010 within the same page.
    memory:=(others=>x"40");
    program(0,(16#1f#,16#1f#,16#fe#));
    program(16#1ffe#,(16#3b#,16));
    program(16#10#,(16#04#,16#5a#,16#cc#,16#1c#,16#90#,16#17#));
    wrap_target_seen:=false;wrap_return_seen:=false;
    start;for n in 1 to 45 loop tick;end loop;
    check(memory(16#1c90#)=x"5a","bstr_page_wrap_target",16#5a#,to_integer(memory(16#1c90#)));
    check(wrap_return_seen,"bstr_page_wrap_return",1,boolean'pos(wrap_return_seen));

    -- BIRR increments R0 and branches from 1FFF to offset 0010 in page zero.
    memory:=(others=>x"40");
    program(0,(16#04#,0,16#1f#,16#1f#,16#fe#));
    program(16#1ffe#,(16#d8#,16));
    program(16#10#,(16#05#,16#6b#,16#cd#,16#1c#,16#91#,16#40#));
    start;for n in 1 to 45 loop tick;end loop;
    check(memory(16#1c91#)=x"6b","birr_page_wrap_target",16#6b#,to_integer(memory(16#1c91#)));

    -- BDRR decrements a nonzero R0 and takes the same page-wrapped target.
    memory:=(others=>x"40");
    program(0,(16#04#,2,16#1f#,16#1f#,16#fe#));
    program(16#1ffe#,(16#f8#,16));
    program(16#10#,(16#05#,16#7b#,16#cd#,16#1c#,16#92#,16#40#));
    start;for n in 1 to 45 loop tick;end loop;
    check(memory(16#1c92#)=x"7b","bdrr_page_wrap_target",16#7b#,to_integer(memory(16#1c92#)));

    -- Eight active calls fill the complete three-bit hardware return stack.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#bf#,1,0,
      16#05#,16#5a#,16#cd#,16#1c#,16#71#,16#40#));
    program(16#100#,(16#bf#,1,16#10#,16#17#));
    program(16#110#,(16#bf#,1,16#20#,16#17#));
    program(16#120#,(16#bf#,1,16#30#,16#17#));
    program(16#130#,(16#bf#,1,16#40#,16#17#));
    program(16#140#,(16#bf#,1,16#50#,16#17#));
    program(16#150#,(16#bf#,1,16#60#,16#17#));
    program(16#160#,(16#bf#,1,16#70#,16#17#));
    program(16#170#,(16#04#,16#a8#,16#cc#,16#1c#,16#70#,16#17#));
    start;for n in 1 to 100 loop tick;end loop;
    check(memory(16#1c70#)=x"a8","stack_depth8_deepest_call",16#a8#,to_integer(memory(16#1c70#)));
    check(memory(16#1c71#)=x"5a","stack_depth8_outer_return",16#5a#,to_integer(memory(16#1c71#)));

    -- BSTR '=' skips on positive CC, then calls on zero CC and returns.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,1,16#38#,32,
      16#05#,16#11#,16#cd#,16#1c#,16#60#,16#04#,0,16#38#,13,
      16#05#,16#22#,16#cd#,16#1c#,16#61#,16#40#));
    program(30,(16#05#,16#33#,16#cd#,16#1c#,16#62#,16#17#));
    program(40,(16#05#,16#66#,16#cd#,16#1c#,16#65#,16#17#));
    start;for n in 1 to 60 loop tick;end loop;
    check(memory(16#1c60#)=x"11","bstr_false_fallthrough",16#11#,to_integer(memory(16#1c60#)));
    check(memory(16#1c61#)=x"22","bstr_return_marker",16#22#,to_integer(memory(16#1c61#)));
    check(memory(16#1c62#)=x"33","bstr_true_subroutine",16#33#,to_integer(memory(16#1c62#)));
    check(memory(16#1c65#)=x"40","bstr_false_skips_subroutine",16#40#,to_integer(memory(16#1c65#)));

    -- BSFR '=' takes for positive CC, returns, then resumes at fall-through.
    memory:=(others=>x"40");
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#04#,1,16#b8#,22,
      16#05#,16#55#,16#cd#,16#1c#,16#63#,16#40#));
    program(30,(16#05#,16#44#,16#cd#,16#1c#,16#64#,16#17#));
    start;for n in 1 to 50 loop tick;end loop;
    check(memory(16#1c63#)=x"55","bsfr_return_fallthrough",16#55#,to_integer(memory(16#1c63#)));
    check(memory(16#1c64#)=x"44","bsfr_positive_subroutine",16#44#,to_integer(memory(16#1c64#)));

    -- Interrupt handler's false RETE must not return; true RETE resumes after HALT.
    memory:=(others=>x"40");io_writes:=0;irq_acks:=0;
    program(0,(16#1f#,0,16#60#));
    program(16#60#,(16#75#,16#ff#,16#77#,16#0a#,16#04#,16#11#,
      16#cc#,16#1c#,0,16#40#,16#04#,16#22#,16#cc#,16#1c#,1,16#40#));
    program(16#30#,(16#04#,1,16#34#,16#05#,16#66#,16#cd#,16#1c#,2,16#35#,16#40#));
    start;for n in 1 to 50 loop tick;end loop;
    check(memory(16#1c00#)=x"11","rete_before_halt",16#11#,to_integer(memory(16#1c00#)));
    irq<='1';for n in 1 to 90 loop tick;end loop;
    check(memory(16#1c02#)=x"66","rete_false_handler_path",16#66#,to_integer(memory(16#1c02#)));
    check(memory(16#1c01#)=x"22","rete_true_resume",16#22#,to_integer(memory(16#1c01#)));
    check(irq_acks=1,"rete_ack_count",1,irq_acks);

    -- Indirect interrupt vector reads a page-zero pointer before handler entry.
    memory:=(others=>x"40");io_writes:=0;irq_acks:=0;ivec<=x"b0";
    program(0,(16#75#,16#ff#,16#77#,16#0a#,16#40#,16#05#,16#22#,
      16#cd#,16#1c#,16#a1#,16#40#));
    memory(16#30#):=x"00";memory(16#31#):=x"50";
    program(16#50#,(16#05#,16#d8#,16#cd#,16#1c#,16#a2#,16#37#));
    start;for n in 1 to 50 loop tick;end loop;
    check(memory(16#1ca1#)=x"40","indirect_vector_before_irq",16#40#,to_integer(memory(16#1ca1#)));
    irq<='1';for n in 1 to 120 loop tick;end loop;
    check(memory(16#1ca2#)=x"d8","interrupt_indirect_vector_handler",16#d8#,to_integer(memory(16#1ca2#)));
    check(memory(16#1ca1#)=x"22","interrupt_indirect_vector_return",16#22#,to_integer(memory(16#1ca1#)));
    check(irq_acks=1,"indirect_vector_ack_count",1,irq_acks);
    ivec<=x"30";

    -- Relative branch wraps inside its current 8 KiB page, not into page 1.
    memory:=(others=>x"40");
    program(0,(16#1f#,16#1f#,16#fb#));
    program(16#1ffb#,(16#75#,16#ff#,16#1b#,3));
    branch_armed:=true;start;for n in 1 to 25 loop tick;end loop;
    check(branch_seen,"relative_branch_progress",1,0);

    -- The second byte of an absolute indirect pointer wraps within its 8 KiB page.
    -- Start at 1F80, read the pointer high byte at 1FFF and its low byte at 0000.
    memory:=(others=>x"40");
    program(0,(16#00#,16#1c#,16#1f#,16#80#));
    program(16#1f80#,(16#75#,16#ff#,16#77#,16#0a#,16#1c#,16#9f#,16#ff#));
    memory(16#1fff#):=x"02";
    program(16#200#,(16#05#,16#7c#,16#cd#,16#1c#,16#97#,16#40#));
    start;for n in 1 to 80 loop tick;end loop;
    check(memory(16#1c97#)=x"7c","absolute_indirect_pointer_page_wrap",16#7c#,to_integer(memory(16#1c97#)));

    write(line_out,string'("BDSM {""status"":""PASS"",""observed"":""Synthetic CPU register/status/addressing/bus/IO/nested returns/conditional return/relative and absolute branch scenarios/HALT interrupt""}"));
    writeline(output,line_out);stop(0);wait;
  end process;
end;
