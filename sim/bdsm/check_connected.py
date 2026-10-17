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
    parser.add_argument('--mode', choices=['main_connected','video_connected','s2636_connected','character_connected','assembly_connected','bootstrap_connected','startup_connected','audio_connected','speech_connected','tms5100_connected','speech_machine_connected','full_connected','mister_shell_connected','mister_shell_behavior_connected','av_connected','cold_connected'], default='main_connected')
    args = parser.parse_args()
    work = Path('build/bdsm-' + args.mode).resolve()
    work.mkdir(parents=True, exist_ok=True)
    if args.mode=='mister_shell_behavior_connected':
        shell=Path('Arcade-Hunchback.sv').read_text()
        ranges=[(int(first),int(second) if second else int(first))
                for first,second in re.findall(r'"O\[(\d+)(?::(\d+))?\]',shell)]
        if any(min(first,second)==0 for first,second in ranges) or not re.search(r'"R(?:\[)?0(?:\])?,Reset;"', shell):
            emit('FAIL',label='mister_status_reserved',cycle=0,expected=1,observed=0)
            return 1
        conf=shell.split('localparam CONF_STR=',1)[1].split('};',1)[0]
        options=re.findall(r'"O\[(\d+)(?::(\d+))?\]',conf)
        status_bits=[]
        for first,last in options:
            lo,hi=sorted((int(first),int(last) if last else int(first)))
            status_bits.extend(range(lo,hi+1))
        if len(status_bits)!=len(set(status_bits)) or status_bits!=sorted(status_bits):
            emit('FAIL',label='mister_status_index_order',cycle=0,expected=1,observed=0)
            return 1
        if '"O[13:12],Orientation,Rotate CW,Rotate CCW,Native;"' in conf:
            emit('FAIL',label='mister_native_orientation_removed',cycle=0,expected=1,observed=0)
            return 1
        reset_items=re.findall(r'"([RT])(?:\[(\d+)\]|(\d+)),Reset;"',conf)
        reset_items=[(kind,bracketed or legacy) for kind,bracketed,legacy in reset_items]
        if reset_items!=[('R','0')] or 'status[0]' not in shell.split('wire reset_async=',1)[1].split(';',1)[0]:
            emit('FAIL',label='mister_single_reset_binding',cycle=0,expected=1,observed=len(reset_items))
            return 1
        reset_pos=conf.find('"R[0],Reset;"')
        cheat_pos=conf.find('"C,Cheats;"')
        jline=re.search(r'"J1,([^\"]+)"',conf)
        jnline=re.search(r'"jn,([^\"]+)"',conf)
        j_pos=conf.find('"J1,')
        jn_pos=conf.find('"jn,')
        version_pos=conf.find('"V,')
        if (reset_pos < 0 or cheat_pos < 0 or j_pos < 0 or jn_pos < j_pos or
            version_pos < jn_pos or reset_pos > j_pos or cheat_pos > j_pos or
            conf.find('"C,Cheats;"',cheat_pos+1) >= 0 or
            not re.search(r'"V,[^\"]*;"\s*$',conf)):
            emit('FAIL',label='mister_menu_action_order',cycle=0,expected=1,observed=0)
            return 1
        expected_slots=['Jump','Start 2','Start 1','Coin']
        mra=Path('releases/Hunchback (CVS).mra').read_text()
        mra_buttons=re.search(r'<buttons names="([^"]+)" default="([^"]+)"',mra)
        if (not jline or jline.group(1).split(';')[0].split(',')!=expected_slots or
            not jnline or jnline.group(1).split(';')[0].split(',')!=['A','X','Start','Select'] or
            not mra_buttons or mra_buttons.groups()!=('Jump,Start 2,Start 1,Coin','A,X,Start,Select')):
            emit('FAIL',label='mister_conf_button_order',cycle=0,expected=1,observed=0)
            return 1
        executable=work/'screen_rotate_dimensions.vvp'
        compile_result=subprocess.run(['iverilog','-g2012','-s','screen_rotate_dimensions_tb','-o',str(executable),
            'rtl/machine/cvs_rotation_raster.sv','sys/arcade_video.v','sim/cpu/screen_rotate_dimensions_tb.sv'],
            capture_output=True,text=True)
        if compile_result.returncode:
            emit('ERROR',reason='Rotation dimension test compile failed: '+compile_result.stderr[-2000:])
            return 2
        run_result=subprocess.run(['vvp',str(executable)],capture_output=True,text=True)
        print(run_result.stdout,end='')
        if run_result.returncode:
            if run_result.stderr: print(run_result.stderr,file=sys.stderr,end='')
            return run_result.returncode
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
    sync_ram_sources=['rtl/machine/cvs_sync_ram_1p.sv','rtl/machine/cvs_sync_ram_2p.sv','rtl/machine/cvs_sync_rom.sv']
    sources=['rtl/machine/cvs_main.sv','rtl/machine/cvs_main_bus.sv','rtl/machine/cvs_cheat_engine.sv','rtl/machine/cvs_main_io.sv',
             'rtl/machine/cvs_main_memory.sv','rtl/machine/cvs_banked.sv',
             'rtl/machine/cvs_memory.sv',*sync_ram_sources,'rtl/machine/cvs_clock.sv']
    top = {'video_connected':'cvs_video_cpu_tb','s2636_connected':'cvs_s2636_cpu_tb','character_connected':'cvs_character_cpu_tb','cold_connected':'cvs_cold_cpu_tb','assembly_connected':'cvs_machine_tb','bootstrap_connected':'cvs_machine_tb','startup_connected':'cvs_startup_tb'}.get(args.mode,'cvs_main_tb')
    if args.mode=='audio_connected':
        top='cvs_audio_cpu_tb'
        sources=['rtl/machine/cvs_audio_cpu.sv','rtl/machine/cvs_audio_bus.sv',*sync_ram_sources,'rtl/machine/cvs_clock.sv']
    if args.mode=='speech_connected':
        top='cvs_speech_cpu_tb'
        sources=['rtl/machine/cvs_speech_cpu.sv','rtl/machine/cvs_speech_bus.sv',*sync_ram_sources,'rtl/machine/cvs_clock.sv']
    if args.mode=='tms5100_connected':
        top='cvs_tms5100_cpu_tb'
        sources=['rtl/machine/cvs_speech_cpu.sv','rtl/machine/cvs_speech_bus.sv',*sync_ram_sources,
                 'rtl/machine/cvs_tms5100_control.sv','rtl/machine/cvs_clock.sv']
    if args.mode=='speech_machine_connected':
        top='cvs_speech_machine_tb'
        sources=['rtl/machine/cvs_speech_machine.sv','rtl/machine/cvs_speech_cpu.sv','rtl/machine/cvs_speech_bus.sv',*sync_ram_sources,
                 'rtl/machine/cvs_clock.sv','rtl/machine/cvs_tms5100_engine.sv','rtl/machine/cvs_tms5100_rate.sv',
                 'rtl/machine/cvs_tms5100_control.sv','rtl/machine/cvs_tms5100_frames.sv','rtl/machine/cvs_tms5100_sequence.sv',
                 'rtl/machine/cvs_tms5100_lattice.sv','rtl/machine/cvs_tms5100_pcm.sv','rtl/vendor/tms5100/cvs_tms5100_tables.sv']
    if args.mode=='video_connected':
        sources += ['rtl/machine/cvs_video_timing.sv','rtl/machine/cvs_vblank_irq.sv']
    if args.mode=='s2636_connected':
        sources += ['rtl/machine/cvs_s2636_objects.sv','rtl/machine/cvs_s2636_bank.sv']
    if args.mode=='character_connected':
        sources += ['rtl/machine/cvs_character_video.sv']
    if args.mode in ('assembly_connected','bootstrap_connected','startup_connected','av_connected','full_connected'):
        sources += ['rtl/machine/cvs_machine.sv','rtl/machine/cvs_scan.sv','rtl/machine/cvs_video_timing.sv',
                    'rtl/machine/cvs_vblank_irq.sv','rtl/machine/cvs_video_join.sv','rtl/machine/cvs_mister_pixel_enable.sv',
                    'rtl/machine/cvs_s2636_bank.sv','rtl/machine/cvs_s2636_objects.sv','rtl/machine/cvs_character_video.sv']
    if args.mode=='av_connected':
        top='cvs_av_machine_tb'
        sources += ['rtl/machine/cvs_av_machine.sv','rtl/machine/cvs_audio_cpu.sv','rtl/machine/cvs_audio_bus.sv','rtl/machine/cvs_audio_samples.sv']
    if args.mode=='full_connected':
        top='cvs_full_machine_tb'
        sources += ['rtl/machine/cvs_full_machine.sv','rtl/machine/cvs_av_machine.sv',
                    'rtl/machine/cvs_audio_cpu.sv','rtl/machine/cvs_audio_bus.sv','rtl/machine/cvs_audio_samples.sv',
                    'rtl/machine/cvs_speech_machine.sv','rtl/machine/cvs_speech_cpu.sv','rtl/machine/cvs_speech_bus.sv',
                    'rtl/machine/cvs_tms5100_engine.sv','rtl/machine/cvs_tms5100_rate.sv','rtl/machine/cvs_tms5100_control.sv',
                    'rtl/machine/cvs_tms5100_frames.sv','rtl/machine/cvs_tms5100_sequence.sv',
                    'rtl/machine/cvs_tms5100_lattice.sv','rtl/machine/cvs_tms5100_pcm.sv','rtl/vendor/tms5100/cvs_tms5100_tables.sv']
    if args.mode in ('mister_shell_connected','mister_shell_behavior_connected'):
        top='emu'
        sources=['sys/arcade_video.v','sim/bdsm/mister_shell_stubs.sv','Arcade-Hunchback.sv',
                 *sorted(str(p) for p in Path('rtl/machine').glob('*.sv')),
                 'rtl/vendor/tms5100/cvs_tms5100_tables.sv']
        if args.mode=='mister_shell_behavior_connected':
            top='mister_shell_tb'
            sources.append('sim/cpu/mister_shell_tb.sv')
    if args.mode not in ('mister_shell_connected','mister_shell_behavior_connected'):
        sources += ['sim/cpu/'+top+'.sv']
    defines=['-DMISTER_FB=1'] if args.mode in ('mister_shell_connected','mister_shell_behavior_connected') else []
    compile_run=subprocess.run(['iverilog','-g2012','-Wall',*defines,'-s',top,'-o',str(work/'test.vvp'),
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
    cheat_array_note=re.compile(r"rtl/machine/cvs_cheat_engine\.sv:(57|58|59|60|61): warning: @\* is sensitive to all 16 words in array '(code_valid|code_address|code_compare_enable|code_compare|code_value)'\.")
    screen_init_note=re.compile(r"sys/arcade_video\.v:(268|300): warning: Static variable initialization requires explicit lifetime in this context\.")
    for line in (compile_run.stdout+compile_run.stderr).splitlines():
        if args.mode in ('s2636_connected','assembly_connected','bootstrap_connected','startup_connected','av_connected','full_connected','mister_shell_connected','mister_shell_behavior_connected') and array_note.fullmatch(line):
            reviewed_messages.append({'message':line,'review':'Full-array sensitivity is required for the declared combinational indexed register/engine read; Verilator -Wall finds no latch or sensitivity fault.'})
        elif args.mode in ('main_connected','video_connected','s2636_connected','character_connected','cold_connected','assembly_connected','bootstrap_connected','startup_connected','av_connected','full_connected','mister_shell_connected','mister_shell_behavior_connected') and cheat_array_note.fullmatch(line):
            reviewed_messages.append({'message':line,'review':'The cheat output intentionally checks all 16 loaded byte-code slots in parallel; each valid/address/compare/value array is included in the combinational sensitivity set.'})
        elif args.mode in ('mister_shell_connected','mister_shell_behavior_connected') and screen_init_note.fullmatch(line):
            reviewed_messages.append({'message':line,'review':'The pinned MiSTer framebuffer rotation module initializes static local raster counters inside clocked processes; this is supported by Quartus and does not change modeled rotation/control behavior.'})
        else:
            diagnostics += line+'\n'
    if args.mode=='mister_shell_connected':
        event={'status':'PASS','observed':'MiSTer emu shell structurally elaborates with the actual GHDL-synthesized S2650 hierarchy; HPS and PLL are interface stubs in this compile-only check.'}
        if reviewed_messages:event['reviewed_diagnostics']=reviewed_messages
        if diagnostics.strip():
            emit('WARNING',observed=diagnostics.strip(),diagnostics=[str(work/'synth.log'),str(work/'compile.log')])
        else:
            emit(**event)
        return 0
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
