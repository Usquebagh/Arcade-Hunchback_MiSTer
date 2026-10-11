#!/usr/bin/env python3
"""Mixed-language synthetic machine: synthesize actual VHDL, execute actual SV."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from check_ghdl import emit


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--mode', choices=['main_connected','video_connected','s2636_connected','character_connected','assembly_connected','bootstrap_connected','startup_connected','audio_connected','av_connected','cold_connected'], default='main_connected')
    args = parser.parse_args()
    work = Path('build/bdsm-' + args.mode).resolve()
    work.mkdir(parents=True, exist_ok=True)
    bootstrap=False
    startup=None
    if args.mode=='startup_connected':
        # Resolve the model from the frozen core, so source mutations are real.
        sys.path.insert(0,str(Path.cwd()/'sim/bdsm'))
        from startup_model import expectations
        try:
            startup=expectations('build/roms/hunchback.bin',work/'startup.expect')
        except (ValueError,OSError) as exc:
            emit('ERROR',reason='Independent startup preparation failed: '+str(exc))
            return 2
    if args.mode=='bootstrap_connected':
        from bootstrap_model import expectations
        try:
            expectations('build/roms/hunchback.bin',work/'bootstrap.expect')
        except (ValueError,OSError) as exc:
            emit('ERROR',reason='Independent bootstrap preparation failed: '+str(exc))
            return 2
        bootstrap=True
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
    top = {'video_connected':'cvs_video_cpu_tb','s2636_connected':'cvs_s2636_cpu_tb','character_connected':'cvs_character_cpu_tb','cold_connected':'cvs_cold_cpu_tb','assembly_connected':'cvs_machine_tb','bootstrap_connected':'cvs_machine_tb','startup_connected':'cvs_startup_tb'}.get(args.mode,'cvs_main_tb')
    if args.mode=='audio_connected':
        top='cvs_audio_cpu_tb'
        sources=['rtl/machine/cvs_audio_cpu.sv','rtl/machine/cvs_audio_bus.sv','rtl/machine/cvs_clock.sv']
    if args.mode=='video_connected':
        sources += ['rtl/machine/cvs_video_timing.sv','rtl/machine/cvs_vblank_irq.sv']
    if args.mode=='s2636_connected':
        sources += ['rtl/machine/cvs_s2636_objects.sv','rtl/machine/cvs_s2636_bank.sv']
    if args.mode=='character_connected':
        sources += ['rtl/machine/cvs_character_video.sv']
    if args.mode in ('assembly_connected','bootstrap_connected','startup_connected','av_connected'):
        sources += ['rtl/machine/cvs_machine.sv','rtl/machine/cvs_scan.sv','rtl/machine/cvs_video_timing.sv',
                    'rtl/machine/cvs_vblank_irq.sv','rtl/machine/cvs_video_join.sv',
                    'rtl/machine/cvs_s2636_bank.sv','rtl/machine/cvs_s2636_objects.sv','rtl/machine/cvs_character_video.sv']
    if args.mode=='av_connected':
        top='cvs_av_machine_tb'
        sources += ['rtl/machine/cvs_av_machine.sv','rtl/machine/cvs_audio_cpu.sv','rtl/machine/cvs_audio_bus.sv']
    sources += ['sim/cpu/'+top+'.sv']
    compile_run=subprocess.run(['iverilog','-g2012','-Wall','-s',top,'-o',str(work/'test.vvp'),
                                str(cpu_file),*sources],capture_output=True,text=True)
    (work/'compile.log').write_text(compile_run.stdout+compile_run.stderr)
    if compile_run.returncode:
        emit('ERROR',reason='Connected simulation compilation failed',diagnostics=[str(work/'compile.log')])
        return 2
    reviewed_messages=[]
    # These individually reviewed notices describe correct implicit sensitivity:
    # a variable-index combinational read must react to every entry. Keep their
    # exact text in the result/log; every other diagnostic remains unreviewed.
    array_note=re.compile(r"rtl/machine/cvs_s2636_objects\.sv:\d+: warning: @\* is sensitive to all (256 words in array 'registers'|4 words in array '(active_duplicate|duplicate_hc|render_row|scale|active_line|in_object|next_row)')\.")
    for line in (compile_run.stdout+compile_run.stderr).splitlines():
        if args.mode in ('s2636_connected','assembly_connected','bootstrap_connected','startup_connected','av_connected') and array_note.fullmatch(line):
            reviewed_messages.append({'message':line,'review':'Full-array sensitivity is required for the declared combinational indexed register/engine read; Verilator -Wall finds no latch or sensitivity fault.'})
        else:
            diagnostics += line+'\n'
    command=['vvp',str(work/'test.vvp')]
    if bootstrap:
        command += ['+boot','+image='+str(Path('build/roms/hunchback.bin').resolve()),'+expect='+str(work/'bootstrap.expect')]
    if startup:
        command += ['+image='+str(Path('build/roms/hunchback.bin').resolve()),'+expect='+str(work/'startup.expect'),
                    '+count='+str(startup['writes']),'+resume='+str(startup['resume'])]
    ran=subprocess.run(command,cwd=work,capture_output=True,text=True)
    (work/'run.log').write_text(ran.stdout+ran.stderr)
    events=[json.loads(line[5:]) for line in ran.stdout.splitlines() if line.startswith('BDSM ')]
    # Icarus $finish argument is diagnostic level, not process exit status;
    # consistent structured events plus a clean vvp exit determine the result.
    if ran.returncode or not events or events[-1]['status'] not in ('PASS','FAIL'):
        emit('ERROR',reason='Connected run failed or did not complete',diagnostics=[str(work/'run.log')])
        return 2
    event=events[-1]
    if reviewed_messages:
        event['reviewed_diagnostics']=reviewed_messages
    if event['status']=='FAIL':
        trace_start=max(1,event['cycle']-1024)
        replay=subprocess.run(command+['+trace_start='+str(trace_start)],cwd=work,capture_output=True,text=True)
        replay_events=[json.loads(line[5:]) for line in replay.stdout.splitlines() if line.startswith('BDSM ')]
        assertion_event={k:v for k,v in event.items() if k!='reviewed_diagnostics'}
        if replay.returncode or not replay_events or replay_events[-1]!=assertion_event:
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
