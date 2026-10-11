#!/usr/bin/env python3
"""Native VHDL boundary checks; assertions and tool errors stay distinct."""
import argparse
import json
import re
from pathlib import Path
import subprocess
import sys


def emit(status, **details):
    print('BDSM ' + json.dumps(dict(status=status, **details)), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['cpu_alu', 'cpu_edges', 'cpu_bus', 'cpu_synth', 'cpu_diagnostics'])
    parser.add_argument('--seed', type=int, default=1)
    args = parser.parse_args()
    work = Path('build/bdsm-' + args.mode)
    work.mkdir(parents=True, exist_ok=True)
    top = {'cpu_alu':'s2650_alu_tb', 'cpu_edges':'s2650_edges_tb'}.get(args.mode,'s2650_bus_tb')
    sources = ['rtl/vendor/arcadia/base_pack.vhd', 'rtl/vendor/arcadia/sgs2650_pack.vhd',
               *(['rtl/vendor/arcadia/sgs2650.vhd'] if args.mode not in ['cpu_alu','cpu_edges'] else []),
               *(['sim/cpu/' + top + '.vhd'] if args.mode != 'cpu_synth' else [])]
    options = ['--std=08', '--workdir=' + str(work)]
    if args.mode == 'cpu_synth':
        command = ['ghdl', '--synth', '--std=08', '--out=verilog', *sources, '-e', 'sgs2650']
        ran = subprocess.run(command, capture_output=True, text=True)
        (work / 'synth.v').write_text(ran.stdout)
        (work / 'synth.log').write_text(ran.stderr)
        if ran.returncode or not ran.stdout.strip():
            emit('ERROR', reason='GHDL synthesis failed', diagnostics=[str((work / 'synth.log').resolve())])
            return 2
        # These are informational inferred-memory notes, individually reviewed.
        # Any other diagnostic is left unreviewed and blocks qualification.
        reviewed = re.compile(r'^rtl/vendor/arcadia/sgs2650.vhd:\d+:\d+:note: found (ROM "[^"]+", width: 70 bits, depth: 256|RAM "ras", width: 15 bits, depth: 8)\n[^\n]*\n[^\n]*\n',re.MULTILINE)
        unreviewed = reviewed.sub('',ran.stderr).strip()
        emit('WARNING' if unreviewed else 'PASS', observed=ran.stderr.strip() or 'Adapted S2650 and packages synthesize with GHDL',
             diagnostics=[str((work / 'synth.log').resolve())])
        return 0
    for command in [['ghdl', '-a', *options, *sources], ['ghdl', '-e', *options, top]]:
        ran = subprocess.run(command, capture_output=True, text=True)
        print(ran.stdout, end=''); print(ran.stderr, end='', file=sys.stderr)
        if ran.returncode:
            emit('ERROR', reason='VHDL analysis/elaboration failed')
            return 2
    command = ['ghdl', '-r', *options, top, '--assert-level=error', '--stop-time=20us']
    ran = subprocess.run(command, capture_output=True, text=True)
    print(ran.stdout, end=''); print(ran.stderr, end='', file=sys.stderr)
    events = [json.loads(line[5:]) for line in ran.stdout.splitlines() if line.startswith('BDSM ')]
    if not events or (events[-1]['status'], ran.returncode) not in [('PASS', 0), ('FAIL', 1)]:
        emit('ERROR', reason='VHDL simulator crashed or omitted consistent assertion result')
        return 2
    warnings = [line for line in (ran.stdout + ran.stderr).splitlines() if '(assertion warning)' in line]
    if args.mode == 'cpu_diagnostics' and events[-1]['status'] == 'PASS':
        emit('WARNING' if warnings else 'PASS', observed=warnings or 'No VHDL runtime warnings')
        return 0
    events[-1]['runtime_warning_count'] = len(warnings)
    if args.mode == 'cpu_bus' and events[-1]['status'] == 'FAIL':
        # The entire directed bench is <700 clocks; a 20us stop cap is 2000
        # 10ns clocks. Neither unbounded traces nor live ROMs enter this harness.
        trace = (work/'failure.vcd').resolve()
        replay = subprocess.run(command + ['--vcd=' + str(trace)],capture_output=True,text=True)
        replay_events = [json.loads(line[5:]) for line in replay.stdout.splitlines() if line.startswith('BDSM ')]
        if replay.returncode != 1 or not replay_events or replay_events[-1] != {k:v for k,v in events[-1].items() if k!='runtime_warning_count'}:
            emit('ERROR',reason='VHDL assertion did not reproduce during bounded trace replay')
            return 2
        events[-1]['diagnostics']=[str(trace)]
    emit(**events[-1])
    return ran.returncode


if __name__ == '__main__':
    raise SystemExit(main())
