#!/usr/bin/env python3
"""Hunchback-specific adapter; tool failures never become assertion failures."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def emit(status, **details):
    print('BDSM ' + json.dumps({'status': status, **details}), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['reset', 'clock', 'memory', 'banked', 'display', 'scan', 'character', 'character_connected', 'cold_connected', 'assembly_connected', 'bootstrap_connected', 'bootstrap_oracle', 'startup_connected', 'startup_oracle', 'audio_bus', 'audio_connected', 'main_bus', 'main_connected', 'video_connected', 's2636_objects', 's2636_connected', 'vblank_irq', 'video_timing', 'video_timing_alt', 'decode', 'lint', 'rom', 'mra', 'cpu_alu', 'cpu_edges', 'cpu_bus', 'cpu_synth', 'cpu_diagnostics'])
    parser.add_argument('--seed', type=int, default=1)
    args = parser.parse_args()
    adapter = Path(__file__).resolve().parent
    if args.mode in ['main_connected','video_connected','s2636_connected','character_connected','assembly_connected','bootstrap_connected','startup_connected','audio_connected','cold_connected']:
        return subprocess.run([sys.executable, str(adapter / 'check_connected.py'), '--mode', args.mode, '--seed', str(args.seed)]).returncode
    if args.mode=='bootstrap_oracle':
        return subprocess.run([sys.executable,str(adapter/'bootstrap_oracle_check.py')]).returncode
    if args.mode=='startup_oracle':
        return subprocess.run([sys.executable,str(adapter/'startup_oracle_check.py')]).returncode
    if args.mode.startswith('cpu_'):
        return subprocess.run([sys.executable, str(adapter / 'check_ghdl.py'), args.mode, '--seed', str(args.seed)]).returncode
    core = Path.cwd()
    work = core / 'build' / ('bdsm-' + args.mode)
    work.mkdir(parents=True, exist_ok=True)
    if args.mode in ('rom', 'mra'):
        # Preparation has already authenticated every required ROM against MAME.
        command = [sys.executable, 'tools/check_mra.py']
        if args.mode == 'rom':
            command += ['--image', 'build/roms/hunchback.bin']
        ran = subprocess.run(command, capture_output=True, text=True)
        print(ran.stdout, end=''); print(ran.stderr, end='', file=sys.stderr)
        return ran.returncode
    sources = {name: 'rtl/machine/cvs_' + name + '.sv' for name in ['reset', 'clock', 'memory', 'decode', 'video_timing', 'vblank_irq', 's2636_objects','audio_bus']}
    banked_sources = ['rtl/machine/cvs_main_memory.sv','rtl/machine/cvs_banked.sv','rtl/machine/cvs_memory.sv']
    bus_sources = ['rtl/machine/cvs_main_bus.sv','rtl/machine/cvs_main_io.sv',*banked_sources]
    character_sources = ['sim/cpu/cvs_character_tb.sv','rtl/machine/cvs_character_video.sv','rtl/machine/cvs_banked.sv']
    scan_sources=['rtl/machine/cvs_scan.sv',sources['video_timing']]
    join_sources=['rtl/machine/cvs_video_join.sv','rtl/machine/cvs_s2636_bank.sv',sources['s2636_objects'],'rtl/machine/cvs_character_video.sv']
    if args.mode == 'lint':
        warnings = []
        lint_sources = {**{('cvs_'+k):[v] for k,v in sources.items()}, 'cvs_main_memory':banked_sources,
                        'cvs_main_bus':bus_sources,
                        'cvs_s2636_bank':['rtl/machine/cvs_s2636_bank.sv',sources['s2636_objects']],
                        'cvs_character_tb':character_sources,'cvs_scan':scan_sources,'cvs_video_join':join_sources,
                        'cvs_character_video':['rtl/machine/cvs_character_video.sv']}
        for name, source in lint_sources.items():
            logfile = work / (name + '.log')
            with logfile.open('w') as log:
                ran = subprocess.run(['verilator', '--lint-only', '--top-module', name, '-Wall', '-Wno-fatal', *source], stdout=log, stderr=subprocess.STDOUT)
            if ran.returncode:
                emit('ERROR', reason='Lint could not complete', diagnostics=[str(logfile)])
                return 2
            warnings.extend(re.findall(r'%Warning-[^\n]+', logfile.read_text()))
        emit('WARNING' if warnings else 'PASS', observed=warnings or 'Configured SystemVerilog block tops have zero -Wall findings; actual mixed CPU hierarchy is separately compiled with Icarus -Wall')
        return 0
    mode = 'video_timing' if args.mode == 'video_timing_alt' else args.mode
    top = 'cvs_main_memory' if mode in ('banked','display') else 'cvs_character_tb' if mode=='character' else 'cvs_' + mode
    mode_sources = scan_sources if mode=='scan' else character_sources if mode=='character' else bus_sources if mode == 'main_bus' else banked_sources if mode in ('banked','display') else [sources[mode]]
    extra_options = ['-GV_LINES=317'] if args.mode == 'video_timing_alt' else []
    extra_cflags = ' -DV_LINES_EXPECTED=317' if args.mode == 'video_timing_alt' else ''
    with (work / 'compile.log').open('w') as log:
        ran = subprocess.run(['verilator', '--cc', '--exe', '--build', '--trace', '--trace-depth', '2',
                              '--top-module', top, '-Wall', '--Mdir', str(work), *extra_options,
                              '-CFLAGS', '-std=c++17 -I' + str(adapter) + extra_cflags, *mode_sources,
                              str(adapter / (mode + '.cpp'))], stdout=log, stderr=subprocess.STDOUT)
    if ran.returncode:
        emit('ERROR', reason='Verilator/C++ compilation failed', diagnostics=[str(work / 'compile.log')])
        return 2
    command = [str(work / ('V' + top)), '+verilator+seed+' + str(args.seed)]
    ran = subprocess.run(command, cwd=work, capture_output=True, text=True)
    events = [json.loads(line[5:]) for line in ran.stdout.splitlines() if line.startswith('BDSM ')]
    if not events or (events[-1]['status'], ran.returncode) not in [('PASS', 0), ('FAIL', 1)]:
        emit('ERROR', reason='Simulation crashed or omitted valid assertion result', observed=ran.stderr)
        return 2
    event = events[-1]
    if event['status'] == 'PASS' and mode in ('s2636_objects','character'):
        kind='sprite' if mode=='s2636_objects' else 'character'
        captures=[work/('synthetic-'+kind+'-frame.log'),work/('expected-'+kind+'-frame.log')]
        if any(not p.is_file() for p in captures):
            emit('ERROR', reason='Synthetic pixel diagnostic is missing')
            return 2
        event['diagnostics']=[str(p) for p in captures]
    if event['status'] == 'FAIL':
        replay = subprocess.run(command + ['--trace-start', str(max(0, event['cycle'] - 1024))], cwd=work, capture_output=True, text=True)
        replay_events = [json.loads(line[5:]) for line in replay.stdout.splitlines() if line.startswith('BDSM ')]
        if replay.returncode != 1 or not replay_events or replay_events[-1] != event:
            emit('ERROR', reason='Failure did not reproduce during trace replay')
            return 2
        event['diagnostics'] = [str(work / 'failure.vcd')]
    emit(**event)
    return ran.returncode


if __name__ == '__main__':
    raise SystemExit(main())
