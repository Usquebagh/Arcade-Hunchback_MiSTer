#!/usr/bin/env python3
"""Native VHDL boundary checks; assertions and tool errors stay distinct."""
import argparse
from collections import Counter
from decimal import Decimal
import json
import re
from pathlib import Path
import subprocess
import sys


def emit(status, **details):
    print('BDSM ' + json.dumps(dict(status=status, **details)), flush=True)


CPU_EQ_WARNING = 'NUMERIC_STD."=": metavalue detected, returning FALSE'
CPU_TO_INTEGER_WARNING = 'NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0'
CPU_STARTUP_WARNING_PROFILE = Counter({
    (CPU_EQ_WARNING, 0): 8,
    (CPU_EQ_WARNING, 5): 1,
    (CPU_EQ_WARNING, 15): 2,
    (CPU_EQ_WARNING, 25): 1,
    (CPU_EQ_WARNING, 131): 1,
    (CPU_EQ_WARNING, 232): 1,
    (CPU_EQ_WARNING, 237): 1,
    (CPU_TO_INTEGER_WARNING, 46): 1,
    (CPU_TO_INTEGER_WARNING, 66): 1,
    (CPU_TO_INTEGER_WARNING, 86): 1,
    (CPU_TO_INTEGER_WARNING, 106): 1,
    (CPU_TO_INTEGER_WARNING, 126): 1,
    (CPU_TO_INTEGER_WARNING, 247): 1,
})


def classify_cpu_runtime_warnings(warnings, events):
    """Review only the frozen unknown-state diagnostics before software init."""
    markers = [e for e in events if e.get('status') == 'INFO' and
               e.get('label') == 'startup_status_initialized']
    if len(markers) != 1 or not isinstance(markers[0].get('time_ns'), int):
        return 'ERROR', {'reason': 'Missing or ambiguous CPU startup initialization marker'}

    boundary = Decimal(markers[0]['time_ns'])
    observed = Counter()
    before_startup = []
    after_startup = []
    unparsed = []
    time_re = re.compile(r'@([0-9]+(?:\.[0-9]+)?)(fs|ps|ns|us|ms|sec):')
    scales = {'fs':Decimal('0.000001'), 'ps':Decimal('0.001'), 'ns':Decimal(1),
              'us':Decimal(1000), 'ms':Decimal(1000000), 'sec':Decimal(1000000000)}
    for line in warnings:
        msg_match = re.search(r'\(assertion warning\):\s*(.*)$', line)
        time_match = time_re.search(line)
        if not msg_match or not time_match:
            unparsed.append(line)
            continue
        message = msg_match.group(1)
        time_ns = Decimal(time_match.group(1)) * scales[time_match.group(2)]
        observed[(message, int(time_ns))] += 1
        (before_startup if time_ns < boundary else after_startup).append(line)

    if not warnings:
        return 'PASS', {'observed': 'No native VHDL runtime warnings',
                        'startup_initialized_time_ns': int(boundary)}
    exact_reviewed_profile = observed == CPU_STARTUP_WARNING_PROFILE
    if exact_reviewed_profile and not after_startup and not unparsed:
        return 'PASS', {
            'observed': f'Reviewed {len(warnings)} known startup warnings before '
                        f'software status initialization at {int(boundary)} ns; none afterward',
            'reviewed_diagnostics': warnings,
            'startup_initialized_time_ns': int(boundary),
        }
    return 'WARNING', {
        'reason': 'Runtime warnings differ from the reviewed startup-only profile or occur after initialization',
        'observed': warnings,
        'startup_initialized_time_ns': int(boundary),
        'warnings_at_or_after_initialization': after_startup,
        'unparsed_warnings': unparsed,
    }


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
    stop_time = '30us' if args.mode in ['cpu_bus', 'cpu_diagnostics'] else '20us'
    command = ['ghdl', '-r', *options, top, '--assert-level=error', '--stop-time=' + stop_time]
    ran = subprocess.run(command, capture_output=True, text=True)
    print(ran.stdout, end=''); print(ran.stderr, end='', file=sys.stderr)
    events = [json.loads(line[5:]) for line in ran.stdout.splitlines() if line.startswith('BDSM ')]
    if not events or (events[-1]['status'], ran.returncode) not in [('PASS', 0), ('FAIL', 1)]:
        emit('ERROR', reason='VHDL simulator crashed or omitted consistent assertion result')
        return 2
    warnings = [line for line in (ran.stdout + ran.stderr).splitlines() if '(assertion warning)' in line]
    if args.mode == 'cpu_diagnostics' and events[-1]['status'] == 'PASS':
        status, details = classify_cpu_runtime_warnings(warnings, events)
        emit(status, **details)
        return 0
    events[-1]['runtime_warning_count'] = len(warnings)
    if args.mode == 'cpu_bus' and events[-1]['status'] == 'FAIL':
        # The directed bench is bounded; neither unbounded traces nor live ROMs
        # enter this harness. The bus suite gets extra time for growing coverage.
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
