# TMS5100 normalized command controller

## Expectations recorded before HDL implementation

Reference: MAME `c806573e925ce00fe3e8d8fe417eba63f83275ce`,
`src/devices/sound/tms5110.cpp` PDC_set/ctl_r/read-bit operations and
`tms5110.h` command constants. This is a compatibility contract, not measured
TMC0281 pin timing. The HDL and synthetic oracle are independently written;
no upstream implementation is imported. The CVS driver uses the data callback
without a legacy table: reset must NOT schedule an initial dummy ROM read.

Commands ignore CTL1 and execute on a normalized PDC falling edge. Holding PDC
low, changing CTL alone or raising PDC must not execute a command. Direction
transitions consume an edge without decoding its CTL value:

| Command | First falling edge | Following falling edges |
| --- | --- | --- |
| 0 RESET | Clear command/buffer state; pulse datapath reset | Normal decode resumes |
| 2 LOAD ADDRESS | Arm address input | Capture the full next CTL nibble, pulse address load and schedule one dummy read |
| 4 OUTPUT | Arm buffer output | Enable buffer output, then return to input |
| 6 SPKSLOW | Pulse start with slow mode | Normal decode resumes |
| 8 READ BIT | Request one serial bit | Normal decode resumes after its response |
| A SPEAK | Pulse start with normal mode | Normal decode resumes |
| C READ BRANCH | Pulse branch event; cancel scheduled dummy read | Normal decode resumes |
| E TEST TALK | Arm talk output | Enable talk output, then return to input |

CTL reads return current input pins in input/armed states, the read buffer in
buffer-output state, and the external datapath talk-status bit in talk-output
state. Talk status alone must never replace the CTL read bit. READ BIT shifts
the previous nibble right and inserts the returned bit at bit 3. An address
load schedules a dummy bit: the next READ BIT consumes it without shifting;
SPEAK/SPKSLOW/RESET consume it before the corresponding datapath pulse.
Four input bits 1,0,1,1 therefore produce buffer nibbles 8,4,A,D.

The serial interface uses one outstanding request. Keep bit_req asserted until
bit_ready accepts it, then deassert it while awaiting bit_valid. Stalls cannot
duplicate a request, shift stale data or emit a premature start/reset. Global
reset cancels state and outstanding work; controller and ROM boundary must
share that reset. Ignore unsolicited responses. A command edge during serial
work is explicitly rejected with a sticky protocol_error diagnostic instead
of silently overwriting work. This finite latency adaptation differs from the
reference's instantaneous callback and needs integration coverage.

Only 0,4,A,E are reachable through the current CVS CTL2/CTL8 shared latch.
Other commands are tested on the generic normalized controller, but address
and branch outputs do not replace the actual CVS CPU's pointer writes. The
CVS reference leaves ROM address/branch callbacks disconnected. No physical
CS/CTL1/ROM-clock, speech RC clock, LPC coefficients/frame parser, lattice,
stop/drain status or PCM is implemented by this command controller. External
talk status in its synthetic test remains a fixture, not speech completion.

Important fault proofs must cover falling-edge decode, the extra direction
edge, buffer shift order and stalled request retention in disposable snapshots.
Compilation failures and timeouts are not successful detection.

The connected synthetic firmware must run on the actual VHDL S2650 and actual
speech bus. With command 42 and external datapath talk status held high, the
eight read/store signatures are C2,C2,42,C2,C2,C2,C2,C2: SPEAK input, TEST TALK
armed, talk output, input return, OUTPUT armed, buffer output, input return and
RESET input. CTL output directions at those reads are 0,0,1,0,0,1,0,0. Expected
CTL nibbles are A,E,1,E,4,0,4,0. Two SPEAK commands emit exactly two start pulses;
one RESET emits one datapath-reset pulse. A 512-master-edge stall at the talk
output read must preserve that direction and defer CPU acceptance. No ROM bits
are consumed because CVS wiring exposes only commands 0,4,A,E. This assembly
still uses an external talk-status fixture and is not an LPC/completion test.

## Executed checks, 2026-10-12

`hunchback.speech.control` passes command/CTL1 and all address-nibble transcripts,
all sixteen four-bit buffer values, separate armed/output/input directions,
dummy consumption before start/reset, stalled acceptance/response, unsolicited
responses, busy command rejection and shared reset in four pending/output
states. `hunchback.speech.control.cpu` passes the eight actual-CPU signatures,
CTL2/8 latch sharing, inverted PDC writes, two starts/one reset, /192 transfers,
512-edge ready stall and no incidental ROM consumption. The first standalone
run failed because its second CTL1 case inherited a high external talk-status
fixture; the fixture is now explicitly reset for each case. Assertions were
retained, and that failed result is excluded from passing evidence.

Five deliberate faults each fail their designated assertion reproducibly twice:
rising-edge decode, premature talk output, reversed bit-buffer shift, lost
stalled request and actual CPU status connected to raw talk status. The first
request mutation left bit_ready unused and failed compilation; that campaign
is retained as ERROR. The corrected mutation preserves a real ready input but
incorrectly accepts requests while PDC is low, and fails tms_request_retained.
The successful targeted campaign does not establish the full 109-mutation or
complete configured regression/candidate gate. All 17 pinned framework unit
tests passed after the adapter dispatch additions; the runner is unchanged.

Existing speech bus/CPU and focused main/audio/native CPU/memory/clock baselines
are retained. Block lint has zero unreviewed findings; actual CPU assembly
uses GHDL synthesis and Icarus four-state execution with no mock CPU/RAM and no
unreviewed compile findings. Broad native runtime unknown-state diagnostics
still block a candidate. Neither these tests nor the previous unchanged-ROM
observation establish a speech-frame, calibrated voice or physical bus oracle.

Next: TMC0281 frame decoding and coefficient tables, fixed-width excitation and
lattice/interpolation checks, stop/drain status, then actual controller/datapath
and serial-ROM arbitration under firmware. Audit the TMS5100 variant rather
than substituting TMS5110A tables from another game's core. A combined three-CPU
machine, physical clocks/CDC, analog mix, MiSTer integration and Quartus gates
remain required. No RBF or hardware-tested result is produced here.
