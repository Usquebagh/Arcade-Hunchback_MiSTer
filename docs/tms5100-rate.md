# Nominal speech sample enable

## Independent expectations before implementation

Pinned MAME CVS config uses an approximate 620000 Hz TMS5100 RC clock;
tms5110.h identifies output sample rate as chip clock divided by 80. The
normalized core's nominal master is 57272724 Hz. Thus speech logical sample
rate is 7750 Hz. This adapter models a rational synchronous enable; it does
not recreate or measure the original separate RC oscillator or its CDC.

After global reset, enabled edge n (one-based) is a sample edge exactly when
floor(n*7750/57272724) differs from floor((n-1)*7750/57272724). Intervals are
7390 or 7391 master edges. Compare to that absolute-time expression, not a
copy of the HDL accumulator. The enable is combinational before the active
edge and is gated low while reset is asserted. Reset clears phase at the next
edge and restarts the epoch. SPEAK and software datapath RESET do not restart
this free-running enable; only global reset does.

Tests must include sustained cadence/count, pulse width, phase-staggered resets
and reset immediately before a due pulse. No clock is generated from fabric
logic. This is a declared FPGA clock contract based on a software approximation,
not a PLL/fitting/timing/physical-clock/reference PASS. Actual engine job latency
and native CPU/ROM integration still need executed checks at this cadence.
