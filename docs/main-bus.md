# Main CPU bus and I/O contract

Expectations recorded before implementation, 2026-10-11. Reference is pinned
MAME cvs.cpp main_cpu_io_map, main_cpu_data_map and input_r, plus the adapted
S2650's one-edge read interface. This is MAME compatibility and a synchronous
implementation contract, not a board measurement or complete input schematic.

An accepted transfer is req AND ready. Memory reads/writes reach the existing
FLAG memory boundary; I/O cannot write memory. The response-space selector is
registered only on accepted reads, so subsequent addresses, writes, stalls and
idle clocks preserve the previous response. CPU CE qualifies req in the CPU;
the boundary must not repeat a write between enabled machine steps.

An extended read uses address bits 3:0: 0,2,3,4 select raw IN0..3, 6 selects
DSW2 and 7 selects DSW1; all other values return zero. Every accepted extended
read, including an unmapped port, latches char_page=address[7:6] and
char_mode=address[5:4]. Writes and stalled reads must not change those latches.
MAME explicitly doubts whether three or four low bits physically select ports;
the present four-bit compatibility choice remains an input accuracy blocker.
Raw bytes preserve polarity; physical coin/start/player/cocktail wiring is pending.

Extended writes latch scroll=255-data. Nonextended control reads sample the
external collision byte; data reads return zero and pulse collision_clear.
Control writes latch audio_command and pulse audio_trigger only on a rising
command bit 7; data writes latch video_fx. Outputs are commands to future
subsystems, not implementations of collisions, audio interrupts or video effects.

Reset clears I/O latches and event pulses but never RAM. Synchronous CPU reset
must run with reset_na high and ready high for opcode-zero priming before release;
reset_na is the separate asynchronous CPU reset input. Physical MiSTer reset/
loader sequencing and CDC are still unimplemented. No I/O or memory write is
accepted during reset; memory reads can prime the opcode. Synthetic integration
will download a program through the real ROM port, use the real /96 clock enable,
software-initialize status, and check stored signatures from real memory reads.

Planned faults: wrong I/O page bits, bank latch updated by writes, repeated
audio bit-7 trigger, and a live memory/I/O response selector. Each must fail
its named assertion twice in disposable framework snapshots. Integration also
checks request cadence, readiness stalls, FLAG views and returned input bytes.

Implemented checks: all 256 raw ports and side effects pass the standalone bus
test. The connected synthetic program produces 12 expected signatures followed
by 12 reads through actual system RAM and stores of those returned bytes. It
checks two independent character pages, palette/bullet and screen/attribute
views, one external sprite read/write, sense and command events. A disconnected
CPU FLAG fault must fail `connected_sprite_write`: a character-plane write is
incorrectly routed to a sprite chip before the readback signatures. Graphics and sound devices are
still external, and this synthetic program is not the Hunchback ROM.

Missing: complete opcode/cycle oracle, CPU unknown-state audit, display ports,
S2636 semantics, physical input decode, raster/collisions, sound, local game boot,
MiSTer/PLL/download integration and Quartus RAM/CDC/timing qualification.
