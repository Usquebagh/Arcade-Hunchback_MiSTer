# Hunchback (CVS, 1983) for MiSTer FPGA

An FPGA implementation of Century Electronics' **Hunchback** arcade game for
the [MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform,
based on the original Century Video System (CVS) hardware.

Play as Quasimodo, leaping pits, swinging on ropes and dodging arrows and
fireballs across the castle ramparts to ring the bell and rescue Esmeralda.

<p align="center">
  <img src="docs/images/cabinet.png" alt="Hunchback upright cabinet" height="310">
  <img src="docs/images/gameplay.png" alt="Hunchback running on MiSTer" height="310">
</p>

This core targets the CVS board. The Hunchback conversions for Galaxian,
Scramble and Donkey Kong hardware are different machines and need different
ROMs.

---

## Original Hardware

| Subsystem | Original Hardware | FPGA Implementation |
|---|---|---|
| **Main CPU** | Signetics 2650A @ 1.79 MHz (14.318 MHz ÷ 8) | S2650 core from Arcadia_MiSTer, with corrections |
| **Sound CPU** | Signetics 2650A @ 895 kHz (14.318 MHz ÷ 16) | Same S2650 core |
| **Speech CPU** | Signetics 2650A @ 895 kHz | Same S2650 core |
| **Video timing** | Signetics 2621 sync generator, 312 lines, 50.54 Hz | `cvs_video_timing.sv` |
| **Sprites** | 3 × Signetics 2636 PVI, with object collision detection | `cvs_s2636_objects.sv` |
| **Background** | Character RAM/ROM, bullets, colour PROMs and hardware collision detection | `cvs_character_video.sv` |
| **Sound** | 8-bit DAC, 4-bit weighted DAC, NE555, ICL8038 and noise discrete circuits | `cvs_discrete_audio.sv`, a digital model from the schematic |
| **Speech** | TI TMS5100 (TMC0281) with serial speech ROM | `cvs_tms5100_*.sv`; coefficient tables from MAME |
| **Display** | Vertical monitor, 244 × 248 visible | MiSTer framebuffer rotation (Rotate CW / CCW) |
| **Controls** | Two-way joystick and jump button, two players alternating | D-pad or stick plus one button |

Notes on the hardware and the design decisions are in
[docs/architecture.md](docs/architecture.md), with per-subsystem detail in
[docs/](docs/).

---

## Controls

| Input | Function |
|---|---|
| **D-pad / Stick left-right** | Move |
| **A** | Jump |
| **Start** | Start 1 player |
| **X** | Start 2 players |
| **Select** | Coin |

Player 2 uses the second controller in **Cocktail** mode. In **Upright** mode
both players share the first controller and take turns.

**OSD:** Coin A, Coin B, Lives, Cabinet, Bonus Life, Orientation (Rotate CW or
CCW) and Aspect Ratio. **Reset** restarts the game.

**Diagnostics:** **Audio Probe** shows on-screen status bars for the sound and
speech hardware. **Audio mix** plays Speech only or Effects only. Both are
off by default.

---

## ROMs

```
ROMs are not included. Use the MAME "hunchbak" set.

/_Arcade/Hunchback (CVS).mra
/_Arcade/cores/hunchback_YYYYMMDD.rbf
/games/mame/hunchbak.zip
```

The latest core and MRA are
[hunchback_20261018.rbf](releases/hunchback_20261018.rbf) and
[Hunchback (CVS).mra](releases/Hunchback%20(CVS).mra). Keep only one
Hunchback RBF in `_Arcade/cores/`. Older MiSTer installations may also
support `_Arcade/mame/` as a legacy ROM location.

---

## Cheats

The cheats are included in the MRA, so no separate `.cht` file is needed. Open
**Cheats** in the OSD to enable them:

- Infinite Credits
- Infinite Time
- Next Bell = Super Bonus Now!
- Invincibility
- P1 Infinite Lives
- P2 Infinite Lives

They are converted from Pugsy's Hunchback entries in the MAME cheat
collection. A no-enemies cheat is not part of that set, so it was left out
rather than guessed.

---

## Compilation

Quartus Prime Lite 17.0.2 targeting the DE10-Nano's Cyclone V. Open
`Arcade-Hunchback.qpf` and compile, or run `bash build.sh` to build in Docker.
Each build stamps a UTC build ID on the OSD version line.

The regression and mutation suite uses
[MiSTer-BDSM](https://github.com/Usquebagh/MiSTer-BDSM). Clone it and set
`MISTER_BDSM_PATH`:

```sh
git clone https://github.com/Usquebagh/MiSTer-BDSM.git /path/to/MiSTer-BDSM
export MISTER_BDSM_PATH=/path/to/MiSTer-BDSM
bash tools/bdsm.sh test --suite smoke
bash tools/bdsm.sh test --suite lint
```

A Verilator sound-section bench, a MAME capture tool and a comparison scorer
are in `sim/harness/` and `tools/`. See
[docs/audio-mame-compare.md](docs/audio-mame-compare.md).

---

## Credits

- **Hunchback (Arcade):** Century Electronics, 1983
- **S2650 CPU:** DO (temlib), imported from MiSTer-devel's
  [Arcadia_MiSTer](https://github.com/MiSTer-devel/Arcadia_MiSTer)
- **TMS5100 coefficient tables:** MAME, by Frank Palazzolo, Couriersud and
  Jonathan Gevaryahu
- **Board research:** Kevtris's reverse-engineered CVS schematics and PAL
  sources (not redistributed here)
- **Cheats:** converted from Pugsy's MAME cheat collection
- **Reference:** MAME `cvs` driver by Mike Coates and Couriersud. See
  [reference provenance](docs/references.md)
- **Test framework:** [MiSTer-BDSM](https://github.com/Usquebagh/MiSTer-BDSM)
- **MiSTer Platform:** Sorgelig and the MiSTer community

## License

The original core and tools are BSD-3-Clause. Imported components keep their
upstream licenses and notices; see [LICENSE](LICENSE), [LICENSES](LICENSES/)
and the vendored component documentation.
