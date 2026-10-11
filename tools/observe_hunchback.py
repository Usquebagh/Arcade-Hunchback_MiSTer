#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Private long-ROM diagnostic; never an RBF gate or a game accuracy PASS.

Use the pinned framework's source inventory/snapshot functions without modifying
its runner. Actual VHDL CPU synthesis and actual SV machine run in Verilator.
All compiler findings remain visible in retained logs. Two-state randomized
power-up is diagnostic and does not replace native unknown-state checks.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive',type=Path)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--cycles',type=int,default=300_000_000)
    parser.add_argument('--seed',type=int,default=1)
    parser.add_argument('--controls',action='store_true',help='Synthetic coin/start/right/jump input windows; see docs/rom-observation.md')
    parser.add_argument('--audio',action='store_true',help='Actual audio CPU/bus and raw 48k samples; nominal external 380 Hz SENSE, no calibrated mixing/speech/analog reference')
    args=parser.parse_args()
    if sys.platform!='linux':parser.error('Run in WSL/Linux with GHDL and Verilator')
    if not 2_000_000<=args.cycles<=1_000_000_000 or not 1<=args.seed<=2147483647:
        parser.error('Cycles must be 2 million..1 billion; seed must be 1..2147483647')
    root=Path(__file__).resolve().parents[1]
    archive=args.archive.resolve()
    output=(args.output or root/'build'/datetime.now(timezone.utc).strftime('observe-%Y%m%dT%H%M%SZ')).resolve()
    if not output.is_relative_to(root/'build'):
        parser.error('Diagnostic output must stay under this project’s ignored build directory')
    output.mkdir(parents=True,exist_ok=False)
    sys.path.insert(0,str(root/'MiSTer-BDSM'))
    from runner.engine import inventory,input_hash,load_adapter,snapshot,tools_metadata,git_metadata
    adapter=load_adapter(root/'sim/bdsm/adapter.json')
    files=inventory(root,adapter)
    metadata=dict(status='INCOMPLETE_DIAGNOSTIC',candidate=False,hardware_validation='pending',
        source_sha256=input_hash(files),source_files=files,core=git_metadata(root),seed=args.seed,
        cycles_requested=args.cycles,controls=args.controls,audio=args.audio,two_state=True,
        tools=tools_metadata(['ghdl','verilator','make','g++']),
        provenance='Independent initialization write model; subsequent ROM execution and frames are observations only',
        limitations=['No independent post-initialization CPU/game/frame oracle','Randomized two-state initialization is not X/Z verification',
            'Provisional 227x256 scan window/origins','Raw MAME compatibility switch/input fixtures; no physical wiring audit',
            'Full PVI/PAL/audio/MiSTer/PLL/Quartus gates remain open','Every compiler finding is retained; no warning suppression'])
    if args.audio:
        metadata['audio_fixture']=dict(master_hz=57272724,sense_hz=380,
            provenance='Nominal synchronous enables and external SENSE fixture; not physical oscillator/CDC proof')
        metadata['limitations'].append('Digital audio-ROM events/raw samples observed only; no independent firmware/channel/waveform oracle or analog/calibrated mixing/speech')
    def save():
        (output/'observation.json').write_text(json.dumps(metadata,indent=2)+'\n')
    save()
    with tempfile.TemporaryDirectory(prefix='hunchback-observe-') as temporary:
        frozen=Path(temporary)/'core'
        snapshot(root,frozen,files)
        work=Path(temporary)/'work';work.mkdir()
        archive_before=hashlib.sha256(archive.read_bytes()).hexdigest()
        with (output/'prepare.log').open('w') as log:
            ran=subprocess.run([sys.executable,str(frozen/'tools/prepare_hunchback.py'),str(archive),
                                '--output',str(output/'image.bin')],stdout=log,stderr=subprocess.STDOUT)
        if ran.returncode:raise ValueError('ROM authentication/preparation failed; see prepare.log')
        if hashlib.sha256(archive.read_bytes()).hexdigest()!=archive_before:
            raise ValueError('ROM archive changed during preparation')
        sys.path.insert(0,str(frozen/'sim/bdsm'))
        from startup_model import expectations
        reference=expectations(output/'image.bin',output/'startup.expect')
        metadata.update(archive_sha256=archive_before,image_sha256=reference['image_sha256'],startup_reference=reference)
        cpu_sources=[str(frozen/'rtl/vendor/arcadia'/name) for name in ['base_pack.vhd','sgs2650_pack.vhd','sgs2650.vhd']]
        ran=subprocess.run(['ghdl','--synth','--std=08','--out=verilog',*cpu_sources,'-e','sgs2650'],capture_output=True,text=True)
        (output/'synth.log').write_text(ran.stderr)
        if ran.returncode or not ran.stdout.strip():raise ValueError('Actual CPU synthesis failed')
        # Lexical keyword escape only; no substitutions to CPU logic or reset.
        cpu=work/'sgs2650.v';cpu.write_text(re.sub(r'\bint\b',lambda _: '\\int ',ran.stdout))
        metadata['synthesized_cpu_sha256']=hashlib.sha256(cpu.read_bytes()).hexdigest()
        names=['cvs_machine','cvs_main','cvs_main_bus','cvs_main_io','cvs_main_memory','cvs_banked','cvs_memory','cvs_clock',
               'cvs_scan','cvs_video_timing','cvs_vblank_irq','cvs_video_join','cvs_s2636_bank','cvs_s2636_objects','cvs_character_video']
        top='cvs_av_machine' if args.audio else 'cvs_machine'
        if args.audio:names += ['cvs_av_machine','cvs_audio_cpu','cvs_audio_bus','cvs_audio_samples']
        command=['verilator','--cc','--exe','--build','-j','4','--top-module',top,'-Wall','-Wno-fatal',
            '--x-initial','unique','--x-assign','unique','--Mdir',str(work/'obj'),'-CFLAGS','-O3 -std=c++17'+(' -DAUDIO_OBSERVE' if args.audio else ''),str(cpu),
            *[str(frozen/'rtl/machine'/f'{name}.sv') for name in names],str(frozen/'sim/bdsm/observe_machine.cpp')]
        metadata['compile_command']=command
        with (output/'compile.log').open('w') as log:
            ran=subprocess.run(command,cwd=frozen,stdout=log,stderr=subprocess.STDOUT)
        metadata['unreviewed_compiler_findings']=re.findall(r'%Warning-[^\n]+',(output/'compile.log').read_text())
        save()
        if ran.returncode:raise ValueError('Compiled-machine diagnostic build failed; see compile.log')
        print(f'Running private diagnostic; {len(metadata["unreviewed_compiler_findings"])} retained compiler findings.',flush=True)
        command=[str(work/'obj'/('V'+top)),str(args.cycles),str(args.seed),str(reference['resume']),str(int(args.controls))]
        with (output/'run.log').open('w') as log:
            process=subprocess.Popen(command,cwd=output,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
            for line in process.stdout:
                log.write(line);log.flush();print(line,end='',flush=True)
            returncode=process.wait()
        lines=(output/'run.log').read_text().splitlines()
        events=[json.loads(line[9:]) for line in lines if line.startswith('OBSERVED ')]
        failures=[json.loads(line[5:]) for line in lines if line.startswith('BDSM ')]
        if returncode==1 and failures and failures[-1].get('status')=='FAIL' and all(
                key in failures[-1] for key in ['label','cycle','expected','observed']):
            metadata.update(status='ASSERTION_FAILED_DIAGNOSTIC',assertion=failures[-1])
            save()
            print('Diagnostic assertion retained in '+str(output)+'; no candidate qualification.',flush=True)
            return 1
        if returncode or not events:raise ValueError('Diagnostic failed or omitted its bounded observation; see run.log')
        metadata['observations']=events[-1]
        metadata['event_logs']=[dict(name=p.name,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
                                for p in sorted(output.glob('*bus.log'))+sorted(output.glob('*events.log'))+sorted(output.glob('*samples.log'))]
        metadata['captures']=[dict(name=p.name,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
                                  provenance='Actual machine pixels; observed only, no independent game-frame oracle')
                              for p in sorted(output.glob('frame-*.ppm'))]
    if inventory(root,adapter)!=files:raise ValueError('Maintained source changed during the diagnostic run')
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=archive_before:raise ValueError('ROM archive changed during execution')
    metadata['status']='OBSERVED_ONLY';save()
    print('Private observation retained in '+str(output)+'; no game accuracy or candidate PASS.',flush=True)


if __name__=='__main__':
    try:raise SystemExit(main() or 0)
    except (OSError,ValueError,subprocess.SubprocessError) as exc:
        print('ERROR: '+str(exc),file=sys.stderr)
        raise SystemExit(2)
