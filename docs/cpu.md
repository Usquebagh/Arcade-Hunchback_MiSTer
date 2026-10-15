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
absolute subroutine/return, nested two-level absolute subroutine/return, control/data
and extended I/O, ack stalls, sense/FLAG, one interrupt acknowledgement and
disabled-enable state/request behaviour. The nested-call regression checks separate
inner and outer return markers; it is still directed coverage, not exhaustive stack
depth or overflow qualification.
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

The shared directed bus bench now asserts active-low reset from simulation time
zero. This removes one fixture-start warning, but the diagnostic still reports 21
numeric_std warnings: unknown comparisons at time zero and later reset/fetch
transitions, plus unknown conversions from 66 ns through 267 ns after reset
release. They remain evidence of uninitialized CPU state and keep the required
WARNING active; no warning is filtered or suppressed.

Mutations reintroduce the three arithmetic faults, remove page wrap, skip HALT
resume, ignore enable, use stale I/O qualifiers and shift machine-step cadence.
Each designated failure must reproduce twice. ALU cycle values are case IDs,
not physical clocks. Bus trace replay is capped at 2000 synthetic 10ns clocks.

Complete opcode/cycle differential coverage, full reset/unknown review, connected
CVS memory/game boot, video, sound instances, CDC/PLL/Quartus and physical testing
remain missing. Required CPU and full-machine blockers remain active. No RBF
candidate is produced in this increment.

## Cold synthesized self-XOR regression, 2026-10-11

The actual synthesized CPU lacks upstream's simulation-only general-register
initialization. The real parent begins clearing RAM by EORZ R0 followed by
STRZ R1 and indexed stores. The first write failed with unknown data/address.
An independent cold synthetic reproduction failed too. EORZ R0 now explicitly
implements its architectural zero and CC=zero, preserving all other PSL bits.
The strengthened regression checks two known indexed zero stores and PSL=27
after independent status initialization. No broad reset values or diagnostic
suppression were introduced. Native CPU/ALU/synthesis and connected bus pass;
the required broader unknown-state WARNING remains active. The unchanged ROM's
first 1024 RAM-clear writes match a restricted independent instruction model.
Attract/gameplay, complete ISA/cycle and physical reference remain unqualified.

## Nested return-stack regression, 2026-10-15

The focused `hunchback.cpu.bus` check now executes two nested absolute
subroutines and verifies distinct inner and outer return markers. Its baseline
passed after the bench change. In disposable source copies, forcing all
subroutine pushes into stack slot zero failed `nested_outer_return` at cycle 755
on two consecutive runs. The fault model and designated assertion are retained
as `overwritten_nested_return` in the BDSM adapter. This covers two active stack
entries only; deeper nesting, wrap/overflow, interrupt/subroutine interaction,
full opcode/cycle differential and native unknown-state diagnostics remain open.

The same bench now checks absolute BIRA/BDRA with zero-wrap non-taken and
nonzero taken cases against the pinned MAME instruction macros and CPU branch
decode. Baseline passes; in disposable snapshots, making the BIDR predicate
unconditionally true fails `bira_wrap_not_taken` at cycle 860 twice. The
`bidr_zero_wrap_branches` mutation is retained in the adapter. Other relative
cases, all registers/conditions and indirect branch forms remain uncovered.

Relative BIRR/BDRR now also check the signed offset, zero-result non-taken path,
nonzero-result taken path and skipped fall-through stores. The pinned MAME
`M_BRR`/BIRR/BDRR macros provide the compatibility expectation. The focused
baseline passes. Removing the saved relative offset in disposable copies fails
`birr_branch_skips_fallthrough` at cycle 1080 twice; this proof is retained as
`lost_relative_bidr_offset`. Page-boundary relative BIRR/BDRR cases and the
remaining branch families still need coverage.

Conditional absolute BCTA now proves `=` false with positive CC and true with
zero CC, checking both the fall-through and target markers. RETC `=` false must
preserve the call frame so a subsequent RETC `>` can return after setting a
register signature. These behaviors follow the pinned MAME `M_BRA`/`M_RET`
contracts, with synthetic byte programs. The baseline passes. In disposable
copies, inverting CC equality fails `bcta_false_fallthrough` at cycle 1320
twice; making RETC unconditional fails `retc_false_then_true` at cycle 1425
twice. Both mutations are retained in the adapter. Conditional relative BCTR/BCFR,
BCTA, RETC, BSTA and RETE interrupt handling now have directed coverage.
Conditional BSFA, RETE enable timing and all CC/register combinations remain
uncovered.

Relative BCTR `=` with positive CC is checked as a non-taken fall-through;
BCFR `=` under the same CC must take and skip the fall-through store. The pinned
MAME `M_BRR` contract and instruction table define this inverse condition
relationship. Baseline passes. Reversing the false-branch predicate in a
disposable copy fails `bcfr_taken_skips_fallthrough` at cycle 1435 twice; the
adapter retains `bcfr_uses_true_predicate`.

Absolute BSTA `=` now checks positive-CC non-taken behavior and zero-CC call,
subroutine signature and return. The interrupt handler checks false RETE does
not return before its signature, then true RETE `>` resumes the interrupted
HALT sequence with one acknowledge. These are synthetic MAME-compatibility
scenarios, not physical interrupt timing measurements. The baseline passes.
Forcing BSTA on the false path fails `bsta_false_skips_subroutine` at cycle 1675
twice; permitting false RETE to return fails `rete_false_handler_path` at cycle
1890 twice. Both mutations are retained. RETE interrupt inhibit/enable edge
timing and interrupt arrival around conditional return remain untested.

Relative BSTR `=` now has distinct false and true targets: the false path must
skip its subroutine while the zero-CC path calls, writes its signature, returns,
and resumes at the fall-through. Relative BSFR `=` must call on positive CC and
return to its caller. Pinned MAME `M_BRR` and `M_RET` semantics define these
synthetic expectations. The focused baseline passes. Forcing false BSTR to call
fails `bstr_false_skips_subroutine` at cycle 1240 twice; reversing the BSFR
predicate fails `bsfr_positive_subroutine` at cycle 1295 twice. Both mutations
are retained in the adapter. Absolute BSFA and relative branch-to-subroutine
page-boundary cases remain uncovered.
