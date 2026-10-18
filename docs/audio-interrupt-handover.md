# Audio interrupt investigation handover

**Status: work in progress; the interrupt fault is not confirmed fixed on hardware.**

The latest engineering diagnostic image is `v261018-001032`, deployed as
`M:\\_Arcade\\cores\\hunchback_20261017.rbf`. Its SHA-256 is
`201A2C14D014C560E438E35F3B19470DFCC2A3C5B26D74A070A6FCA0DA4A418A`.
The published RBF at `releases/hunchback_20261017.rbf` is synchronized to this
same image. The paired MRA still resolves to `hunchback_20261017`. This is an
engineering diagnostic image with the OSD Audio Probe option present and
defaulting Off; bell, walking, and jumping effects are still not working on
hardware.

## Hardware observation

The confirmed six-bar readout is: command trigger lit, audio IRQ lit, INTACK
black, nonzero command lit, interrupt-inhibit black, and heartbeat pulsing.
Thus hardware raises an unmasked audio interrupt with a nonzero command, but the
audio CPU does not acknowledge it. This localizes the failure to CPU interrupt
acceptance or its state/handshake boundary; the mixer, gain, DC blocker, discrete
effect generators, ROM download offset, and PSU-II masking do not explain this
specific missing-INTACK observation.

## RTL audit and simulation

The S2650 asynchronous reset branch cleared IAR, stack pointer, and PSU-II, but
did not initialize the control state, registered request handshake, or INTACK.
The wrapper holds `reset_na` low during core reset, so the later synchronous
`state <= sOPCODE` assignment was not guaranteed to run during that interval.
The current work initializes `state` to `sOPCODE`, `req_i` low, and `intack` low
in the asynchronous reset branch. This is a plausible simulation/silicon
divergence source, not yet a hardware-confirmed root cause.

The audio-command register is explicitly cleared by the main-I/O synchronous
reset. The earlier interpretation that the yellow sticky probe bar proves it
was nonzero before any write was incorrect: the authenticated startup bus trace
records writes of `0x40` and then `0x3f` to the sound-command port at master
cycles 1,959,428 and 1,960,004, before the scripted coin input. The probe bar
records any nonzero command, not only IRQ-triggering commands, so this is
consistent with a legitimate startup write and does not establish an unreset
command latch.

After the reset initialization change, the focused authenticated-ROM replay
(seed 1, coin at field 170, start at 178, 230,000,000 master clocks) passed its
startup checkpoint and recorded:

| Command event | IRQ sample | INTACK |
| --- | --- | --- |
| `0xe6` at cycle 194,624,901 | cycle 194,625,572; II=0, INTACK=0 | cycle 194,625,765; II=1 |
| `0xff` at cycle 203,716,293 | cycle 203,716,580; II=0, INTACK=0 | cycle 203,716,773; II=1 |

This uses the actual audio S2650 and authenticated ROM stimulus through coin and
start; it is an observed diagnostic, not full gameplay or physical hardware
coverage. The focused `hunchback.audio.cpu` check passed and logs an eligible
sample with II clear, INTACK asserted on interrupt entry, and II cleared after
RETE. RTL lint passed. The broader lint suite remains incomplete because the
native CPU runtime-diagnostics check produced its existing warning.

## Next hardware check

Load `v261018-001032`, turn **Audio Probe** On, then use OSD Reset to clear the
sticky bars before inserting a credit. The seven bars are: blue command trigger,
green audio IRQ, cyan INTACK, yellow any nonzero command, red II observed,
magenta eligible IRQ sample, and white heartbeat. If magenta lights while cyan
stays black, the CPU reaches an enabled, unmasked opcode/HALT sampling boundary
but fails to enter INTACK. If magenta remains black while green is lit, inspect
the CPU state, clock-enable, and outstanding-request/ack gate. Cyan and red
lighting together confirms interrupt entry and PSU-II assertion.

The image fits, but setup timing is not closed: worst setup slack is -0.580 ns
and hold slack is +0.246 ns. The generated STA summary reports setup TNS
-8.542 ns, while the plain-text STA report's final endpoint summary reports
-29.873 ns for the same clock; preserve this report discrepancy for the next
timing audit. The endpoint-violation count was not emitted by these summaries.
This is an engineering diagnostic, not a candidate. Continue reporting timing
with each build and do not claim a fix until the hardware probe changes.
