#!/usr/bin/env python3
"""Mixed-language synthetic machine: synthesize actual VHDL, execute actual SV."""
import argparse
import json
from pathlib import Path
import re
import subprocess
from check_ghdl import emit


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--mode', choices=['main_connected','video_connected'], default='main_connected')
    args = parser.parse_args()
    work = Path('build/bdsm-' + args.mode).resolve()
    work.mkdir(parents=True, exist_ok=True)
    cpu_sources = ['rtl/vendor/arcadia/base_pack.vhd', 'rtl/vendor/arcadia/sgs2650_pack.vhd',
                   'rtl/vendor/arcadia/sgs2650.vhd']
    ran = subprocess.run(['ghdl','--synth','--std=08','--out=verilog',*cpu_sources,'-e','sgs2650'],
                         capture_output=True,text=True)
    (work/'synth.log').write_text(ran.stderr)
    if ran.returncode or not ran.stdout.strip():
        emit('ERROR',reason='Connected CPU synthesis failed',diagnostics=[str(work/'synth.log')])
        return 2
    # Same individually reviewed inferred ROM/stack notes as native synthesis.
    reviewed = re.compile(r'^rtl/vendor/arcadia/sgs2650.vhd:\d+:\d+:note: found (ROM "[^"]+", width: 70 bits, depth: 256|RAM "ras", width: 15 bits, depth: 8)\n[^\n]*\n[^\n]*\n',re.MULTILINE)
    diagnostics = reviewed.sub('',ran.stderr).strip()
    # GHDL emits the legal VHDL port "int" as a bare Verilog identifier; it is a
    # SystemVerilog keyword. Escape only this identifier, without logic edits.
    generated = re.sub(r'\bint\b',lambda _: '\\int ',ran.stdout)
    cpu_file=work/'sgs2650.v'
    cpu_file.write_text(generated)
    sources=['rtl/machine/cvs_main.sv','rtl/machine/cvs_main_bus.sv','rtl/machine/cvs_main_io.sv',
             'rtl/machine/cvs_main_memory.sv','rtl/machine/cvs_banked.sv',
             'rtl/machine/cvs_memory.sv','rtl/machine/cvs_clock.sv']
    top = 'cvs_video_cpu_tb' if args.mode=='video_connected' else 'cvs_main_tb'
    if args.mode=='video_connected':
        sources += ['rtl/machine/cvs_video_timing.sv','rtl/machine/cvs_vblank_irq.sv']
    sources += ['sim/cpu/'+top+'.sv']
    compile_run=subprocess.run(['iverilog','-g2012','-Wall','-s',top,'-o',str(work/'test.vvp'),
                                str(cpu_file),*sources],capture_output=True,text=True)
    (work/'compile.log').write_text(compile_run.stdout+compile_run.stderr)
    if compile_run.returncode:
        emit('ERROR',reason='Connected simulation compilation failed',diagnostics=[str(work/'compile.log')])
        return 2
    diagnostics += compile_run.stdout+compile_run.stderr
    command=['vvp',str(work/'test.vvp')]
    ran=subprocess.run(command,cwd=work,capture_output=True,text=True)
    (work/'run.log').write_text(ran.stdout+ran.stderr)
    events=[json.loads(line[5:]) for line in ran.stdout.splitlines() if line.startswith('BDSM ')]
    # Icarus $finish argument is diagnostic level, not process exit status;
    # consistent structured events plus a clean vvp exit determine the result.
    if ran.returncode or not events or events[-1]['status'] not in ('PASS','FAIL'):
        emit('ERROR',reason='Connected run failed or did not complete',diagnostics=[str(work/'run.log')])
        return 2
    event=events[-1]
    if event['status']=='FAIL':
        trace_start=max(1,event['cycle']-1024)
        replay=subprocess.run(command+['+trace_start='+str(trace_start)],cwd=work,capture_output=True,text=True)
        replay_events=[json.loads(line[5:]) for line in replay.stdout.splitlines() if line.startswith('BDSM ')]
        if replay.returncode or not replay_events or replay_events[-1]!=event:
            emit('ERROR',reason='Connected assertion did not reproduce during bounded trace replay')
            return 2
        event['diagnostics']=[str(work/'failure.vcd')]
        emit(**event)
        return 1
    if diagnostics.strip():
        emit('WARNING',observed=diagnostics.strip(),diagnostics=[str(work/'synth.log'),str(work/'compile.log')])
    else:
        emit(**event)
    return 0


if __name__=='__main__':
    raise SystemExit(main())
