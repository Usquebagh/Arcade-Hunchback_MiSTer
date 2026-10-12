# Normalized speech lattice and PCM quantizer

## Expectations recorded before implementation

Compatibility reference: pinned MAME tms5110.cpp at
c806573e925ce00fe3e8d8fe417eba63f83275ce, matrix_multiply/lattice_filter/
clip_analog. Its comments identify a hardware multiplier-LSB approximation.
This profile reproduces the numeric software contract; it does not resolve
physical TMC0281 rounding, analog gain or pin waveform fidelity.

Coefficients are signed ten bits. Matrix arguments are signed ten and signed
fifteen bits, despite the upstream prose calling the second argument fourteen:
the implementation explicitly wraps at +/-16384 modulo 32768. Multiply and
arithmetically shift right nine. No forced multiplier LSB is added. Initialize
u10 from previous energy times signed excitation divided by eight with floor
rounding. Energy is unsigned seven bits; excitation is signed eight bits.

For i=9 down to 0, u[i]=u[i+1]-matrix(K[i],x[i]). For i=9 down to 1,
x[i]=old_x[i-1]+matrix(K[i-1],u[i-1]); finally x[0]=u[0]. Use the previous
sample's energy for excitation scaling, then retain this sample's input energy
for the following sample. All K inputs and that next energy are captured at
request acceptance; input changes during processing cannot alter this sample.
Initial/reset x and previous energy are zero. SPEAK is not an automatic filter
reset: that policy belongs to the future speech scheduler.

The HDL may store intermediate/delay values modulo 32768 because every later
matrix use and final output applies that modulus. The independent test oracle
must use wider signed sums and wrap only matrix inputs/final output, demonstrating
observable equivalence rather than duplicating the HDL's modular recurrence.
Arithmetic shifts are floor division, including negative nonmultiples.

Normalize final u0 to signed fifteen bits. Clamp it to [-2048,2047], discard
four low bits, and expand the retained bits to signed sixteen-bit PCM as in
the software speaker path. For an in-range raw r, PCM bit layout is
{r[11:4],r[10:4],r[10]}; out-of-range values saturate to 8000 or 7FFF. This
quantizer is a compatibility transform, not a calibrated analog mixer.
Exhaustively check all 32768 raw values against arithmetic clip/floor/expand.

One request may be outstanding. Accept only while ready, pulse sample_valid
exactly twenty master edges after acceptance, then hold raw/PCM until another
completion. Requests during busy set a sticky diagnostic without replacing
captured parameters. Shared reset/clear cancels processing and resets outputs,
delay and previous energy. Exercise reset at every pipeline position, impulse,
constant and changing excitation, coefficient extremes and table-derived
sequences, all energy/excitation input pairs, hold and rejected requests.

Important fault proofs must detect energy-delay removal, shift/rounding errors,
wrong lower-lattice feedback index, using live rather than captured K, and
broken saturation/quantization. No generator cadence/interpolation/LFSR/chirp/
frame consumption/stop-drain/CTL talk status/voice or physical timing is
established by this standalone numerical component.

## Executed checks, 2026-10-12

The actual filter/quantizer passes all 32768 raw PCM values, all 128 unsigned
energy by 256 signed excitation combinations, 4096 table-derived coefficient
histories, 64 signed-extreme cases, changing live inputs after acceptance,
exact twenty-edge completion/one-edge valid, hold and busy rejection. Reset or
clear at every in-flight pipeline position cancels the job and reproduces
fresh filter behaviour. The independent model uses wider sums and applies
wrap only at matrix arguments and final output; the HDL stores modular state.

Five faults each reproduce their designated assertion twice after passing
baselines: current instead of previous energy, wrong excitation divisor,
wrong feedback index, live upper coefficients and premature PCM saturation.
Focused block lint has zero findings. The full configured campaign is now 120
and has not run. These are numeric software-compatibility checks; upstream
hardware multiplier-LSB approximation and physical audio/reference gaps remain.
No standalone filter PASS establishes a voice, frame scheduler, TMS talk-status
completion, integrated three-CPU machine, MiSTer interface or Quartus candidate.
