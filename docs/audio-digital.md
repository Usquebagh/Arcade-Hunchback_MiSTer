# Audio CPU and digital controls

Expected compatibility behaviour recorded before implementation: pinned MAME CVS
`c806573e925ce00fe3e8d8fe417eba63f83275ce`, audio map/handlers and CPU configuration.
The user-supplied v1.4 schematic page 2 was visually inspected as a full sheet and
at command, CPU, DAC and decode regions. Its upper UK5 processor has 128-byte RAM,
command/IRQ wiring and DAC/discrete controls; lower UC5 is the speech processor.
Net names are reverse-engineered and the drawing warns of possible errors.
The inspected PDF SHA-256 is
`95a23d34d151344f3611500297e6aaf2ed091cc45562b63917870b62de92616d`.

## Initial contract

An actual adapted S2650 uses a /192 machine-step enable (three /64 audio clocks),
external SENSE and interrupt vector 03. CPU requests accepted with ready high have
one master-edge read latency. Read output holds until another accepted read.
Downloads can initialize 4 KiB ROM; CPU writes cannot change it. RAM power-up is
unspecified and RAM retains contents across reset. No hierarchical initialization
or mock CPU replaces the connected test.

| Accepted memory address | Read | Write |
| --- | --- | --- |
| 0000..0FFF | Audio program | Ignored |
| 1000..107F | Actual 128-byte RAM | RAM |
| 1800 | Latest main command byte | Ignored |
| 1840 | FF | Eight-bit DAC/control byte |
| 1880..1883 | FF | Selected four-bit DAC latch, data bit 7 |
| 1884..1887 | FF | Selected discrete control latch, data bit 0 |
| Others/nonmemory I/O | FF | Ignored |

These are exact 15-bit MAME windows, not an audit of physical aliases. A command
event sets pending IRQ; command read does not clear it. A rising CPU INTACK clears
pending IRQ once, even if the adapted CPU holds INTACK across master edges. A
coincident new event wins, and a later event during held INTACK stays pending.
This event-priority policy is an FPGA/MAME compatibility contract, not a measured
74LS74 clear/clock coincidence. Command data is supplied from the main command
latch; it must be stable and synchronous to this interface. No CDC is implied.

Reset clears IRQ, acknowledgement history, DAC/discrete latch values and their
write pulses; it does not erase RAM or ROM. Downloads and opcode-zero read priming
remain available while reset holds. Writes/strobes are blocked by reset or ready
low, and decoded strobes last one master edge. SENSE is external here: the drawing
and pinned MAME note a measured approximately 380 Hz RC oscillator; no nominal
digital oscillator or analog timing proof is introduced in this milestone.

## Independent executed checks

The standalone bus oracle enumerates all 32768 memory addresses and all
downloaded ROM bytes/RAM words, read hold, ROM protection, download forwarding,
reset retention, stalls and every data value at every DAC/discrete latch address.
IRQ checks include event/ack coincidence, held acknowledgement, command-read
retention and ignored reset events. These expected values come from the table and
explicit event contract, not sampled RTL output.

A synthetic program executes the actual VHDL CPU with actual audio bus/RAM,
/192 clock enable, a ready stall, SENSE, HALT/vector/RETE and command reads. It
produces nine independently specified RAM signatures and real DAC/discrete strobes.
Both raw latch paths must distinguish 80 from 01; a test using only FF/00 cannot
resolve the data-bit conflict. Native unknown-state diagnostics remain blockers.
Both new baselines and focused lint passed. Six new faults (wrong DAC/discrete
data bit, ignored ready, reversed ack history, RAM alias and wrong CPU vector)
each fail their designated assertion reproducibly twice in disposable framework
snapshots. The configured full campaign is now 90; it was not rerun in full.
Existing main connected bus, native CPU bus and memory checks passed; the broad
native runtime diagnostic remains a required WARNING. Framework unit tests passed.

## Reference gaps

The latch data-bit question is resolved: the drawing labels the 74LS259 input
`SP_D0`, and MAME masks writes to the discrete trigger window (`0x1884..0x1887`)
with `data &= 1`. The RTL samples `din[0]` for those addresses. MAME's bit-7
sampling applies to the separate four-bit DAC window (`0x1880..0x1883`), not to
the discrete latches ([MAME CVS driver](https://github.com/mamedev/mame/blob/master/src/mame/misc/cvs.cpp#L3274-L3292)).
The four resistor weights still need a separate audit before raw latch order can
be interpreted as calibrated analog amplitude. The physical control/filter/mixer
response and board recordings also remain open.

The audio board has a separate oscillator. Shared FPGA enables are implementation
choices; relative phase/drift and CDC need integration checks. Neither DAC path
produces PCM in this milestone. ICL8038/noise/envelopes/filter/mixer, speech CPU,
TMS5100/ROM addressing, gain and board recordings remain missing. MAME's beeper
placeholders cannot justify their accuracy. Audio/audio-reference, complete CPU,
main/game/video/MiSTer/PLL/constraint candidate blockers remain required.

## Private firmware observation

An ignored four-state Icarus probe loads the unchanged authenticated audio ROM
from image offsets 8000..8FFF through the real downloader and supplies a nominal
380 Hz SENSE fixture. It replays selected main-game command pairs with documented
time-shifted spacing. Command I/O is independent of main CPU FLAG; filtering it by
FLAG would omit valid commands. This is a serial diagnostic stimulus, not a
connected main/audio board simulation or an independent expected sound waveform.
The probe records actual RAM/control writes and native unknown data separately.
It must not replace candidate checks, remove unknown-state/reference blockers or
produce an audio-accuracy PASS. No PCM, waveform or speech is synthesized here.

The final three-pair probe (40/E6, 40/FF, 40/CB) ran 1.5 million master edges:
three IRQ acknowledgements, 56 byte-DAC writes, 204 four-bit latch writes and
156 discrete latch writes. None of those control values was unknown. Six work-RAM
writes were unknown; their raw records remain a diagnostic limitation. A prior
single-pair CB probe had eight unknown RAM writes. Different stimuli are not
replacement expected streams; neither run has an independent audio-ROM oracle.

The subsequent [connected assembly milestone](audio-assembly.md) executes the
actual main/audio CPUs and unchanged ROMs together. Its native read trace also
identifies two unknown indexed addresses behind the work-RAM observation. The
synthetic wrapper does not resolve that power-up/reference gap.

The [wiring audit](audio-wiring.md) supports keeping byte significance as drawn
and shows that every executed four-bit game write was zero; physical gain/weights
remain gaps. Later work added
the third CPU, speech controller and numeric TMS datapath and connected them in
the three-CPU machine. Speech is audible on hardware. A schematic-derived
discrete-audio approximation is now integrated; its effect triggers, FM law,
noise source, physical protocol, exact voice fidelity and calibrated analog
mix remain incomplete. See [the circuit model](audio-circuits.md).
