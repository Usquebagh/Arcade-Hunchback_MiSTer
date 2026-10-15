# Normalized speech sample sequencer

## Independent expectations before implementation

Reference is pinned MAME tms5110.cpp at
c806573e925ce00fe3e8d8fe417eba63f83275ce, normal interpolation path with
FAST_START_HACK enabled. This compatibility profile includes that explicit
software start approximation and excludes perfect-interpolation/digital-output
hacks. It is not cycle-exact TMC0281 pin timing. External sample_tick advances
logical sample time; a future clock adapter must establish the nominal 620000/80
Hz cadence independently. A clock fixture is not a physical RC measurement.

Reset sets interpolation period IP=0, parameter counter PC=0, subcycle=0,
normal subcycle reload=1, old silence/unvoiced flags=1, RNG=1FFF and pitch
count/current parameters/targets=0. Every logical sample advances subcycle;
at new subcycle=3 reload and increment PC. At PC=12/new subcycle=2 reload,
set PC=0 and increment IP modulo eight. Normal periods are 25 samples after
the reset's initial extra subcycle; slow reload=0 gives 38 samples per period.
Eight steady periods are therefore 200 or 304 samples. SPEAK changes reload
and sets SPEN/TALK immediately, old flags and parameter-zero masks, retaining
counter/filter/target history. It does not restart the sample phase.

At IP=7/PC=12 wrap, latch TALKD from TALK. If TALK was zero and SPEN set, set
TALK for the next latch; the fast-start profile normally sets TALK on SPEAK.
CTL talk status is SPEN OR TALKD. Idle samples emit active_sample=0; the future
audio assembly must emit -1 and advance counters without updating RNG/pitch.
Active samples at IP=0,PC=12,subcycle=1 request/apply a new decoded frame and
skip interpolation on that sample. Energy index F clears SPEN/TALK, while
TALKD remains until the next IP=7 wrap: seven periods of drain, 175 normal or
266 slow samples including the wrap sample. Silence is energy index zero.

On active subcycle=2 update only PC's parameter: PC0 energy, PC1 pitch,
PC2..11 K1..K10. Use signed floor shift counts [0,3,3,3,2,2,1,1] indexed by IP.
Inhibit interpolation except IP0 when old/new unvoiced classifications differ
or old silence changes to nonsilence. Parameter-zero masks override the updated
parameter, with the high-K mask applying to K5..K10 only. A newly parsed frame
clears the all-parameter mask and adopts its unvoiced high-K mask. Silence/stop
retain raw pitch indices as established by the frame parser.

Excitation uses the old unvoiced flag: +64 or -64 from pre-update RNG bit zero,
or a signed TMC0281 chirp entry indexed by pitch count clamped at 51. Advance
the 13-bit LFSR twenty times for each active sample with taps 12,3,2,0; idle
does not advance it. Increment pitch count after the sample and wrap at the
updated current pitch, or while pitch-zero is asserted. Pitch-zero is set at
an active IP7 wrap with inhibit and cleared at active IP0/PC0/subcycle2 before
that sample's count update. Old energy/pitch classification is latched only
at active IP7 wrap. These ordering details need independent transcript tests.

The finite-latency frame handshake holds a pending logical sample until a
decoded target arrives, then emits one parameter_valid pulse. Coefficient and
frame decode work is not a mock for firmware or serial ROM. Unexpected sample
ticks while pending and SPEAK overlapping a pending parse are diagnosed;
unsolicited frame responses are ignored. Shared reset/clear cancels pending
work. These latency collisions remain integration/reference gaps until checked.
Tests must cover normal/slow counts, phase-retaining SPEAK, idle/active RNG,
voiced/unvoiced/silence/repeat/stop transitions, parameter update ordering,
inhibit/pitch-zero, delayed frames, unsolicited responses and cancellation.
