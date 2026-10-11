# S2650 CPU boundary

Adapted from Arcadia revision `b18a02f43b116b21b57f25e0d608e2b321a7f501`;
original hashes/licenses are in `rtl/vendor/arcadia/README.md`. S2650A mode is
selected. The behavioural oracle is MAME `s2650.cpp` at
`c806573e925ce00fe3e8d8fe417eba63f83275ce`. Page addressing and cycle expectations
are also checked against the manufacturer manual reproduced at
https://amigan.yatho.com/2650UM.html. Tests use synthetic bytes only.

## Retained regressions

The native GHDL ALU test independently computes all 256x256 operands, eight
C/COM/WC combinations and eight ALU groups: 4,194,304 result/flag cases.
The unmodified package failed its baseline. Exact failures and corrections
remain in local MiSTer-BDSM reports; fast tests retain these counterexamples:

| Reproduced fault | Inputs | Required result |
| --- | --- | --- |
| Add interdigit carry | 00 + 0F + carry; PSL 3D | Byte 10, PSL 78 |
| Subtract interdigit borrow | 00 - 0F - borrow; PSL 3C | Byte F0, PSL 98 |
| Signed negative comparison | 80 versus 81; PSL 34 | Byte 80 unchanged, PSL B4 |
| HALT interrupt return | HALT; LODI R0,22; handler writes D7 then RETE | Resume writes 22, not D7 |
| Relative page overflow | Near 1FFF, branch to low-page offset 2 | Fetch 0002, not 2002 |

Directed processor scenarios also cover ordinary registers/status, alternate R1
banks, indexed/auto-increment/auto-decrement loads, indirect data in another page,
absolute subroutine/return, control/data and extended I/O, ack stalls, sense/FLAG,
one interrupt acknowledgement and disabled-enable state/request behaviour.
The programs explicitly initialize relevant software state. The initial memory
driver mistakenly changed data in the clock's delta; it was corrected to deliver
data after the sampling edge before further failures were interpreted. I/O
qualifiers/fetch restoration are tested with that corrected model.

## Bus and timing contracts

`ce` advances a synchronous machine step. A request transfers on an enabled edge
with ack high; synchronous read data is consumed on the next enabled step.
Ack stalls preserve the pending address. During synchronous reset the bus reads
opcode address zero; asynchronous reset deasserts requests. Reset must be clocked
before use. No synthesized clock gating is introduced.

A machine step represents three original CPU clock periods. Existing /32 main
and /64 sound clock strobes are preserved; /96 and /192 machine-step enables
are added at the declared four-crystal master. A LODI + ADDI + absolute store
takes eight steps between store markers (24 original clock periods). Cadences,
counts and reset restart are checked. This is directed timing, not a full cycle
oracle. The original boards have separate oscillators; shared-master phase
alignment remains an FPGA contract with CDC/drift review pending.

Sequential/relative/pointer/index arithmetic preserves 8 KiB pages; explicit
absolute branches retain 15-bit addressing. The relative boundary is tested.
All indexed/indirect wrap variants, stack depth/overflow and interrupt vectors
are not yet covered.

## Synthesis and coverage gaps

GHDL analyzes/elaborates/synthesizes the adapted CPU. Informational notes for a
256x70 decode ROM and 8x15 stack RAM are individually reviewed. Other diagnostics
become required WARNING. This is not Quartus fitting or TimeQuest qualification.
SystemVerilog retains separate unsuppressed Verilator -Wall checks.

Native CPU simulations expose numeric_std unknown-value warnings during startup
and evaluation of uninitialized state. They remain in logs, with a separate
required diagnostic check returning WARNING and blocking candidates. Functional
assertions can pass alongside that explicit gap. Do not force MAME's deterministic
reset image onto all hardware state merely to hide warnings; the manufacturer
guarantees less reset state than MAME initializes.

Mutations reintroduce the three arithmetic faults, remove page wrap, skip HALT
resume, ignore enable, use stale I/O qualifiers and shift machine-step cadence.
Each designated failure must reproduce twice. ALU cycle values are case IDs,
not physical clocks. Bus trace replay is capped at 2000 synthetic 10ns clocks.

Complete opcode/cycle differential coverage, full reset/unknown review, connected
CVS memory/game boot, video, sound instances, CDC/PLL/Quartus and physical testing
remain missing. Required CPU and full-machine blockers remain active. No RBF
candidate is produced in this increment.
