-- SPDX-License-Identifier: BSD-3-Clause
-- Independent integer expectations, pinned to MAME S2650 arithmetic semantics.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.base_pack.all;
use work.sgs2650_pack.all;

entity s2650_alu_tb is end;
architecture test of s2650_alu_tb is
begin
  process
    variable actual, flags : uv8;
    variable input_flags, wanted_flags : uv8;
    variable result_value, carry_in, wide, expected, diff : integer;
    variable a_signed, b_signed : integer;
    variable cases : natural := 0;
    variable line_out : line;
    procedure check(condition : boolean; label_text : string; want, got : integer) is
    begin
      if not condition then
        write(line_out,string'("BDSM {""status"":""FAIL"",""label"":"""));
        write(line_out,label_text);
        write(line_out,string'(""",""cycle"":"));write(line_out,cases);
        write(line_out,string'(",""expected"":"));write(line_out,want);
        write(line_out,string'(",""observed"":"));write(line_out,got);
        write(line_out,string'("}"));writeline(output,line_out);
        stop(1); wait;
      end if;
    end procedure;
  begin
    -- Full operand space and C/COM/WC combinations for all eight ALU groups.
    for operation in 0 to 7 loop
      for control in 0 to 7 loop
        input_flags := to_unsigned(16#34#,8);
        input_flags(0) := to_std_logic((control mod 2)=1);
        input_flags(1) := to_std_logic(((control/2) mod 2)=1);
        input_flags(3) := to_std_logic((control/4)=1);
        for a in 0 to 255 loop
          for b in 0 to 255 loop
            op_alu(to_unsigned(operation*32,8),to_unsigned(a,8),to_unsigned(b,8),input_flags,actual,flags);
            wanted_flags := input_flags;
            carry_in := 0;
            if input_flags(3)='1' and input_flags(0)='1' then carry_in:=1; end if;
            case operation is
              when 0 => result_value:=b;
              when 1 => result_value:=to_integer(to_unsigned(a,8) xor to_unsigned(b,8));
              when 2 => result_value:=to_integer(to_unsigned(a,8) and to_unsigned(b,8));
              when 3 => result_value:=to_integer(to_unsigned(a,8) or to_unsigned(b,8));
              when 4 =>
                wide:=a+b+carry_in; result_value:=wide mod 256;
                wanted_flags(0):=to_std_logic(wide>255);
                wanted_flags(5):=to_std_logic((a mod 16)+(b mod 16)+carry_in>15);
                wanted_flags(2):=to_std_logic(((a<128)=(b<128)) and ((result_value<128)/=(a<128)));
              when 5 =>
                carry_in:=0;
                if input_flags(3)='1' and input_flags(0)='0' then carry_in:=1;end if;
                wide:=a-b-carry_in; result_value:=wide mod 256;
                wanted_flags(0):=to_std_logic(wide>=0);
                wanted_flags(5):=to_std_logic((a mod 16)-(b mod 16)-carry_in>=0);
                wanted_flags(2):=to_std_logic(((a<128)/=(b<128)) and ((result_value<128)/=(a<128)));
              when 6 => result_value:=b;
              when others => result_value:=a;
            end case;
            if operation=7 then
              a_signed:=a; b_signed:=b;
              if input_flags(1)='0' then
                if a>=128 then a_signed:=a-256;end if;
                if b>=128 then b_signed:=b-256;end if;
              end if;
              diff:=a_signed-b_signed;
              if diff=0 then wanted_flags(7 downto 6):="00";
              elsif diff<0 then wanted_flags(7 downto 6):="10";
              else wanted_flags(7 downto 6):="01";end if;
            else
              if result_value=0 then wanted_flags(7 downto 6):="00";
              elsif result_value<128 then wanted_flags(7 downto 6):="01";
              else wanted_flags(7 downto 6):="10";end if;
            end if;
            expected:=result_value;
            check(to_integer(actual)=expected,"alu_result",expected,to_integer(actual));
            check(flags=wanted_flags,"alu_flags",to_integer(wanted_flags),to_integer(flags));
            cases:=cases+1;
          end loop;
        end loop;
      end loop;
    end loop;
    write(line_out,string'("BDSM {""status"":""PASS"",""observed"":""4194304 exhaustive ALU operand/control cases""}"));
    writeline(output,line_out);stop(0);wait;
  end process;
end;
