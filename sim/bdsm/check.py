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
    parser.add_argument('mode', choices=['reset', 'clock', 'memory', 'decode', 'lint', 'rom', 'mra'])
    parser.add_argument('--seed', type=int, default=1)
    args = parser.parse_args()
    adapter = Path(__file__).resolve().parent
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
    sources = {name: 'rtl/machine/cvs_' + name + '.sv' for name in ['reset', 'clock', 'memory', 'decode']}
    if args.mode == 'lint':
        warnings = []
        for name, source in sources.items():
            logfile = work / (name + '.log')
            with logfile.open('w') as log:
                ran = subprocess.run(['verilator', '--lint-only', '--top-module', 'cvs_' + name, '-Wall', '-Wno-fatal', source], stdout=log, stderr=subprocess.STDOUT)
            if ran.returncode:
                emit('ERROR', reason='Lint could not complete', diagnostics=[str(logfile)])
                return 2
            warnings.extend(re.findall(r'%Warning-[^\n]+', logfile.read_text()))
        emit('WARNING' if warnings else 'PASS', observed=warnings or 'All implemented modules have zero -Wall findings')
        return 0
    top = 'cvs_' + args.mode
    with (work / 'compile.log').open('w') as log:
        ran = subprocess.run(['verilator', '--cc', '--exe', '--build', '--trace', '--trace-depth', '2',
                              '--top-module', top, '-Wall', '--Mdir', str(work),
                              '-CFLAGS', '-std=c++17 -I' + str(adapter), sources[args.mode],
                              str(adapter / (args.mode + '.cpp'))], stdout=log, stderr=subprocess.STDOUT)
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
