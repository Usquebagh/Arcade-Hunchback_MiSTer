-- SPDX-License-Identifier: BSD-3-Clause
-- Retained counterexamples from the exhaustive imported-core baseline.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.base_pack.all;
use work.sgs2650_pack.all;
entity s2650_edges_tb is end;
architecture test of s2650_edges_tb is
begin
  process
    variable value,flags : uv8;
    variable cases : natural := 0;
    variable line_out : line;
    procedure check(label_text : string; op,a,b,status,want_value,want_flags : natural) is
    begin
      op_alu(to_unsigned(op,8),to_unsigned(a,8),to_unsigned(b,8),to_unsigned(status,8),value,flags);
      if value/=want_value or flags/=want_flags then
        write(line_out,string'("BDSM {""status"":""FAIL"",""label"":"""));write(line_out,label_text);
        write(line_out,string'(""",""cycle"":"));write(line_out,cases);
        write(line_out,string'(",""expected"":"));write(line_out,want_value*256+want_flags);
        write(line_out,string'(",""observed"":"));write(line_out,to_integer(value)*256+to_integer(flags));
        write(line_out,string'("}"));writeline(output,line_out);stop(1);wait;
      end if;
      cases:=cases+1;
    end procedure;
  begin
    -- Result/PSL are packed into one assertion value; neither can hide the other.
    check("alu_add_idc",16#80#,0,15,16#3d#,16#10#,16#78#);
    check("alu_sub_idc",16#a0#,0,15,16#3c#,16#f0#,16#98#);
    check("alu_signed_compare",16#e0#,128,129,16#34#,128,16#b4#);
    write(line_out,string'("BDSM {""status"":""PASS"",""observed"":""Three retained ALU bug counterexamples""}"));
    writeline(output,line_out);stop(0);wait;
  end process;
end;
