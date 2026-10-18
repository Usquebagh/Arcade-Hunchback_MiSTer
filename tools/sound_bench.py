#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Run the actual CVS audio RTL with authenticated ROMs and a command timeline."""
import argparse
import csv
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import time
import wave

import numpy as np

sys.dont_write_bytecode = True
from prepare_hunchback import assemble, validated

ROOT = Path(__file__).resolve().parents[1]
MASTER = 57_272_724
ACK_BOUND = 9  # longest unmasked instruction path (6), opcode/INTER (2), trigger (1)
# cvs_cpu_reset holds the machine reset this many edges past core_reset, so the
# 48 kHz sampler (reset with the CPUs, as in the top level) starts that much later.
PRIME_CYCLES = 4
VHDL = [f'rtl/vendor/arcadia/{name}.vhd' for name in ('base_pack', 'sgs2650_pack', 'sgs2650')]
SV = [f'rtl/machine/{name}.sv' for name in (
    'cvs_cpu_reset', 'cvs_clock', 'cvs_audio_cpu', 'cvs_audio_bus', 'cvs_sync_rom', 'cvs_sync_ram_1p',
    'cvs_audio_samples', 'cvs_discrete_audio', 'cvs_audio_dc_blocker', 'cvs_audio_output')]
HARNESS = ['sim/harness/cvs_sound_bench.sv', 'sim/harness/sound_bench.cpp']
INPUTS = VHDL + SV + HARNESS + ['tools/sound_bench.py', 'tools/prepare_hunchback.py',
                              'tools/rom_manifest.json', 'sim/bdsm/adapter.json',
                              'sim/bdsm/check_connected.py', 'Arcade-Hunchback.sv',
                              'rtl/machine/cvs_av_machine.sv', 'rtl/machine/cvs_full_machine.sv',
                              'rtl/machine/cvs_main_io.sv']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def command_output(command):
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


def timeline(path, duration):
    rows = []
    with path.open(newline='') as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != ['seconds', 'command']:
            raise ValueError('Timeline header must be seconds,command')
        for row in reader:
            seconds, byte = float(row['seconds']), int(row['command'], 16)
            if not math.isfinite(seconds) or seconds < 0 or not 0 <= byte <= 255:
                raise ValueError('Invalid timeline seconds/command')
            edge = round(seconds * MASTER)
            if rows and edge <= rows[-1][0]:
                raise ValueError('Commands must have distinct, increasing master edges')
            rows.append((edge, byte))
    return [(edge, byte) for edge, byte in rows if edge < round(duration * MASTER)]


def build(threads, x_random, versions, hashes):
    work = ROOT / 'results/sound-bench-build' / f't{threads}-x{int(x_random)}'
    work.mkdir(parents=True, exist_ok=True)
    key = dict(sources=hashes, versions=versions, threads=threads, x_random=x_random)
    stamp = work / 'build.json'
    binary = work / 'obj/Vcvs_sound_bench'
    if stamp.exists() and binary.exists() and json.loads(stamp.read_text())['key'] == key:
        return binary, json.loads(stamp.read_text())
    # Build from a frozen copy: no source edits during compilation can mix identities.
    frozen = work / 'source'
    for name in INPUTS:
        target = frozen / name
        target.parent.mkdir(parents=True, exist_ok=True)
        data = (ROOT / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != hashes[name]:
            raise ValueError('Source changed while freezing: ' + name)
        target.write_bytes(data)
    synth = ['ghdl', '--synth', '--std=08', '--out=verilog', *VHDL, '-e', 'sgs2650']
    ran = subprocess.run(synth, cwd=frozen, capture_output=True, text=True)
    (work / 'synth.log').write_text(ran.stderr)
    if ran.returncode or not ran.stdout.strip():
        raise ValueError('Actual VHDL CPU synthesis failed: ' + str(work / 'synth.log'))
    cpu = work / 'sgs2650.v'
    cpu.write_text(re.sub(r'\bint\b', lambda _: '\\int ', ran.stdout))
    flags = ['verilator', '--cc', '--exe', '--build', '-j', '32', '--threads', str(threads),
             '--top-module', 'cvs_sound_bench', '-Wall', '-Wno-fatal',
             '--Mdir', str(work / 'obj'), '-CFLAGS',
             '-O3 -std=c++17 -Wall -Wextra -Werror' + (' -DSOUND_X_RANDOM' if x_random else '')]
    if x_random:
        flags += ['--x-initial', 'unique', '--x-assign', 'unique']
    flags += [str(frozen / HARNESS[0]), *[str(frozen / name) for name in SV],
              str(cpu), str(frozen / HARNESS[1])]
    print(f'Building threads={threads}, x_random={x_random}; log: {work / "compile.log"}', flush=True)
    with (work / 'compile.log').open('w') as log:
        result = subprocess.run(flags, cwd=frozen, stdout=log, stderr=subprocess.STDOUT)
    findings = re.findall(r'^%Warning-[^\n]+', (work / 'compile.log').read_text(), re.MULTILINE)
    bench_findings = [line for line in findings if 'sim/harness/' in line]
    if result.returncode or bench_findings:
        raise ValueError('Build failed or new bench has lint warnings: ' + str(work / 'compile.log'))
    metadata = dict(key=key, compile_command=flags, synth_command=synth,
                    synthesized_cpu_sha256=digest(cpu), compiler_findings=findings,
                    new_bench_warnings=bench_findings, compile_log=str(work / 'compile.log'))
    write_json(stamp, metadata)
    return binary, metadata


def check_run(output, rows, duration):
    with (output / 'irq-events.csv').open() as stream:
        irq = list(csv.DictReader(stream))
    acknowledgements = []
    previous = 0
    # Rising INTACK only; an already-high level must not satisfy a later command.
    ack_times = []
    irq_times = []
    last_ack = last_irq = 0
    for event in irq:
        if int(event['intack']) and not last_ack:
            ack_times.append(round(float(event['seconds']) * MASTER))
        if int(event['irq']) and not last_irq:
            irq_times.append(round(float(event['seconds']) * MASTER))
        last_ack, last_irq = int(event['intack']), int(event['irq'])
    for index, (edge, byte) in enumerate(rows):
        seconds = edge / MASTER
        end_edge = rows[index + 1][0] if index + 1 < len(rows) else round(duration * MASTER)
        rising = not previous & 128 and bool(byte & 128)
        ack_edge = next((t for t in ack_times if edge <= t < end_edge), None)
        irq_edge = next((t for t in irq_times if edge <= t < end_edge), None)
        ack = ack_edge / MASTER if ack_edge is not None else None
        irq_time = irq_edge / MASTER if irq_edge is not None else None
        latency = (ack_edge - edge) / 192 if ack_edge is not None else None
        passed = not rising or latency is not None and latency <= ACK_BOUND
        acknowledgements.append(dict(seconds=seconds, command=f'0x{byte:02x}', trigger=bool(rising),
                                     irq_seconds=irq_time, intack_seconds=ack,
                                     latency_audio_ce_periods=latency, passed=passed))
        previous = byte
    with (output / 'dac-events.csv').open() as stream:
        events = list(csv.DictReader(stream))
    for index, item in enumerate(acknowledgements):
        end_edge = rows[index + 1][0] if index + 1 < len(rows) else round(duration * MASTER)
        item['dac_events'] = sum(rows[index][0] <= round(float(e['seconds']) * MASTER) < end_edge for e in events)
    wavs = {}
    for name in ('mix', 'dac8', 'dac4'):
        with wave.open(str(output / (name + '.wav')), 'rb') as wav:
            if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getcomptype()) != (1, 2, 48000, 'NONE'):
                raise ValueError('Invalid WAV format: ' + name)
            count = wav.getnframes()
            data = wav.readframes(count)
            if len(data) != count * 2 or count != (round(duration * MASTER) - PRIME_CYCLES) * 48000 // MASTER:
                raise ValueError('Wrong WAV length: ' + name)
        samples = np.frombuffer(data, dtype='<i2').astype(np.float64)
        rms = [float(np.sqrt(np.mean(samples[i:i + 48000] ** 2)))
               for i in range(0, len(samples), 48000)]
        wavs[name] = dict(frames=count, rms_per_second_s16=rms, sha256=digest(output / (name + '.wav')))
    return dict(passed=all(item['passed'] for item in acknowledgements),
                commands=acknowledgements, wavs=wavs)


def run(binary, build_info, image, output, rows, duration, seed, x_random, reset_edges,
        release_ps, common):
    output.mkdir(parents=True, exist_ok=False)
    applied = [[edge / MASTER, f'0x{byte:02x}'] for edge, byte in rows]
    with (output / 'timeline.csv').open('w', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['seconds', 'command'])
        writer.writerows(applied)
    prepared = output / 'timeline-edges.txt'
    prepared.write_text(''.join(f'{edge} {byte}\n' for edge, byte in rows))
    command = [str(binary), str(image), str(prepared), str(output), str(round(duration * MASTER)),
               str(reset_edges), str(release_ps), f'+verilator+seed+{seed}']
    metadata = dict(common, source='rtl', sample_rate=48000, audio_cpu_cycle_hz=MASTER / 192,
                    duration_seconds=round(duration * MASTER) / MASTER,
                    timeline=applied, timeline_quantization_seconds=1 / MASTER,
                    seed=seed if x_random else None, x_random=x_random, build=build_info,
                    reset_edges_after_download=reset_edges, release_offset_ps=release_ps,
                    command=command, status='INCOMPLETE', notes=[
                        'Stage 1; speech PCM=0. Actual GHDL-synthesized S2650; no mock CPU or initialized work RAM.',
                        'audio_cpu_cycle counts pre-edge ce_audio_step pulses: master / (64 * 3) = 298295.4375 Hz, not board oscillator cycles.',
                        'seconds=0 is reset release (first active posedge is edge 0); seconds=edge/57272724. Commands use Python round(seconds*master). ROM download and reset hold are excluded, independent of reset pin sequencing.',
                        'MAME directed commands start at machine time zero with main CPU halted. RTL has no main CPU; pre-release download/reset time is not a command offset. Residual edge quantization is at most half a master period.',
                        *(['Revision unavailable: neither --revision nor HUNCHBACK_REV supplied; source hashes remain authoritative.'] if common['version'] == 'unknown' else []),
                        'ROM download and shared reset match cvs_av_machine; SENSE toggles every 75360 master edges.',
                        'WAV sampling uses pre-edge sample_ce/PCM, as synchronous consumers do. No DC removal or gain in captures.',
                        'Reset is held for the 4096-edge download plus 576..5760 extra master edges (3..30 audio CE periods); normal run uses 576.',
                        'Release offset is 1..8728 ps into the low clock half-cycle. The CPU reset tail (cvs_cpu_reset, as in the top level) also restarts cvs_clock: first audio CE is always edge 195; relative CE phase diversity is unavailable without changing wiring.',
                        'Host context time is diagnostic only; all scheduling and timestamps use integer nominal master edges.',
                        'INTACK bound is 9 audio CE periods: <=6 steps to finish longest indirect instruction, opcode acceptance + INTER acknowledgement (2), trigger-to-IRQ allowance (1). Assumes unmasked interrupts/ready=1; masked firmware still fails the command deadline.',
                        'Two-state randomized startup is diagnostic, not native X/Z, physical power-up, CDC, calibrated analog or hardware validation.',
                        'MAME comparison/scoring and 32-seed contract campaign are later stages; this run only checks bounded INTACK and file integrity.'])
    write_json(output / 'manifest.json', metadata)
    started = time.perf_counter()
    with (output / 'run.log').open('w') as log:
        result = subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT)
    metadata['wall_seconds'] = time.perf_counter() - started
    metadata['returncode'] = result.returncode
    if result.returncode:
        write_json(output / 'manifest.json', metadata)
        raise ValueError('Simulator failed: ' + str(output / 'run.log'))
    summary = check_run(output, rows, duration)
    metadata.update(summary=summary, stats=json.loads((output / 'run-stats.json').read_text()),
                    status='PASS' if summary['passed'] else 'FAIL')
    write_json(output / 'manifest.json', metadata)
    print(json.dumps(dict(output=str(output), wall_seconds=metadata['wall_seconds'],
                          status=metadata['status'], commands=summary['commands'],
                          mix_rms=summary['wavs']['mix']['rms_per_second_s16'])), flush=True)
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom', type=Path, required=True)
    parser.add_argument('--timeline', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--duration', type=float, default=7)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--x-random', action='store_true')
    parser.add_argument('--revision', default=os.environ.get('HUNCHBACK_REV') or 'unknown')
    parser.add_argument('--benchmark-threads', type=int, metavar='N',
                        help='opt in to a bit-identical 1-versus-N benchmark; use the faster model')
    parser.add_argument('--reset-stress', type=int, default=0)
    args = parser.parse_args()
    if not math.isfinite(args.duration) or not 0 < args.duration <= 3600:
        parser.error('Duration must be in (0,3600] seconds')
    if not 1 <= args.seed <= 2147483647 or not 0 <= args.reset_stress <= 10000:
        parser.error('Invalid seed or stress count')
    if args.benchmark_threads is not None and not 2 <= args.benchmark_threads <= 32:
        parser.error('Benchmark threads must be 2..32')
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / 'results') or output == ROOT / 'results':
        parser.error('Output must be a new directory under this repository’s ignored results/')
    if output.exists():
        parser.error('Output directory already exists; use a new directory to preserve captures')
    hashes = {name: digest(ROOT / name) for name in INPUTS}
    versions = {tool: command_output([tool, option]).splitlines()[0]
                for tool, option in [('verilator', '--version'), ('ghdl', '--version'),
                                     ('g++', '--version'), ('make', '--version')]}
    rom_manifest = json.loads((ROOT / 'tools/rom_manifest.json').read_text())
    archive = args.rom.resolve()
    archive_hash = digest(archive)
    image_bytes = assemble(validated(archive, rom_manifest), rom_manifest)
    if digest(archive) != archive_hash:
        raise ValueError('ROM archive changed during authentication')
    build_root = ROOT / 'results/sound-bench-build'
    build_root.mkdir(parents=True, exist_ok=True)
    image = build_root / ('image-' + hashlib.sha256(image_bytes).hexdigest() + '.bin')
    image.write_bytes(image_bytes)
    common = dict(version=args.revision, source_sha256=hashes,
                  tools=versions, rom_archive_sha256=archive_hash, image_sha256=digest(image),
                  rom_manifest_sha256=hashes['tools/rom_manifest.json'])
    rows = timeline(args.timeline, args.duration)
    selected = 1
    common['thread_benchmark'] = None
    if args.benchmark_threads is not None:
        multi = args.benchmark_threads
        binaries = {n: build(n, False, versions, hashes) for n in (1, multi)}
        perf_key = hashlib.sha256(json.dumps(dict(hashes=hashes, versions=versions, multi=multi), sort_keys=True).encode()).hexdigest()
        perf_dir = build_root / ('benchmark-' + perf_key)
        perf_file = perf_dir / 'threading.json'
        if perf_file.exists():
            perf = json.loads(perf_file.read_text())
        else:
            smoke = timeline(ROOT / 'sim/harness/timelines/smoke.csv', 7)
            measures = []
            for n in (1, multi):
                binary, info = binaries[n]
                measures.append(run(binary, info, image, perf_dir / f't{n}', smoke, 7, 1, False, 576, 1, common))
            same = all(digest(perf_dir / f't1/{name}') == digest(perf_dir / f't{multi}/{name}')
                       for name in ('dac-events.csv', 'irq-events.csv', 'mix.wav', 'dac8.wav', 'dac4.wav'))
            if not same:
                raise ValueError('Threading changed capture contents; see ' + str(perf_dir))
            times = {str(n): item['wall_seconds'] for n, item in zip((1, multi), measures)}
            perf = dict(wall_seconds=times, bit_identical=same,
                        selected_threads=min((1, multi), key=lambda n: times[str(n)]))
            write_json(perf_file, perf)
        print('Thread benchmark (7 s smoke): ' + json.dumps(perf), flush=True)
        selected = perf['selected_threads']
        common['thread_benchmark'] = perf
    binary, info = build(selected, args.x_random, versions, hashes)
    result = run(binary, info, image, output, rows, args.duration, args.seed,
                 args.x_random, 576, 1, common)
    success = result['summary']['passed']
    if args.reset_stress:
        binary, info = build(selected, True, versions, hashes)
        seeds = []
        def stress(seed):
            rng = random.Random(seed)
            reset_edges, release_ps = rng.randint(576, 5760), rng.randint(1, 8728)
            try:
                capture = run(binary, info, image, output / f'seed-{seed}', rows, args.duration,
                              seed, True, reset_edges, release_ps, common)
                return dict(seed=seed, reset_edges_after_download=reset_edges,
                            release_offset_ps=release_ps, status=capture['status'],
                            wall_seconds=capture['wall_seconds'],
                            stats=capture['stats'], commands=capture['summary']['commands'])
            except (ValueError, OSError) as exc:
                return dict(seed=seed, status='ERROR', reason=str(exc))
        # Independent processes; at most eight seeds and <=32 model threads.
        with ThreadPoolExecutor(max_workers=min(8, max(1, 32 // selected))) as pool:
            for item in pool.map(stress, range(1, args.reset_stress + 1)):
                seeds.append(item)
                success &= item['status'] == 'PASS'
                write_json(output / 'reset-stress.json', dict(ack_bound_audio_ce_periods=ACK_BOUND,
                           reset_extra_master_edges=[576, 5760], release_offset_ps=[1, 8728],
                           relative_ce_phase_varied=False, seeds=seeds,
                           passed=all(seed['status'] == 'PASS' for seed in seeds)))
    return 0 if success else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(2)
