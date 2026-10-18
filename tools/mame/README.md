# Hunchbak MAME sound capture

This is the MAME side of [the sound harness contract](../../docs/audio-mame-compare.md).
It requires Python 3 with numpy, MAME with Lua enabled, and the user's local
`hunchbak.zip`. ROM members are authenticated in place against
`tools/rom_manifest.json`; nothing is extracted or copied. All outputs must be
in a **new** directory under this checkout's ignored `results/`.

From the repository root:

```sh
mkdir -p results
cat > results/directed.csv <<'CSV'
seconds,command
0.050,0x40
0.060,0x3f
1.000,0xe6
4.000,0xff
CSV
python3 tools/mame_sound_capture.py \
  --rom-dir '/mnt/c/Users/markm/Documents/AI MiSTer Cores/Arcade-Hunchback_MiSTer' \
  --output results/directed --timeline results/directed.csv --duration 7
python3 tools/mame_sound_capture.py \
  --rom-dir '/mnt/c/Users/markm/Documents/AI MiSTer Cores/Arcade-Hunchback_MiSTer' \
  --output results/gameplay --record 60
```

Select another binary with `--mame /absolute/path/to/mame`. Default directed
duration is the last command time plus three seconds. `--record S` selects the
capture duration; an accompanying `--duration` must agree. MAME's
`-seconds_to_run` takes whole seconds, so fractional requests round up. The
manifest records requested duration and actual WAV duration separately. Time
zero is machine startup, not the first command or the first gameplay frame.

## Versions and reference limits

The compatibility reference is MAME commit
`c806573e925ce00fe3e8d8fe417eba63f83275ce`. The script is written against its
local Lua documentation and driver sources. Execution has been tested with
Ubuntu **0.264 (unknown)**, not a binary authenticated against the pin.
Changing `--mame` does not certify a binary's source revision. The manifest
retains the exact `-version` string and executable SHA-256; non-0.264 versions
are also marked unverified until independently checked.

The pinned driver lives in `src/mame/misc/cvs.cpp`. It configures main CPU /8,
50 Hz video, and beep0..2 placeholders. `audio_command_w` ignores unchanged
bytes; its synchronized handler asserts IRQ on a rising bit 7 and INTACK clears
IRQ. The actual handler is invoked, preserving these rules.

0.264 instead has `src/mame/cvs/cvs.cpp`, main CPU /16, 60 Hz video,
a level-sensitive bit-7 command IRQ (also cleared by INTACK), different S2650
implementation, and a DAC3 placeholder instead of those beepers. It processes
duplicate command writes. **Its captures are development diagnostics, not the
reference.** No RTL comparison or sound-accuracy PASS follows from these runs.

Both inspected drivers configure the audio S2650 with integer
`14318181 / 16 = 894886` Hz. Their S2650 instruction budgets count clock cycles
(e.g. 6 and 9), with no additional clocks-to-cycles divisor. The runner reads
the configured audio chip clock from that binary's `-listxml` and uses it as
`audio_cpu_cycle_hz`. It is deliberately different from an RTL /192 enable rate.
Lua exposes no total-cycle counter here: `audio_cpu_cycle` is
`floor(manager.machine.time:as_double() * audio_cpu_cycle_hz)`. It counts elapsed
clock periods, including HALT; it is not an instruction-execution counter.
Decimal CSV times are rounded to nine places; cycle estimates may differ by
one from recomputing from the rounded timestamp. Physical clock/phase accuracy
is outside this capture's claims.

## Isolation, audio, and outputs

The runner uses `-noreadconfig -video none -sound none -nothrottle`, 48000 Hz,
`-wavwrite`, `-seconds_to_run`, `-autoboot_delay 0`, and the Lua autoboot script.
It disables autosave, rewind, plugins, and joystick hardware. The MAME working
directory and cfg, nvram, snapshot, diff, input and state directories all reside
inside the fresh output directory. No previous game state is loaded. The
primary references for these options are the pinned `commandline-all.rst` and
MAME's own command-line option validation. MAME 0.264 has no
`-memcard_directory` option; no memory card is used by this machine.

`-sound none` **does write audio to WAV on 0.264**. The WAV writer produces
stereo despite the driver's single speaker. The runner retains it as
`raw-mix.wav`, checks uncompressed 16-bit/48000 Hz PCM, and writes `mix.wav`
as mono using the integer channel mean, rounding down. Mono source WAVs also
work. No DC removal, gain, filtering, or trimming is applied. MAME can execute
one more screen frame while exiting; event taps stop at the whole-second
capture boundary. Both WAV length and event timestamps are validated.

Outputs:

- `timeline.csv`: actual control-port writes, `seconds,command`, including
  duplicates. In directed mode the runner requires the applied timeline to
  match the requested times/bytes (10 ns serialization tolerance).
- `dac-events.csv`: `seconds,audio_cpu_cycle,address,value`, one full-byte row
  for each write to 0x1840 or 0x1880..0x1887. It excludes the intervening holes.
- `mix.wav`: shared mono signed 16-bit 48000 Hz PCM; `raw-mix.wav`: original.
- `manifest.json`: version, clock basis, actual timeline, seed=null, ROM/binary/
  tool hashes, output hashes, exact invocation, limitations, command counts,
  event counts per command, and per-second raw RMS and DC-removed RMS in PCM16
  units. `mame_wall_seconds` measures the child process; `wall_seconds` also
  includes postprocessing, but excludes preflight ROM/version/hash work.
- `capture-config.lua`, `lua-status.txt`, `mame.log`: private run configuration,
  lifecycle/isolation status and all MAME findings. Failed runs retain a
  `FAILED` manifest and are never silently accepted.
- Record mode additionally writes `inputs.csv` (logical pressed flags) and
  `sprite-positions.csv` (actual PVI HC/VC writes and current movement inputs).
  `movement_observation` in the manifest reports PVI 1 object 0 before input
  and its first changed coordinate during the following second, if observed.

No `irq-events.csv` is emitted: IRQ assertion and INTACK callbacks are not
exposed by these Lua interfaces. Command observations are not IRQ observations.

The pinned Lua sound interfaces have no documented per-device output-gain or
beeper-clock setter; the tested generic device objects expose neither.
**Beepers are not excluded.** On 0.264 beep0..2 do not exist, but its DAC3
placeholder remains audible. The pinned mixed WAV will include beepers unless
a separately reviewed exclusion method is added. `lua-status.txt` enumerates
present beep devices and explicitly records `beepers_excluded=false`.
`dac-events.csv` retains every write that could affect them: 0x1840 (also beep2
clock) and 0x1884..0x1887. The manifest counts these addresses. Speech is also
included in the complete driver mix. Do not treat this mix as DAC-only or as an
analog/discrete reference. Raw RMS includes large DAC DC offsets; consult the
DC-removed RMS before calling a segment audible.

## Directed and record behavior

Directed mode stops main execution before its first instruction: a program
read tap returns the S2650 HALT opcode (0x40) and writable PS has PSU.II set
(bit 0x2000 in combined PS), preventing vblank IRQ from waking it. This is a
read overlay, not a ROM modification. Setting the exported HALT state alone
would not stop instruction fetching in the inspected S2650 loop. There is no
main/game initialization, normal video activity or gameplay speech command
stream; audio/speech CPUs and other devices continue from reset. A control-port
tap counts unexpected main writes and the runner fails if any occur. Commands
are delivered by emulated-time scheduler waits to `maincpu.spaces.data` at
address 0, through the real driver handler. They are not writes to the audio
latch or invented interrupt pulses.

Record mode leaves the CPUs alone. Coin is held at 3.0..3.2 seconds and start
at 4.0..4.2 seconds; earlier pulses were ineffective during initialization on
0.264. Right is held from 15 seconds and jump repeats for 0.18 seconds every
1.2 seconds thereafter. These times allow boot and roughly ten seconds of
intro. Inputs are applied at screen-frame boundaries, so the recorded input
edges reflect frame quantization. There is no claim of optimal gameplay,
reaching the bell, or equivalence across the two drivers' intro timing.

The sprite observation masks all four program-memory mirrors to 0x1fff and
checks FO=0, excluding character RAM. PVI2/1/0 occupy 0x1500/1600/1700;
object bases are 0x00,0x10,0x20,0x40, HC at +0x0a, VC at +0x0c. Each row
updates one register and retains the previous value of the other (255 until
first observed). These are register coordinates, not transformed display
coordinates. To check controllability, compare stable pre-input coordinates
with post-input movement and, preferably, a private no-movement control run
with the same coin/start sequence. Do not mistake intro animation for player
control. A missing `movement_observation` is missing evidence, not PASS.

## Lua API assumptions

All MAME-specific calls/properties used by the script are listed here. The
pinned local `ref-core.rst`, `ref-devices.rst`, `ref-mem.rst` and the driver/CPU
sources are the API/map references; record-input field behavior is also
experimentally checked on 0.264. The pinned binary still needs an execution run.

- Standard Lua supports `os.getenv`, `dofile`, `io.open`/write/close, tables,
  formatting, integer bit operations and coroutine yielding. The environment
  variable `HUNCHBAK_CAPTURE_CONFIG` points to a generated `return { ... }` file;
  long-bracket strings safely carry absolute paths. No shell interpolation is
  used to launch MAME.
- `manager.machine.devices[tag]` looks up `:maincpu`, `:audiocpu`, and optional
  `:beep0`..`:beep2`. `device.spaces.program` and `.data` are address spaces.
  In both inspected versions S2650 non-extended CTRL is **data address 0**;
  `.io` is extended I/O. The name `main_cpu_io_map` alone is misleading.
- `machine.time` is attotime and `:as_double()` returns seconds, including
  CPU-local emulated time inside a write callback. Autoboot delay zero executes
  at time zero before the first instruction; the runner verifies this.
- `space:install_write_tap(start,end,name,callback)` observes absolute address,
  full write data and access mask. `install_read_tap` returns replacement read
  data when the callback returns an integer. Observer callbacks return nil and
  do not alter writes. Tap userdata removes handlers on garbage collection;
  `_G.hunchbak_capture.taps` explicitly retains every handle for the whole run.
- `space:write_u8(address,value)` invokes the mapped driver write handler and
  its write tap. Pinned command scheduling remains MAME's own synchronization.
- `device.state.PS.value` is readable/writable combined PSU:PSL; `FO.value` is
  the flag bank selector; `PC.value` is readable at stop. Neither device
  suspend/resume nor total_cycles is assumed to exist.
- `emu.wait(seconds)` yields the autoboot coroutine until a scheduler timer,
  allowing sub-frame directed commands; calls are relative to current time.
- `emu.add_machine_frame_notifier` and `add_machine_stop_notifier` register
  callbacks and return retained subscription handles. If absent, the script
  falls back to `emu.register_frame`/`register_stop` (deprecated but available
  on 0.264). Frame callbacks run headless; stop callbacks close logs normally.
- `machine.ioport.ports[tag].fields` supports `pairs`; each field has `.mask`
  and `:set_value(0 or 1)` for released/pressed logical digital input, including
  active-low fields. Fields are selected by mask rather than localized names:
  IN0 coin=0x08, start=0x01, jump=0x20; IN1 right=0x10. Missing fields abort.
- No device-specific beep methods, sound-stream gain controls, IRQ hooks,
  debugger installation or total-cycle extension are presumed available.

A repeat directed capture should have identical hashes for timeline, DAC log,
mono WAV and raw WAV. This also checks the regression where collected tap
handles prematurely stopped logging. Never compare only process exit codes:
inspect the manifest status, time-zero/start/stop checks, full event count and
retained MAME log. ROM/captures/WAVs and local probe variants stay ignored.
