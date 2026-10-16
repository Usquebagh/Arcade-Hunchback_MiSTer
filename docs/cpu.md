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

Native CPU startup diagnostics are checked separately from functional behavior.
The required `hunchback.cpu.runtime_diagnostics` gate accepts either a clean run
or the exact reviewed 21-warning profile before the first fetch at address 4,
after software initializes CPSL and PPSL. It rejects changed or additional
warnings, any warning at or after that marker, and a missing marker. This is a
bounded synthetic software-startup contract; it does not establish physical
power-up state. Do not force MAME's deterministic reset image onto hardware
state merely to hide warnings; the manufacturer guarantees less reset state.

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
as `overwritten_nested_return` in the BDSM adapter. This specific case covers
two active stack entries; eight-entry fill/unwind coverage is added below.
Overflow and interrupt/subroutine interaction, full opcode/cycle differential
and native unknown-state diagnostics remain open.

The same bench now checks absolute BIRA/BDRA with zero-wrap non-taken and
nonzero taken cases against the pinned MAME instruction macros and CPU branch
decode. Baseline passes; in disposable snapshots, making the BIDR predicate
unconditionally true fails `bira_wrap_not_taken` at cycle 860 twice. The
`bidr_zero_wrap_branches` mutation is retained in the adapter. Other relative
cases, all registers/conditions and absolute indirect branch forms remain
uncovered.

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
RETE enable timing and all CC/register combinations remain uncovered; absolute
BSFA coverage is added below.

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
are retained in the adapter. Relative BSTR page-wrap target coverage is added
below; BSFR and conditional relative boundary cases remain uncovered.

An eight-call absolute subroutine chain now fills all eight documented return
stack slots, writes a deepest-level signature, and unwinds to a separate caller
signature. The independent contract is the pinned MAME three-bit stack pointer
mask and the implementation's eight-entry stack; stack overflow is not inferred
from this test. The focused baseline passes. Aliasing stack writes to four slots
in a disposable copy fails `stack_depth8_outer_return` at cycle 1280 twice; the
mutation is retained as `stack_depth_alias_four`.

Absolute BSFA `=` now calls on positive CC, returns through its saved frame,
and skips its distinct target on zero CC. Its synthetic expectation follows
the pinned MAME absolute BSFA predicate. Baseline passes; reversing that
predicate fails `bsfa_false_subroutine` at cycle 1245 twice. The targeted fault
is retained as `bsfa_predicate_reversed`. Conditional absolute subroutine
coverage is directed; other condition codes, indirect forms and page-boundary
cases remain open.

An unconditional relative BSTR at 1FFE now crosses the 1FFF page boundary and
must reach address 0010, write its signature, return, and fetch address 0000.
Directed BIRR and BDRR programs also verify their increment/decrement decisions
and page-wrapped target at 0010. These are synthetic bus-memory checks against
the pinned MAME instruction semantics; they are not board measurements. The
focused bus baseline passes. Dropping the BSTR target offset fails
`bstr_page_wrap_target`; saving `iar+1` without page wrapping fails
`bstr_page_wrap_return` at cycle 1295 in two disposable copies. The adapter
retains both targeted mutations. Reversing the BIRR increment fails
`birr_wrap_not_taken`, and reversing the BDRR decrement fails
`bdrr_zero_not_taken`; both direction mutations are retained in the adapter.
Indirect and conditional relative boundary cases remain open.

The bus bench also places BCFR `=` at 1FFE with a positive condition code and
checks its taken target at 0010 after the relative operand wraps the page. This
combines the documented false-condition predicate with the independently
checked page-relative base. The focused bus baseline passes. Existing retained
mutations separately reverse the BCFR predicate and remove relative page
wrapping. A dedicated `bcfr_relative_target_plus_one` mutation now adds one to
relative conditional-branch displacement; it fails `bcfr_page_wrap_target` at
cycle 843 in both repeats (expected 6C, observed 40). Other conditional relative
boundary combinations remain uncovered.

Focused checks after these bench-only changes passed `hunchback.cpu.bus`,
`hunchback.cpu.alu`, `hunchback.cpu.edge_regressions`,
`hunchback.cpu.synthesis`, and `hunchback.cpu.cold_self_xor`. The required
`hunchback.cpu.runtime_diagnostics` check now passes by accepting only its exact
reviewed startup warning profile before the first fetch at address 4, after
`CPSL` and `PPSL`; the 21 warnings are timestamp-pinned and it requires no
warnings after that marker. Full opcode/cycle differential,
physical board timing, I/O decode, video, inputs, audio, game-level behavior,
Quartus timing, and actual MiSTer checks remain incomplete.

Startup audit: the Signetics user manual says the 2650 has no internal startup
procedure, requires RESET for at least three clocks, then fetches address zero.
The bus test now holds reset for exactly three clocks; `hunchback.cpu.bus`
passes. Its startup code clears and sets status before directed conditional
tests. An isolated diagnostic copy with only the synthesis-excluded instruction
Trace process removed drops the six `TO_INTEGER` warnings (from printing
unknown PSL condition bits), but still reports fifteen vector-comparison
warnings from early CPU operation. The VCD shows unknown PSL, instruction
register and return-address-stack values before software initialization. All 21
warnings occur before the address-4 marker at 277 ns: 15 vector equalities at
0ms, 5ns, 15ns, 25ns, 131ns, 232ns and 237ns; six conversions at 46ns, 66ns,
86ns, 106ns, 126ns and 247ns. No warnings occur after the marker. The
diagnostic now reports PASS only for that exact timestamped profile or a clean
run; any changed warning, missing marker, or warning at/after initialization
yields WARNING/ERROR. Two disposable injections of a post-marker warning were
rejected. It does not suppress simulator output. This validates the
software-initialized synthetic CPU path; it does not qualify power-up state on
physical hardware.

## Indirect control-flow regressions, 2026-10-16

The bus bench now verifies a relative BCTR indirect operand resolving through
pointer bytes at 0010/0011 to target 0200, an absolute BCTA indirect branch to
0200, and an absolute BSTA indirect call through the same pointer followed by a
RETC and caller-resume signature. The expected pointer-byte order and target
are synthetic S2650 bus scenarios based on the pinned MAME instruction behavior
and manufacturer addressing description; they are not board measurements. The
focused bus baseline passes. A disposable `indirect_control_target_plus_one`
mutation advances the resolved control target by one byte and fails
`relative_indirect_target` at cycle 481 twice (expected 6B, observed 40). The
`absolute_indirect_branch_bypasses_pointer` mutation ignores the indirect bit
and fails `absolute_indirect_branch_target` at cycle 481 twice (expected 7C,
observed 40). Other absolute-indirect condition variants, additional pointer-
page boundary/indexed-indirect combinations and hardware bus timing remain open.

Direct and indirect BXA R3 indexing are now checked separately. The direct case
uses base 0200 with R3=1 and must execute at 0201; the indirect case resolves
pointer 0010/0011 to 0300, adds R3, and must execute at 0301. Expectations are
synthetic CPU-bus behavior from the pinned MAME S2650 model and manufacturer
instruction description, not board measurements. The focused bus baseline
passes. `bxa_direct_index_ignored` fails `bxa_indexed_target` at cycle 539 in
both repeats (expected 6D, observed 40); `bxa_indirect_index_ignored` fails
`bxa_indirect_indexed_target` at cycle 602 in both repeats (expected 7D,
observed 40). Both mutations are retained in the adapter. Indexed BXA is
covered; indexed-indirect pointer-page boundaries, other indexed-indirect
combinations and hardware bus timing remain open.

Direct and indirect indexed BSXA calls are now checked through both the
subroutine target and the caller's return signature. The direct call resolves
0400+R3; the indirect call resolves pointer 0010/0011 to 0400, then adds R3.
These are synthetic MAME/manual-compatible CPU expectations, not board
measurements. A disposable `bsxa_direct_index_ignored` mutation fails
`bsxa_indexed_subroutine` at cycle 675 in both repeats (expected A6, observed
40). It is retained in the adapter. The indirect call/return path passes, but
its shared BXA/BSXA resolution logic is only mutation-checked at the earlier
BXA assertion. Indexed-indirect pointer-page boundaries, remaining indexed-
indirect combinations and hardware bus timing remain open.

## Indirect interrupt-vector regression, 2026-10-16

The synthetic bus now exercises an indirect vector `B0`: its low seven bits
select pointer bytes at page-zero addresses 0030/0031, which contain handler
address 0050. The actual CPU must enter that handler, write its signature, and
return after HALT to complete a second signature. This follows the Signetics
Instructor 50 User's Guide description of the interrupt vector's indirect bit
and the two-byte handler address stored at the selected vector location
([interrupt mechanism](https://www.vintagecomputer.net/fjkraan/comp/divcomp/doc/SigneticsInstructor50UserGuide.pdf)); it is a processor-manual expectation, not a CVS board measurement.

The initial regression exposed a defect: indirect entry formed 4030 from stale
CPU bus data instead of reading the selected page-zero pointer. The CPU now
starts its normal indirect fetch at the address carried by `ivec(6:0)`. The
focused bus regression passes. The retained `interrupt_indirect_vector_uses_stale_bus`
mutation restores the old source and fails `interrupt_indirect_vector_handler`
at cycle 2404 in both repeats (expected D8, observed 40). Native CPU ALU, edge,
cold-start, synthesis, runtime-diagnostic and lint checks pass; main-bus and
connected-CPU checks pass as well. Other vector values, nested/edge-timed IRQ
cases and physical interrupt-bus timing remain open.

## Indirect pointer page-wrap regression, 2026-10-16

The actual CPU now resolves an absolute indirect branch whose two-byte pointer
straddles the end of an 8 KiB page: the high byte is read from 1FFF and the low
byte from 0000, producing target 0200 and the expected store signature. This
is a synthetic S2650 addressing expectation based on the pinned MAME behavior
and the manufacturer page-addressing description; it is not a board timing
measurement. The focused CPU bus baseline and RTL lint pass. A disposable
`indirect_pointer_second_byte_leaks_page` mutant replaces page-aware pointer
increment with linear increment and fails
`absolute_indirect_pointer_page_wrap` at cycle 2515 in both repeats (expected
7C, observed 40). Other pointer/index combinations and hardware bus timing
remain open.

## Absolute indirect indexed data-read regression, 2026-10-16

LODA R1 now has a directed indirect-indexed read case: pointer 0010/0011
resolves to 0300, R1 contributes an index of one, and the actual CPU loads byte
6D from 0301 into R0 before storing the signature. This is a synthetic S2650
instruction expectation based on the pinned MAME behavior and manufacturer
addressing description, not a board measurement. The focused CPU bus test and
RTL lint pass. A disposable `indirect_loda_ignores_index` mutant removes the
post-pointer index addition and fails `absolute_indirect_indexed_load` at cycle
947 in both repeats (expected 6D, observed 40). That mutant covers the mode-3
indexed case; pre-increment and pre-decrement are checked separately below.

Indirect LODA pre-increment and pre-decrement cases now also verify the
effective data address and updated R1 value: starting at 1, pre-increment reads
0302 and leaves R1=2; pre-decrement reads 0300 and leaves R1=0. The CPU bus
baseline and lint pass. `indirect_loda_preincrement_uses_old_index` substitutes
the old index for the incremented value and fails
`absolute_indirect_preincrement_load` at cycle 1025 in both repeats (expected
6E, observed 40). `indirect_loda_predecrement_uses_old_index` fails
`absolute_indirect_predecrement_load` at cycle 1103 in both repeats (expected
7B, observed 40). The distinct pointer-wrap cases for these data-access modes
remain uncovered.

The indexed LODA effective address also wraps within the 8 KiB page: pointer
target 1FFF plus R1=1 reads address 0000 (the known startup opcode 75), while
2000 contains guard value 40. The CPU bus baseline and lint pass. A disposable
`indirect_loda_index_add_leaks_page` mutant uses linear addition and fails
`absolute_indirect_indexed_page_wrap` at cycle 1171 twice (expected 75, observed
40). This complements the separate test for the second pointer byte wrapping
from 1FFF to 0000.

Indirect pre-increment and pre-decrement effective-address wrapping now have
separate checks too. Both use a pointer target of 1FFF and an updated index of
one; each must read address 0000 and retain R1=1. CPU bus and lint baselines
pass. `indirect_loda_preincrement_add_leaks_page` fails
`absolute_indirect_preincrement_page_wrap` at cycle 1249 twice (expected 75,
observed 40); `indirect_loda_predecrement_add_leaks_page` fails
`absolute_indirect_predecrement_page_wrap` at cycle 1327 twice (expected 75,
observed 40). These are synthetic CPU addressing tests, not physical bus
measurements.

## Conditional absolute-indirect branch regression, 2026-10-16

BCFA `=` with a positive condition code now follows a page-zero pointer at
0010/0011 to target 0200. The fall-through marker must remain untouched and
the target writes its signature. This joins the independently covered
false-condition predicate and absolute-indirect resolution in one actual-CPU
bus case; expectations are synthetic MAME/manual-compatible behavior, not CVS
board measurements. The focused `hunchback.cpu.bus` and RTL lint checks pass.
The `bcfa_indirect_predicate_reversed` disposable mutation passes its untouched
baseline and fails `bcfa_indirect_skips_fallthrough` at cycle 509 in both
repeats (expected 40, observed 11). Other conditional absolute-indirect
condition selectors, target/page-boundary combinations, and physical bus timing
remain open.

BCTA `>` with positive condition code now also resolves an indirect pointer to
0200; its fall-through marker stays untouched and the target records 44. This
is the synthetic instruction condition rule `selected condition == PSL CC`,
based on the pinned CPU model/manual, not a board measurement. CPU bus and lint
pass. The `bcta_indirect_greater_uses_equality` mutation has a passing baseline
and fails `bcta_indirect_greater_skips_fallthrough` at cycle 512 in both repeats
(expected 40, observed 11). BCFA/BCTA other CC selectors, absolute-indirect
page-boundary targets, and physical bus timing remain uncovered.
