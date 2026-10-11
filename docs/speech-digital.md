# Speech CPU and serial-ROM interface

## Independent expectations before implementation

The initial digital contract is pinned MAME CVS `c806573e925ce00fe3e8d8fe417eba63f83275ce`
speech map and handlers, cross-checked against the supplied schematic page 2.
The actual second sound S2650 has 2 KiB program ROM and no mapped work RAM,
external SENSE, /192 adapted machine-step cadence and no connected IRQ.
The speech/LPC engine, physical level translators/PDC clocking, timing and
calibrated speech waveform remain missing. A synthetic status/bit-consumer
fixture is not a TMS5100 implementation or a game-speech accuracy reference.

| Accepted memory address | Read | Write |
| --- | --- | --- |
| 0000..07FF | Program ROM | Ignored |
| 1D00 | FF | Serial pointer low byte, shifted left 3; retain bits 15:11 |
| 1D40 | FF | Serial pointer high byte, shifted left 11 and truncated to 16 bits; retain bits 10:0 |
| 1D80 | Command bits 6:0 plus inverted TMS CTL read bit 0 in bit 7 | Ignored |
| 1DDC..1DDE | FF | Three normalized control latch bits, each inverted CPU data bit 7 |
| 1DDF | FF | Normalized PDC, inverted CPU data bit 7 |
| Others/nonmemory I/O | FF | Ignored |

CTL output is `{latch1,latch2,latch1,0}`: CTL2 and CTL8 share latch1 and
CTL4 uses latch2. Latch0 is retained separately; MAME does not drive CTL1 from it.
The drawing has shared CS/CTL1/status and transistor level translators. This
compatibility abstraction does not reproduce their bidirectional electrical
behaviour. PDC is a normalized digital state, not the board's extra flip-flop,
ROM-clock and level-translator circuit. Do not silently equate those boundaries.
The command input is explicitly seven bits; a future main-machine connection
must supply the low seven bits of its byte latch. Bit 7 belongs to status here.

`ctl_status` is the low bit returned by the speech engine's CTL read, not an
unconditional copy of its internal talk/busy flag. The pinned primary
[TMS implementation](https://github.com/mamedev/mame/blob/c806573e925ce00fe3e8d8fe417eba63f83275ce/src/devices/sound/tms5110.cpp)
distinguishes TEST TALK output, read-buffer output and input-bus states. A future
engine must supply the appropriate read bit for its PDC/direction state. This
interface does not implement those modes yet. Accessed 2026-10-12.

CPU reads complete one master edge after `req && ready`; output holds otherwise.
Downloads can initialize program ROM and a separate 4 KiB serial data ROM.
CPU cannot modify either ROM. Reset clears normalized control/PDC, bit pointer,
response-valid and bit data, but not ROMs. This is an explicit FPGA reset policy,
not a physical power-up claim. Writes are blocked under reset or ready low.

An external synchronous consumer requests a bit using `bit_req && bit_ready`.
On that edge `bit_valid` pulses with the selected data bit; data holds between
requests. Bits are LSB first. Reads clamp the current 16-bit pointer to 32768
bits, then increment; after 7FFF the stored pointer is 8000 and the following
read clamps to zero. A download to the same byte explicitly forwards new data.
An accepted CPU pointer write has priority and lowers `bit_ready` on that edge;
the consumer must retain/retry its request. This is a declared adapter handshake,
not a physical TMS/ROM timing measurement.

The bus test must exhaust all program bytes and all 32768 memory addresses,
all command/status combinations, all data values at each control/PDC address,
16-bit address-load equations and serial wrapping. It must test stalls, reset,
read holds, forwarding and simultaneous pointer/consumer requests. The actual
CPU test must execute downloaded synthetic code with no fake RAM: status/SENSE,
command, ROM-protection and unmapped reads appear as actual control/address
writes, followed by actual serial-ROM consumption through this interface.

The independent actual-CPU signatures, recorded before fixture execution, are:
1D00 writes A0 (SENSE high/IRQ inhibited), C2 (command 42/status 0), 42
(command 42/status 1), 20 (SENSE low), 5A (protected tail ROM byte), FF
(unmapped memory), FF (unmapped control I/O); then control writes
FF/00 to 1DDC, 80/01 to 1DDD, 80/01 to 1DDE, 80/01 to 1DDF.
The final pointer writes FF to 1D00 and 0F to 1D40 select bit 7FF8.
Actual serial reads must return byte A6 LSB first, wrap and return byte 5A
LSB first. A ready stall before the C2 write must not advance the signatures.

## Executed digital checks

`hunchback.speech.bus` passed exhaustive ROM protection/decode, 128 payloads
times both external CTL status values, every control/PDC data byte, all 256 by
256 pointer byte loads, two complete serial wraps and explicit handshakes.
Reset/holds/stalls and same-byte program/data forwarding are retained checks.
The new interface uses a seven-bit payload type instead of silently accepting
an unused command high bit; its first build had a lint WARNING/compile ERROR
for that unused bit. Those outcomes remain errors, not test or mutation catches.

`hunchback.speech.cpu` executes the actual synthesized VHDL CPU and actual SV
ROMs/control bus. All 17 independently specified signatures, /192 cadence,
ready stall, SENSE and external status changes, protected/unmapped reads and
serial data/wrap passed with no unreviewed Icarus `-Wall` findings. No speech
RAM, hierarchical initialization, mock CPU or TMS model replaces this assembly.

Eight new faults (status polarity, CTL8 source, serial order, wrap, low address
bit, pointer/consumer priority, PDC inversion and actual CPU command routing)
each fail the designated assertion twice after passing baselines. Final proofs
use the explicit CTL-status interface; the earlier named-interface proof is
retained separately. The full configured campaign is now 104 and was not run.
Focused audio/main/clock/memory/native CPU checks and lint passed. All 17 pinned
framework units passed; broad native unknown-state diagnostics remain blockers.

## Private unchanged-ROM observation

A disposable frozen-source, four-state probe loads the authenticated common
2 KiB program and 4 KiB prepared data region through the actual download ports.
It supplies nominal external 380 Hz SENSE and a constant-zero external CTL read
bit, with no serial consumer/LPC engine. Time-shifted real command payloads
3F,01,66,7F,4B are delivered after initialization with 576-edge header spacing.
This is an explicit diagnostic fixture, not an executed three-CPU machine or
an independent speech-frame/voice oracle.

At eight million master edges the probe observed 2918 command reads, eleven
control writes, fifteen PDC writes/seven rises and two ROM-pointer writes.
It emitted normalized CTL A then E around a phrase-address load, providing
evidence that the unchanged firmware reaches speech control code. No accepted
address or write data was unknown in this bounded observation. That result
does not audit all CPU states or remove the broad native/runtime warning.
No serial data was consumed and no voice was generated; the fixed external
CTL bit cannot reproduce TEST TALK/buffer/direction transitions or phrase
completion. Later commands in this fixture are not independently qualified.

The earlier 1.5-million-edge probe delivered some commands before the roughly
0.9-million-edge software initialization completed; it had no address writes.
Both reports remain observations. An intermediate unfrozen helper expanded a
numeric bound by prefix replacement and was interrupted; its partial output
is not coverage. The corrected bounded probe uses exact numeric replacement,
frozen source/dependency identities, tool/fixture hashes and untouched ROMs.
All reports, binaries, fixtures and traces remain ignored/private.

The normalized TMS command/direction controller now has standalone and actual
CPU checks; see [command expectations and limits](tms5100-control.md). The next
required subsystem is the actual TMC0281 LPC datapath and speech ROM consumer,
followed by connection to the main machine.
Physical CS/CTL1/PDC/ROM clock/aliases, RC frequency, coefficients, complete
speech firmware/reference waveforms, analog mixing/filters, CPU power-up and
MiSTer/Quartus qualification remain missing. No speech or RBF candidate PASS
is established by these digital tests.
