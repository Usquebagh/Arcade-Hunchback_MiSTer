#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Capture private hunchbak command/DAC timelines and audio with MAME Lua."""
import argparse
from bisect import bisect_right
from collections import Counter
import csv
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import time
import wave
import xml.etree.ElementTree as ET
import zipfile

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PIN = 'c806573e925ce00fe3e8d8fe417eba63f83275ce'


def read_timeline(path):
    with path.open(newline='') as stream:
        reader = csv.DictReader(stream)
        if reader.fieldnames != ['seconds', 'command']:
            raise ValueError('timeline header must be seconds,command')
        rows = []
        for row in reader:
            seconds, command = float(row['seconds']), int(row['command'], 0)
            if not math.isfinite(seconds) or seconds < 0 or not 0 <= command <= 255:
                raise ValueError('timeline requires finite nonnegative times and byte commands')
            if rows and seconds < rows[-1][0]:
                raise ValueError('timeline times must be ordered')
            rows.append([seconds, f'0x{command:02x}'])
    return rows


def lua_string(value):
    # Long bracket strings avoid shell quoting and Lua/JSON escape differences.
    delimiter = '='
    while ']' + delimiter + ']' in value:
        delimiter += '='
    return '[' + delimiter + '[' + value + ']' + delimiter + ']'


def identity(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--timeline', type=Path)
    mode.add_argument('--record', type=float, metavar='SECONDS')
    parser.add_argument('--mame', default='mame')
    parser.add_argument('--duration', type=float, metavar='S')
    parser.add_argument('--throttle', action='store_true', help='run at real time for reference calibration')
    args = parser.parse_args()
    requested = read_timeline(args.timeline) if args.timeline else []
    duration = args.duration if args.duration is not None else (
        args.record if args.record is not None else (requested[-1][0] if requested else 0) + 3)
    if not math.isfinite(duration) or duration <= 0:
        parser.error('duration must be positive and finite')
    if args.record is not None and (not math.isfinite(args.record) or args.record <= 0):
        parser.error('record seconds must be positive and finite')
    if args.record is not None and duration != args.record:
        parser.error('--duration must equal --record when both are specified')
    if requested and requested[-1][0] >= duration:
        parser.error('duration must extend beyond the final command')
    out = args.output.resolve()
    if not out.is_relative_to(ROOT / 'results'):
        parser.error('all capture outputs must be under this checkout\'s ignored results/')
    if out.exists():
        parser.error('choose a new output directory; captures are never overwritten')
    rom_dir = args.rom_dir.resolve()
    rom = rom_dir / 'hunchbak.zip'
    # Authenticate in place; never extract/copy the user archive.
    rom_manifest = json.loads((ROOT / 'tools/rom_manifest.json').read_text())
    with zipfile.ZipFile(rom) as archive:
        for entry in rom_manifest['roms']:
            data = archive.read(entry['name'])
            if len(data) != entry['bytes'] or hashlib.sha1(data).hexdigest() != entry['sha1']:
                raise ValueError('ROM authentication failed: ' + entry['name'])
    binary = shutil.which(args.mame)
    if binary is None:
        parser.error('MAME executable not found: ' + args.mame)
    binary = str(Path(binary).resolve())
    version = subprocess.check_output([binary, '-version'], text=True).strip()
    xml = ET.fromstring(subprocess.check_output([binary, 'hunchbak', '-noreadconfig', '-listxml'], text=True))
    system = next(m for m in xml.findall('machine') if m.get('name') == 'hunchbak')
    audio = next(c for c in system.findall('chip') if c.get('tag') == 'audiocpu')
    cycle_hz = int(audio.attrib['clock'])
    out.mkdir(parents=True)
    script = ROOT / 'tools/mame/hunchbak_sound.lua'
    table = ',\n'.join(f'{{{seconds:.17g}, {command}}}' for seconds, command in requested)
    config = out / 'capture-config.lua'
    config.write_text('return {\noutput=' + lua_string(str(out)) + ',\nmode=' +
                      lua_string('directed' if args.timeline else 'record') +
                      f',\ncapture_seconds={math.ceil(duration)},\ncycle_hz={cycle_hz},\ntimeline={{\n{table}\n}}\n}}\n')
    command = [binary, 'hunchbak', '-noreadconfig', '-rompath', str(rom_dir),
               '-video', 'none', '-sound', 'none', '-throttle' if args.throttle else '-nothrottle', '-samplerate', '48000',
               '-wavwrite', str(out / 'mix.wav'), '-seconds_to_run', str(math.ceil(duration)),
               '-autoboot_delay', '0', '-autoboot_script', str(script), '-skip_gameinfo',
               '-noautosave', '-norewind', '-noplugins', '-nojoystick']
    for option in ['cfg', 'nvram', 'snapshot', 'diff', 'input', 'state']:
        directory = out / option
        directory.mkdir()
        command += ['-' + option + '_directory', str(directory)]
    env = os.environ.copy()
    env['HUNCHBAK_CAPTURE_CONFIG'] = str(config)
    notes = [
        'MAME compatibility only; binary revision is not authenticated as pinned ' + PIN + '.',
        'audio_cpu_cycle=floor(machine.time.as_double()*audio_cpu_cycle_hz); '
        'Lua exposes no total_cycles. This is elapsed clock cycles, including HALT, not executed instructions.',
        'cvs.cpp configures audio S2650 at integer 14318181/16=894886 Hz; '
        's2650.cpp instruction budgets count clock cycles (6/9/etc), with no clock-to-cycle divider. '
        'Rate is read from this binary\'s -listxml, not guessed from RTL /192 enables.',
        'Audio IRQ/INTACK callback is not exposed by these Lua device APIs; no irq-events.csv.',
        'Pinned beep0..2 cannot be muted with the documented Lua sound/device APIs. '
        'All beeper-affecting writes to 1840 and 1884..1887 remain in dac-events.csv.',
        'WAV includes the driver\'s complete mixer, including speech and placeholder effects; no analog claim.',
        'MAME -sound none retains WAV generation (verified on 0.264). '
        'WAV writer stereo is converted by integer channel mean to mono signed 16-bit; raw-mix.wav retained.',
        '-seconds_to_run takes whole seconds; request is rounded up; actual WAV length is recorded.',
    ]
    if version.startswith('0.264'):
        notes += ['DEVELOPMENT ONLY: MAME 0.264 is NOT the pinned reference. src/mame/cvs/cvs.cpp '
                  'has main /16, level-sensitive command bit-7 IRQ (INTACK clears), different S2650 code, '
                  '60 Hz video and DAC3 placeholder; pinned src/mame/misc/cvs.cpp uses main /8, '
                  'rising-bit-7 IRQ, 50 Hz and beep0..2. No beep devices exist in 0.264.']
    if args.timeline:
        notes += ['seconds=0 is MAME machine start/reset, verified by lua-status start_seconds=0. Commands use scheduler timers from that origin; no game warm-up offset.',
                  'Main CPU is stopped before its first instruction with an all-program HALT read tap '
                  'and PS bit 0x2000 (PSU.II) set. ROMs unchanged; no main/game initialization, video or '
                  'speech commands from gameplay. Audio and speech CPUs continue. Commands use '
                  'maincpu.spaces.data:write_u8(0,value), invoking the real driver handler. '
                  'Pinned handler ignores unchanged values; 0.264 does not.']
    else:
        notes += ['Scripted inputs: coin 3.0..3.2 s, start 4.0..4.2 s; right from 15 s, '
                  'jump 0.18 s every 1.2 s thereafter, sampled at frame boundaries. '
                  'timeline.csv records every main control write, including duplicates. '
                  'sprite-positions.csv observes bank-0 S2636 HC/VC writes; movement alone '
                  'is supporting evidence, not proof of player identity or a completed level.']
    manifest = dict(source='mame', version=version, sample_rate=48000,
                    audio_cpu_cycle_hz=cycle_hz, duration_seconds=None,
                    requested_duration_seconds=duration, timeline=[], seed=None, notes=notes,
                    status='RUNNING', rom_sha256=identity(rom), mame_binary_sha256=identity(Path(binary)),
                    source_sha256={str(p.relative_to(ROOT)): identity(p) for p in
                                   [Path(__file__).resolve(), script, ROOT / 'tools/rom_manifest.json']},
                    requested_timeline=requested, command=command)
    manifest_path = out / 'manifest.json'
    def save():
        manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    save()
    start = time.monotonic()
    try:
        with (out / 'mame.log').open('w') as log:
            result = subprocess.run(command, env=env, cwd=out, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=max(120, duration * 10))
        manifest['mame_wall_seconds'] = time.monotonic() - start
        log = (out / 'mame.log').read_text()
        if result.returncode or any(s in log for s in ['[LUA ERROR]', 'Error running autoboot', 'Fatal error']):
            raise RuntimeError('MAME/Lua failed; see mame.log')
        status = dict(line.split('=', 1) for line in (out / 'lua-status.txt').read_text().splitlines() if '=' in line)
        manifest['lua_status'] = status
        if float(status.get('start_seconds', 'inf')) != 0 or 'end_seconds' not in status:
            raise RuntimeError('capture did not run from time zero to normal stop')
        if int(status['unexpected_main_commands']):
            raise RuntimeError('directed main-CPU isolation failed')
        applied = read_timeline(out / 'timeline.csv')
        manifest['timeline'] = applied
        if args.timeline and (len(applied) != len(requested) or any(
                abs(a[0] - b[0]) > 1e-8 or a[1] != b[1] for a, b in zip(applied, requested))):
            raise RuntimeError('applied timeline differs from requested timeline')
        raw = out / 'raw-mix.wav'
        (out / 'mix.wav').rename(raw)
        with wave.open(str(raw), 'rb') as wav:
            channels, width, rate, frames, compression, _ = wav.getparams()
            if width != 2 or rate != 48000 or compression != 'NONE' or channels not in (1, 2) or not frames:
                raise RuntimeError('invalid MAME PCM WAV')
            samples = np.frombuffer(wav.readframes(frames), dtype='<i2').reshape(-1, channels)
        if frames < duration * rate:
            raise RuntimeError('WAV is shorter than requested capture')
        mono = np.floor_divide(samples.astype(np.int32).sum(axis=1), channels).astype('<i2')
        with wave.open(str(out / 'mix.wav'), 'wb') as wav:
            wav.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
            wav.writeframes(mono.tobytes())
        manifest['duration_seconds'] = frames / rate
        manifest['raw_wav_channels'] = channels
        manifest['rms_per_second_pcm16'] = [float(np.sqrt(np.mean(block.astype(float) ** 2)))
            for block in np.array_split(mono, np.arange(rate, frames, rate))]
        command_times = [t for t, _ in applied]
        counts = [0] * len(applied)
        event_count, before_first, last = 0, 0, -1.0
        placeholder_writes = Counter()
        with (out / 'dac-events.csv').open() as stream:
            reader = csv.DictReader(stream)
            if reader.fieldnames != ['seconds', 'audio_cpu_cycle', 'address', 'value']:
                raise RuntimeError('invalid DAC event header')
            for row in reader:
                t, address, value = float(row['seconds']), int(row['address'], 0), int(row['value'], 0)
                if not (last <= t < frames / rate and 0 <= value <= 255 and
                        (address == 0x1840 or 0x1880 <= address <= 0x1887)):
                    raise RuntimeError('invalid DAC event')
                if abs(int(row['audio_cpu_cycle']) - math.floor(t * cycle_hz)) > 1:
                    raise RuntimeError('invalid derived DAC cycle')
                last = t
                event_count += 1
                index = bisect_right(command_times, t) - 1
                if index >= 0:
                    counts[index] += 1
                else:
                    before_first += 1
                if address == 0x1840 or address >= 0x1884:
                    placeholder_writes[f'0x{address:04x}'] += 1
        manifest['rms_ac_per_second_pcm16'] = [float(np.std(block.astype(float)))
            for block in np.array_split(mono, np.arange(rate, frames, rate))]
        manifest['dac_event_count'] = event_count
        manifest['command_write_counts'] = dict(Counter(command for _, command in applied))
        if args.record is not None:
            # Keep the observed register evidence explicit; do not declare gameplay PASS.
            with (out / 'sprite-positions.csv').open() as stream:
                positions = [row for row in csv.DictReader(stream)
                             if row['pvi'] == '1' and row['object'] == '0']
            before = [row for row in positions if float(row['seconds']) < 15]
            evidence = {'pvi': 1, 'object': 0, 'before_input': before[-1] if before else None,
                        'first_changed_after_input': None}
            if before:
                initial = (before[-1]['x'], before[-1]['y'])
                evidence['first_changed_after_input'] = next((row for row in positions
                    if 15 <= float(row['seconds']) < 16 and (row['x'], row['y']) != initial), None)
            manifest['movement_observation'] = evidence
        manifest['dac_events_before_first_command'] = before_first
        manifest['dac_events_per_command'] = counts
        manifest['placeholder_affecting_write_counts'] = dict(placeholder_writes)
        manifest['status'] = 'COMPLETED_DEVELOPMENT_CAPTURE' if version.startswith('0.264') else 'COMPLETED_UNVERIFIED_REFERENCE'
        manifest['output_sha256'] = {name: identity(out / name) for name in
                                    ['timeline.csv', 'dac-events.csv', 'mix.wav', 'raw-mix.wav']}
        manifest['wall_seconds'] = time.monotonic() - start
        save()
        print(json.dumps({key: manifest[key] for key in ['status', 'version', 'wall_seconds',
              'duration_seconds', 'dac_event_count', 'rms_per_second_pcm16']}, indent=2))
        print('Manifest:', manifest_path)
    except Exception as exc:
        manifest.update(status='FAILED', error=str(exc), wall_seconds=time.monotonic() - start)
        save()
        raise


if __name__ == '__main__':
    main()
