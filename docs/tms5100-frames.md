# TMC0281 frame decoder and numeric ROMs

## Expectations recorded before implementation

Pinned reference: MAME `c806573e925ce00fe3e8d8fe417eba63f83275ce`,
`tms5110.cpp` parse_frame/read_bits and `tms5110r.hxx`
T0280B_0281A_coeff. These establish a TMS5100/TMC0281 compatibility profile,
not physical CVS timing or a calibrated voice reference. The coefficient
source identifies decap/patent verification; that claim has not independently
been audited here. TMS5110A pitch/LPC tables are different and must not be used.

The serial ROM supplies bits LSB first within bytes. Each field is assembled
MSB first from those successive bits. A frame begins with four energy bits.
Energy 0 (silence) or F (stop) ends after four bits; pitch and coefficient
indices retain their previous values. Otherwise read one repeat bit, five
pitch bits, and, unless repeat is set, K indices of widths
5,5,4,4,4,4,4,3,3,3. Pitch 0 ends after K4. Frame lengths are therefore
4 (silence/stop), 10 (repeat), 28 (unvoiced) and 49 (voiced) bits.

Repeat retains all ten raw coefficient indices. Unvoiced nonrepeat updates
only K1..K4 and retains K5..K10. The effective high-coefficient zeroing flag
belongs to a nonsilent frame with pitch 0; it must not destroy the raw indices.
The reference clears that flag before parsing every frame, including silence
and stop. A voiced frame, unvoiced frame and voiced repeat must reactivate the
retained upper six indices. Stop detection alone does not implement talk-status
drain, interpolation or filter tail.

The parser stages fields and commits atomically when the frame is complete.
Its output valid is a one-edge pulse, with values holding afterward. One
outstanding serial request is allowed; retain requests under ready stalls,
await only accepted responses, and ignore unsolicited valid pulses. Shared
reset or clear cancels staged work and clears output indices. A request made
while busy is rejected with a sticky diagnostic; clear/reset cancels it.
The ROM boundary and parser must share clear cancellation before reuse if a
response is outstanding. This normalized latency/reset policy is an FPGA
contract, not physical ROM-clock emulation.

Tests must use an independently encoded serial transcript and arithmetic
field oracle; no HDL expected-value extraction. Exercise every energy/pitch/
repeat combination, all legal K indices, all frame lengths, output hold,
acceptance/response stalls, reset/clear during each kind of partial frame,
repeat retention and silence/stop followed by more frames. Exhaust the numeric
ROM's energy, pitch, K, chirp and interpolation addresses, including explicit
zero defaults for invalid K addresses. A real speech-bus assembly must read
downloaded synthetic bytes, cross byte/end-of-ROM boundaries and retain CPU
pointer-write priority. Synthetic bits are not a voice/game waveform oracle.

Important mutations: reverse field assembly, consume silence tail bits, clear
retained high K indices, lose a stalled bit request and substitute a TMS5110A
table value. Baseline must pass and each semantic mutant fail its assertion
twice; tool errors are not detection.

## Executed checks, 2026-10-12

The frame parser passes all 1024 energy/pitch/repeat combinations, all legal
K index values, all four frame lengths, atomic hold/commit, response/acceptance
stalls, unsolicited responses, busy rejection and reset/clear after every
partial bit position with and without an outstanding response. The explicit
voiced/unvoiced/voiced-repeat regression preserves and reuses K5..K10.

Numeric ROM checks exhaust all addresses, signed values, invalid defaults and
4096 simultaneous address combinations. The reference facts share the same
pinned upstream numbers; this proves address/transcription/sign behaviour,
not independent physical coefficient provenance. Imported numeric data retains
its original BSD notices and separate license.

The real serial-memory/parser assembly consumes 1027 downloaded synthetic
frames across byte and 7FFF-to-zero wrap, verifies the independent field
values/counts, relocates a partial pitch field through two priority-winning
CPU pointer writes, retries the request and cancels an already-issued response
under shared reset. Its first dispatch returned KeyError/ERROR because the new
source mode was selected too late; the adapter is corrected without changing
assertions. This is a real ROM/parser assembly with synthetic CPU transactions,
complementing the existing actual-S2650 speech tests.

Six faults reproduce twice. Five match their designated assertions in the
initial targeted campaign. ROM-input inversion also failed twice, but its
inverted repeat bit caused the independent length assertion before the field
assertion originally designated; that campaign remains FAILED. The corrected
designation is tms_frame_rom_length, verified in a separate successful proof
with a passing baseline. No test assertions were weakened. Full configured
regression/mutations, speech-frame cadence/interpolation/excitation/stop-drain,
unchanged speech firmware/voice, physical protocol, three CPUs, MiSTer and
Quartus remain incomplete. See the [numeric lattice](tms5100-lattice.md).
