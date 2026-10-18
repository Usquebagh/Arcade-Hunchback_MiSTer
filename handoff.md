# Hunchback (CVS) MiSTer core — handoff

**Repo:** https://github.com/Usquebagh/Arcade-Hunchback\_MiSTer (public)
**Local path:** `C:\\Users\\markm\\Documents\\AI MiSTer Cores\\Arcade-Hunchback\_MiSTer`
**State:** Playable. Video, controls, reset, cheats and TMS5100 speech work on hardware. Sound *effects* (bell, walking, jumping) do not. Timing not closed. Engineering beta, not a candidate.
**Last build at handoff:** `v261018-001032`, SHA-256 `201A2C14D014C560E438E35F3B19470DFCC2A3C5B26D74A070A6FCA0DA4A418A`

\---

## 1\. Target hardware

Century Video System (CVS), Century Electronics UK, 1983. Vertical monitor, two-player alternating, two-way joystick + jump button.

**Reference documentation (already in repo, gitignored):** `docs/private/cvs-v1.4/` — kevtris reverse-engineered schematic `cvs\_arcade\_V1.4.pdf` (6 pages), eight PAL source listings (`.pld`) and JEDEC files. **This is the authoritative source.** Every significant breakthrough on this project came from reading it rather than inferring from MAME.

Schematic page map:

|Page|Sheet|
|-|-|
|1|ROM board|
|2|Audio board — 2× S2650A, DACs, ICL8038, noise/filter/mixer, TMS5100|
|3|Main board 4 — character/video RAM, attribute/scroll|
|4|Main board 1 — main S2650A, system RAM, inputs, PAL decoders|
|5|Main board 2 — crystal/dividers, 2621N, 3× 2636N, raster counters, colour DAC|
|6|Main board 3 — character RAM/ROM select, shift registers, bullet, palette|

## 2\. MAME reference

* Driver: `src/mame/misc/cvs.cpp`, set `hunchbak` (variants `hunchbaka`, `hunchbkd`, `hunchbkg`, `hunchbks` — the latter two are *different hardware*, Galaxian/Scramble conversions, non-interchangeable ROMs).
* S2636 device: `src/devices/machine/s2636.cpp`
* TMS5110/5100: `src/devices/sound/tms5110.cpp`
* Pinned revision recorded in `docs/references.md`.

**MAME caveats learned the hard way:**

* `set\_offsets(-5, -26)` is ordered **Y then X**. X offset is −26, not −5.
* MAME's `240x248` visible area is a bitmap convention with no raw timing behind it. Do not treat it as hardware truth.
* MAME's CVS discrete audio is **beeper placeholders**, explicitly not accurate, and does not list `hunchbak` among games using those trigger latches. MAME is not a reference for this game's sound effects.

## 3\. Architecture

### CPUs

Three Signetics **S2650A** — main, audio, speech. Core: `rtl/vendor/arcadia/sgs2650.vhd` (modified).

### Clocks

14.318181 MHz crystal. Core PLL generates **57.272727 MHz** (real Cyclone V IP, `locked` used in reset).

* 2621 sync generator: 227 timing slots/line, 312 lines/field → **50.541419 Hz**. Matches real hardware (50.541416 Hz) to 7 s.f. MAME's fixed 50 Hz is 1.08% *below* hardware.
* Display pixel clock: U12AA/U12AB divide 14.318 MHz by three; U12CA rephases PIXCLK on /HRST. 183 unblanked slots × 16 master clocks ÷ 12 per pixel = **244 active pixels**. Not 227, not 240.
* Audio CPU clock enable: one pulse per 192 master clocks (\~298.3 kHz).

### Video

Signetics 2621 sync generator + **three S2636 PVIs** + character/tilemap + bullet layer. Hardware collision detection between object and character planes. Visible 244×248. Rotation via MiSTer `screen\_rotate`; OSD offers Rotate CW / Rotate CCW (Native was removed — it was broken).

### Audio (schematic page 2, documented in `docs/audio-circuits.md`)

Audio CPU `SP\_LAT0..7` outputs split into two groups:

|Latch|Address|Function|
|-|-|-|
|`SP\_LAT0..3`|`0x1880`–`0x1883`|**4-bit weighted DAC** into LM3900 mixer via 12k/22k/47k/100k summing resistors (+100k shunt). Ungated. Separate from byte DAC.|
|`SP\_LAT4`|`0x1884`|CD4016 UD1B/UD1A — selects byte DAC between ICL8038 FM node and MIX2|
|`SP\_LAT5`|`0x1885`|CD4016 UD1D + R35=150k — gates ICL8038 square into MIX2|
|`SP\_LAT6`|`0x1886`|R71=10k, BC337 TR2, C17=10µF/R73=220k → **2.2 s** envelope; receives NE555 via D4/R65=22k|
|`SP\_LAT7`|`0x1887`|R72=10k, BC337 TR3, C18=10µF/R63=100k → **1.0 s** envelope; receives NOISE via U1C/D3/R62=22k|

Byte DAC at `0x1840`. NE555: R79=33k, R80=220k, C26=10nF → **304.4 Hz**, duty \~53.5% (independently verified twice). ICL8038 timing cap C7=22nF; **full frequency not resolvable from the schematic** — currently an estimate.

Bit extraction (`rtl/machine/cvs\_audio\_bus.sv`): `dac4\[addr\[1:0]] <= din\[7]` for 0x1880–3; `discrete\[addr\[1:0]] <= din\[0]` for 0x1884–7. Note the **different data bits** — drawing says SP\_D0, MAME uses bit 7 for 1880–1883 and bit 0 for 1884–1887. This discrepancy is recorded in `docs/audio-digital.md` and has not been physically resolved.

Speech: TMS5100 + dedicated S2650. **Works on hardware.**

## 4\. How sound is meant to work

1. Main CPU writes a command byte to the sound command port (`rtl/machine/cvs\_main\_io.sv`).
2. `audio\_trigger <= !audio\_command\[7] \&\& din\[7]` — the trigger is a **rising edge of bit 7** of the command byte.
3. Trigger sets `irq` to the audio CPU (`cvs\_audio\_bus.sv`). IRQ clears on the rising edge of `intack`.
4. Audio CPU takes the interrupt (vector `0x03`), runs the effect routine, and writes `SP\_LAT0..7`.
5. `SP\_LAT0..3` writes produce the 4-bit weighted DAC output → mixer → `AUDIO\_L/R`.
6. `SP\_LAT4..7` gate the discrete analogue circuits.

**Measured from the ROM:** during gameplay Hunchback drives sound almost entirely by toggling **SP\_LAT2** (`0x1882`, 3,332 writes of `0xff` interleaved with `0x00` in a controlled run), with a sweeping toggle rate (\~62,784 master clocks early, \~16,704 later). `SP\_LAT4..7` are **never set** by this game. The discrete circuits exist on the board but Hunchback does not use them for these effects.

## 5\. Current sound symptoms (hardware)

* Speech works at game start. **Does not** play when the player falls off the edge.
* No bell, walking or jumping sounds, ever.
* Game otherwise plays correctly.

**Probe readout (OSD → Audio Probe → On), confirmed bar-by-bar:**

|Bar|Signal|State|
|-|-|-|
|blue|command trigger|**lit** (on credit insert)|
|green|audio IRQ raised|**lit**|
|cyan|**INTACK**|**black — never asserts**|
|yellow|non-zero command latched|lit (also at boot — legitimate startup writes `0x40`, `0x3f`)|
|red|PSU-II interrupt inhibit observed|black — never set|
|magenta|eligible IRQ sample|(added last build, untested)|
|white|heartbeat control|pulsing|

**Conclusion:** hardware raises an unmasked interrupt with a valid command, and the audio CPU never acknowledges it. The same RTL **does** acknowledge in simulation.

## 6\. Ruled out (do not re-investigate without new evidence)

|Hypothesis|How eliminated|
|-|-|
|Mixer not summing the 4-bit DAC|Read RTL; `nibble\_mix` is summed ungated into `mix\_ab`, correct per schematic|
|Gain too low|Was real (0.8% FS). Fixed — normalised, `>>>2` removed. Still silent.|
|DC offset railing the mix|Was real. Idle byte DAC code `0x00` → −32768. Fixed via `cvs\_audio\_dc\_blocker` + reordering so coupling precedes the saturating sum (`cvs\_audio\_output.sv`).|
|Discrete circuits not implemented|Implemented (`cvs\_discrete\_audio.sv`). Irrelevant — game never gates them.|
|Audio ROM at wrong download offset|**Verified correct.** MRA main section = 4 blocks × (5×0x400 + 0x0c00 repeat) = exactly 0x8000. `6c.sdp1` lands at 0x8000, matching `dl\_addr>=0x8000 \&\& <0x9000`.|
|Audio CPU not running / held in reset / no clock|Probe: fetching, address bus moving, clock enable running, reset released, SENSE toggling|
|PSU-II interrupt masking|Probe: never set|
|Command never sent|Probe: trigger + non-zero command both lit|
|Unreset command latch|Disproved — `cvs\_main\_io.sv` clears it on sync reset; startup writes are legitimate|

## 7\. Leading hypothesis

Simulation/silicon divergence from **undefined reset state in the S2650 interrupt path**. The async reset branch cleared IAR, stack pointer and PSU-II but **did not** initialise control `state`, the registered request handshake, or `intack`. `reset\_na` is held low during core reset, so the synchronous `state <= sOPCODE` assignment was not guaranteed to execute. Verilator treats uninitialised regs as 0; the FPGA does not.

Work in progress (committed, **not hardware-confirmed**): initialise `state` to `sOPCODE`, `req\_i` low, `intack` low in the async reset branch of `rtl/vendor/arcadia/sgs2650.vhd`.

Post-change simulation (seed 1, coin field 170, start 178, 230M master clocks) shows correct interrupt entry:

|Command|IRQ sample|INTACK|
|-|-|-|
|`0xe6` @ 194,624,901|@194,625,572, II=0|@194,625,765, II=1|
|`0xff` @ 203,716,293|@203,716,580, II=0|@203,716,773, II=1|

**Needs hardware confirmation.**

## 8\. Build process

Quartus **Lite 17.0.2** via Docker image `theypsilon/quartus-lite-c5:17.0.2`. Target Cyclone V `5CSEBA6U23I7`.

```bash
./build.sh
```

Generates a fresh `build\_id.v` (`vYYMMDD-HHMMSS`, shown in the OSD version line), runs `quartus\_sh --flow compile Arcade-Hunchback`, logs to `build/quartus.log`, prints fit summary. Output: `output\_files/Arcade-Hunchback.rbf`.

**Critical:** do **not** use the gated path (`tools/bdsm.sh build`). It stops at a candidate-coverage preflight because nine coverage gates are marked SKIP, and produces no RBF. This blocked the project three separate times. `AGENTS.md` permits skipping the full suite during development; use `build.sh` directly.

Test framework: MiSTer-BDSM (Verilator/Icarus/Yosys). Decoupled — not a submodule. Set `MISTER\_BDSM\_PATH` to a checkout of https://github.com/Usquebagh/MiSTer-BDSM, or place it at the repo root.

```bash
export MISTER\_BDSM\_PATH=/path/to/MiSTer-BDSM
./tools/bdsm.sh test --suite smoke
./tools/bdsm.sh test --check hunchback.audio.cpu
```

## 9\. Deploy and test

MiSTer SD card is mounted on the Windows host as drive **`M:`**. From WSL, reach it via `powershell.exe` — mapped network drives are not visible under `/mnt`.

|File|Destination|
|-|-|
|`output\_files/Arcade-Hunchback.rbf` → `hunchback\_20261017.rbf`|`M:\\\_Arcade\\cores\\`|
|`Hunchback (CVS).mra`|`M:\\\_Arcade\\`|
|`hunchbak.zip` (user-supplied)|`M:\\games\\mame\\` — **not** `\_Arcade/mame/`, that's the legacy path|

**Rules learned the hard way:**

* Keep **exactly one** `hunchback\*` file in `\_Arcade\\cores\\`. Rollbacks go to `results/card-backups`, never the card. Multiple matching files caused MiSTer to load the wrong core and cost hours.
* **Never enumerate `M:\\\_Arcade`** — the collection is huge and a listing takes forever. Check only `M:\\\_Arcade\\cores\\hunchback\_20261017.rbf`, the `hunchback\*` wildcard, and the MRA's `<rbf>` element.
* Always verify SHA-256 of card file vs `output\_files/Arcade-Hunchback.rbf`.
* Always confirm the OSD version string matches the build. Two separate rounds of "the fix doesn't work" were stale binaries.
* `releases/hunchback\_20261017.rbf` is tracked via a `!releases/\*.rbf` gitignore exception — keep it synced with the deployed build.

**Test sequence:** load core → confirm OSD build ID → (Audio Probe On if diagnosing) → OSD Reset to clear sticky probe bars → insert coin → press start → **wait \~10 s** for the climb animation (player is not controllable; \~505 fields at 50.54 Hz) → walk right → jump → reach the bell.

> The 10-second intro invalidated three separate automated traces. Any scripted test must wait past field \~700 after start, and must \*\*prove\*\* controllability by confirming the sprite coordinate changes before trusting input.

## 10\. OSD options

Coin A/B, Lives, Cabinet, Bonus life, Registration, Registration length, Orientation (Rotate CW/CCW), Meter pulses, Aspect ratio, **Audio Probe (Off/On)**, Reset, Cheats.

**conf\_str ordering is load-bearing:** `R\[0],Reset` and `C,Cheats` must appear **before** the `J1`/`jn` joystick lines. Placed after them they render in the menu but are never bound — both appeared and did nothing for several builds.

Cheats: Pugsy's MAME `hunchbak` codes embedded in the MRA, delivered via the standard HPS path. Available: Infinite Credits, Infinite Time, Next Bell = Super Bonus, Invincibility, P1/P2 Infinite Lives. **No no-enemies cheat exists in Pugsy's set** — deliberately not invented. Closed, do not reopen.

## 11\. Open questions

1. **Why does INTACK never assert on hardware when it does in simulation?** Primary question. Test the committed S2650 reset-initialisation change on hardware.
2. Does the new magenta "eligible IRQ sample" bar light? If magenta lights and cyan stays black, the CPU reaches an enabled sampling boundary but fails to enter INTACK. If magenta stays black with green lit, inspect CPU state, clock enable and the request/ack gate.
3. **Why does speech work at game start but not on falling off the edge?** Both are command-driven. May share the INTACK cause.
4. `SP\_D0` vs bit 7 / bit 0 data-line discrepancy between schematic and MAME — unresolved, no physical measurement.
5. ICL8038 frequency not derivable from the schematic. Currently estimated (\~55.6 Hz base from 0.33/(RC) with 270k/22nF). Irrelevant until the game is observed to use it.
6. **Timing not closed.** Worst setup −0.580 ns, hold +0.246 ns. STA summary reports TNS −8.542 ns while the plain-text report's endpoint summary says −29.873 ns for the same clock — **this discrepancy is unexplained and should be audited.** Endpoint violation count not emitted. Deprioritised until sound works; report with every build and do not let it regress.
7. Nine candidate coverage gates remain SKIP (cpu, banked\_memory, video, input, audio, audio\_reference, game\_boot, mister\_integration, constraints). Long-term research requiring physical reference captures. Not a release gate for engineering builds.
8. CRT output untested — only HDMI confirmed.

## 12\. Method notes

Three techniques accounted for every breakthrough:

1. **Go to the schematic, not MAME.** The 244-pixel line width, the −26 sprite X offset and the audio component values all came from kevtris's drawing after days of inference failed.
2. **Hardware probes with a control.** On-screen indicators driven directly from signals, *including a free-running heartbeat* so you can tell a dead signal from a dead probe. Three static bars taught us nothing until a heartbeat proved the instrument worked.
3. **Distrust agreement between simulation and intent.** Simulations passed throughout while hardware stayed broken, repeatedly — because they encoded the same wrong assumptions. Several tests asserted a pulse *asserts* a signal without ever checking the *idle* state, and traces measured moments when the game wasn't doing the thing being measured.

Source comments marked "provisional", "pending" or "not measured" are load-bearing assumptions, not TODOs. `cvs\_scan.sv` and `cvs\_video\_join.sv` still carry them.

