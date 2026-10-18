# Hunchback (CVS) for MiSTer — Claude guide

**`AGENTS.md` is binding and overrides anything here.** It holds the
per-subsystem check lists, the candidate/engineering build distinction and the
publication rules. This file is the short orientation plus the working rules
for this machine. Current state and the open sound fault: `docs/STATUS.md`.

## What the core is

FPGA implementation of Century Electronics' *Hunchback* (1983) on the Century
Video System (CVS) board, for MiSTer (Cyclone V `5CSEBA6U23I7`). Three
Signetics S2650A CPUs (main, audio, speech), a 2621 sync generator, three S2636
PVIs, character/bullet video with hardware collisions, a byte DAC, a 4-bit
weighted DAC, discrete effects and TMS5100 speech. 14.318181 MHz crystal and a
57.272727 MHz core PLL. Status: playable engineering beta, not a candidate.

## References, in order of authority

1. **kevtris CVS schematic v1.4 and PAL sources** — `docs/private/cvs-v1.4/`
   (gitignored, never publish). Authoritative for circuits, clocks and values.
2. **MAME `src/mame/misc/cvs.cpp`, set `hunchbak`**, pinned at
   `c806573e925ce00fe3e8d8fe417eba63f83275ce` (`docs/references.md`). It is a
   compatibility reference for the memory/I/O map, ROM layout, CPU program
   behaviour and the byte/4-bit DAC writes. **It is not a reference** for
   discrete audio (beeper placeholders), raw video timing (its 50 Hz and
   240x248 are conventions) or physical phases. `hunchbkg`/`hunchbks` are
   different hardware.
3. Device sources from the same MAME pin: `s2636.cpp`, `tms5110.cpp`.

Label every expectation by source: board/schematic, MAME compatibility,
independent model, or frozen regression (AGENTS.md).

## Source layout

| Path | Contents |
| --- | --- |
| `Arcade-Hunchback.sv` | MiSTer `emu` top: CONF_STR, HPS I/O, video/audio out, probes |
| `rtl/machine/` | Core RTL (`cvs_*.sv`): main/audio/speech machines, buses, video, TMS5100 |
| `rtl/vendor/arcadia/` | Modified S2650 VHDL (`sgs2650.vhd`), GPL-2.0 |
| `rtl/vendor/tms5100/` | TMS5100 numeric tables transcribed from MAME, BSD-3 |
| `rtl/pll*` | Cyclone V PLL IP |
| `sys/` | MiSTer template framework (do not edit) |
| `sim/bdsm/` | MiSTer-BDSM adapter (`adapter.json`), Verilator C++ benches, Python oracles |
| `sim/cpu/` | SystemVerilog/VHDL testbenches run by the adapter |
| `tools/` | `bdsm.sh` runner, ROM preparation, long-run observer, renderers |
| `docs/` | Per-subsystem contracts and evidence; `docs/private/` is ignored |
| `releases/` | MRA and the single dated, reviewed engineering RBF |
| `scripts/` | Host-side helpers (`deploy.ps1`) |
| `LICENSES/` | Imported-component licences |

## Toolchain (this machine)

Windows 11 host. All HDL tools live in **WSL `Ubuntu-24.04`**: Verilator 5.020,
Icarus 12.0, Yosys 0.33, GHDL 4.1.0, Python 3.12 + numpy, Docker 29 with
`theypsilon/quartus-lite-c5:17.0.2` (Quartus Lite 17.0.2). There is no native
Windows Quartus and no Windows Python. MiSTer-BDSM is checked out (ignored) at
`./MiSTer-BDSM`. Codex CLI: `%APPDATA%\npm\codex.cmd` (Node.js LTS in
`C:\Program Files\nodejs`). MAME is not installed yet.

From PowerShell, run repo commands through WSL. Put anything with nested
quotes in a script file rather than an inline `bash -lc` string:

```powershell
wsl -d Ubuntu-24.04 --cd "/mnt/c/Users/markm/Documents/AI MiSTer Cores/Arcade-Hunchback_MiSTer" -- bash build.sh
```

## Hardware — use all of it

Ryzen 9 5950X (16C/32T), 64 GB RAM. Always use the whole machine:

- **Quartus:** `NUM_PARALLEL_PROCESSORS ALL` stays in `Arcade-Hunchback.qsf`
  (already set). The Docker container sees all WSL CPUs.
- **Verilator:** build with `-j 32`. Use `--threads N` where it helps:
  large connected/full-machine models and long ROM runs. Measure it first;
  small benches are often slower multithreaded. Threading must not change
  results: a seeded run must reproduce bit-identically before you adopt it.
  Pending: `sim/bdsm/check.py:144` builds without `-j`. Adding it goes
  through the normal commit gate.
- **Run independent jobs at the same time, not one after another:** separate
  BDSM checks, Quartus compiles in separate worktrees (each worktree has its
  own `db/` and `output_files/`, so two compiles never share a directory),
  and Codex tasks in their own worktrees. Leave headroom: about 4 Quartus
  compiles, or 1–2 compiles plus sims.
- **Long jobs** (Quartus, mutation campaigns, ROM observation runs, MAME
  captures) **run in the background** while you keep working. Check them
  when they finish; don't poll.
- WSL2 gets 50% of RAM (32 GB) by default and there is no `.wslconfig`.
  If parallel builds start swapping, ask the user before raising `memory=`
  in `%USERPROFILE%\.wslconfig`.

## Build, test, deploy

| Task | Command (in WSL, repo root) |
| --- | --- |
| Engineering RBF | `bash build.sh` → `output_files/Arcade-Hunchback.rbf`, log `build/quartus.log` |
| One check | `bash tools/bdsm.sh test --check hunchback.audio.cpu` |
| Lint | `bash tools/bdsm.sh test --suite lint` |
| Smoke | `bash tools/bdsm.sh test --suite smoke` |
| Long ROM run | `python3 tools/observe_hunchback.py hunchbak.zip --audio ...` (see `docs/rom-observation.md`) |
| Deploy to MiSTer | `powershell -File scripts/deploy.ps1` (Windows; MiSTer `root@192.168.75.57`, key login) |

- `build.sh` output is `ENGINEERING_UNQUALIFIED_NOT_A_CANDIDATE`. Never use
  `tools/bdsm.sh build` for development: it stops at the candidate preflight
  (nine SKIP coverage gates) and produces no RBF.
- Report setup/hold slack with every build. Timing is not closed (worst setup
  −0.580 ns), and it must not get worse.
- On the card: exactly one `hunchback*` RBF in `_Arcade/cores/`, named as the
  MRA `<rbf>` says (`hunchback_20261017`). Verify the SHA-256 after copying,
  and confirm the OSD build ID matches `build_id.v` before trusting any
  hardware result. Never list `_Arcade/` in full. Back up to
  `results/card-backups/`, never to the card. ROMs: `games/mame/hunchbak.zip`.

## Conventions

- **MiSTer template rules:** keep the `emu` port contract and `sys/` untouched.
  CONF_STR ordering is load-bearing: `R[0]` reset and `C` cheats come before
  the `J1`/`jn` lines. Audit the whole string on any change (AGENTS.md).
  Register new sources in `files.qip`.
- **Minimal diffs, no unrelated changes.** Don't reformat, don't rename, don't
  fix things you weren't asked to touch. Write code in the style of the
  surrounding file. Note out-of-scope problems in `docs/STATUS.md` and leave them.
- **Provisional comments are load-bearing.** "Provisional", "pending" and "not
  measured" in source mark assumptions, not TODOs.
- **Never weaken a test** to get a PASS. Keep bug reproductions as regressions.
  A test that checks an asserted state must also check the idle state.
- **Never commit** ROMs, schematics, PAL/JEDEC, `docs/private/`, WAVs,
  traces, `results/`, Quartus output or MAME captures. The only binary
  exception is the reviewed dated RBF under `releases/`.

## Commit gate

**No RTL, simulation, tool or adapter change is committed until its sim/tests
pass:**

1. Every check AGENTS.md lists for the touched subsystem passes, plus
   `hunchback.rtl.lint`.
2. Every bug-regression check for that subsystem still passes.
3. For audio-path changes, once the sound harness exists
   (see `docs/STATUS.md`), it runs with no score regression.
4. The commit message records which checks ran. Any check you skipped is
   named as skipped, and why.

A pre-existing WARNING (e.g. `hunchback.cpu.runtime_diagnostics`) is reported
as such. It is not a pass, and nothing is merged on the assumption that it is
harmless. Docs-only commits need no sim run. Never commit failing work to
`main`; a WIP branch is fine.

## Delegating to Codex

Claude is the lead on this repo. Codex is a contractor for **well-scoped**
tasks: one subsystem, a clear acceptance check, and no need to judge
schematic evidence. Good fits: write a testbench against a stated contract,
write a script or tool, make a mechanical refactor, add a regression for an
already-diagnosed bug. Do not delegate root-cause diagnosis, reference/evidence
decisions, CONF_STR changes, release/deploy or anything touching `docs/private/`.

**Division of labour:** prefer delegating implementation to Codex. Claude
plans, writes the task specs and contracts, reviews the diffs and runs the
harness and checks.

**Model policy:**

| Tier | Model | Effort | When |
| --- | --- | --- | --- |
| Default | `CODEX_CHEAP_MODEL` (TBD) | `medium` | Every task to start with |
| Escalation | `CODEX_STRONG_MODEL` (TBD) | `high` | After **two failed attempts** at the same task, or for timing-critical analysis (STA, CDC, cycle-exact behaviour) |

Pass both on every call: `-m <model> -c model_reasoning_effort="medium"`.
Don't rely on `~/.codex/config.toml` (currently `gpt-6.1-sol`/medium) for
this. **Tell the user each time you escalate**, with the reason and the
two failed attempts. A failed attempt is a diff that is rejected at review
or fails its acceptance checks. Models in the local cache:
`gpt-6.1-sol`, `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`, `gpt-5.6-sol`,
`gpt-5.6-terra`, `gpt-5.6-luna`. The user still has to choose the two tiers;
until then, ask before running Codex.

**Codex never commits to `main`** and never pushes. Workflow:

```powershell
$env:Path = "C:\Program Files\nodejs;$env:APPDATA\npm;$env:Path"
$task = "audio-wav-writer"
git worktree add "..\hunchback-wt-$task" -b "codex/$task" main
codex exec -C "..\hunchback-wt-$task" -s workspace-write `
  -m $model -c "model_reasoning_effort=`"$effort`"" `
  -o "..\hunchback-wt-$task.last.txt" "<prompt>"
```

- `codex exec` flags checked on codex-cli 0.163.0: `-C/--cd`, `-s/--sandbox
  read-only|workspace-write|danger-full-access`, `-m`, `-o/--output-last-message`,
  `--json`, `--ephemeral`, `--worktree` (Codex-managed). Use our own `git worktree`
  so that we choose the branch name and location. Recheck `codex exec --help`
  after upgrades. Never use `--dangerously-bypass-approvals-and-sandbox`.
- The prompt must be self-contained. Include the goal, the files in scope, the
  files that are out of scope, the acceptance checks to run, the instruction
  to follow `AGENTS.md`, and the instruction **not to commit** (leave changes
  in the worktree).
- Ignored local inputs are not in the worktree. Point Codex at them by
  absolute path rather than copying them: `MISTER_BDSM_PATH` to
  `<main>/MiSTer-BDSM` and the ROM zip by path. Never copy ROMs into tracked
  paths.
- **Review before merge (Claude):** read `git -C <wt> diff main` in full.
  Reject scope creep, weakened assertions, edited expected outputs, broad
  warning suppression and references to private material. Then run the
  AGENTS.md checks for the touched subsystem and the sound harness *yourself*
  in the worktree; Codex's own PASS claims don't count. Commit on
  `codex/<task>` with an honest message, merge into `main`, then
  `git worktree remove` and delete the branch.
- If the result is wrong, either reprompt Codex in the same worktree
  (`codex exec resume --last`) or discard the worktree. Never hand-patch a
  large Codex diff into `main` unreviewed.
