#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Private stereo raw-DAC diagnostic from authenticated actual HDL samples.

Left is raw byte DAC, right raw four-bit latch. Optional preview removes each
channel's mean and applies gain 1/2. No physical mixing/filter/discrete/speech.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import wave

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('observation',type=Path,help='Completed audio-enabled observation.json')
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--preview',action='store_true',help='Remove channel means and apply gain 1/2 for playback; not calibrated audio')
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
report_path=args.observation.resolve();output=args.output.resolve()
if not report_path.is_relative_to(root/'build') or not output.is_relative_to(root/'build'):
    parser.error('Observation and WAV output must remain under ignored project build/')
if output.suffix.lower()!='.wav':parser.error('Output must have .wav extension')
if output.exists() or output.with_suffix('.json').exists():
    parser.error('Choose a new output path; existing diagnostic files are retained')
data=json.loads(report_path.read_text())
if data.get('status')!='OBSERVED_ONLY' or not data.get('audio'):
    raise SystemExit('Requires a completed audio-enabled observation')
source=report_path.parent/'audio-samples.log';identity=hashlib.sha256(source.read_bytes()).hexdigest()
if not any(p['name']==source.name and p['sha256']==identity for p in data.get('event_logs',[])):
    raise SystemExit('Actual sample log hash is not authenticated by this observation')
origin=data['observations']['audio_sample_origin'];master=data['audio_fixture']['master_hz'];rate=48000
event_source=report_path.parent/'audio-events.log'
event_identity=hashlib.sha256(event_source.read_bytes()).hexdigest()
if not any(p['name']==event_source.name and p['sha256']==event_identity for p in data.get('event_logs',[])):
    raise SystemExit('DAC event log hash is not authenticated by this observation')
events=[];last_cycle=-1
for line in event_source.read_text().splitlines():
    fields=line.split();cycle=int(fields[0])
    if cycle<last_cycle:raise SystemExit('Event log is not ordered')
    last_cycle=cycle
    if fields[1] in ['DAC8','DAC4']:
        if len(fields)!=3:raise SystemExit('Malformed DAC event')
        value=int(fields[2]);maximum=255 if fields[1]=='DAC8' else 15
        if not 0<=value<=maximum:raise SystemExit('Invalid raw DAC event')
        events.append((cycle,fields[1],value))
cursor=0;dac8=dac4=0
channels=[[],[]]
for index,line in enumerate(source.read_text().splitlines(),1):
    fields=line.split()
    if len(fields)!=3:raise SystemExit('Malformed sample record')
    cycle,left,right=map(int,fields)
    want=origin+(index*master+rate-1)//rate
    if cycle!=want or not (-32768<=left<=32767 and -32768<=right<=32767):
        raise SystemExit('Sample cadence or signed value violates the declared raw contract')
    # DAC writes are logged after their latch edge. Sampling on that same edge
    # consumes the previous values, so only strictly earlier events apply.
    while cursor<len(events) and events[cursor][0]<cycle:
        _,kind,value=events[cursor]
        if kind=='DAC8':dac8=value
        else:dac4=value
        cursor+=1
    if left!=dac8*256-32768 or right!=dac4*4096-32768:
        raise SystemExit('Actual PCM samples do not match preceding raw DAC events')
    channels[0].append(left);channels[1].append(right)
count=(data['observations']['cycles']-origin)*rate//master
if not channels[0] or len(channels[0])!=count:raise SystemExit('Missing or truncated actual sample stream')
means=[sum(c)/count for c in channels]
gain=0.5 if args.preview else 1.0
shifts=means if args.preview else [0,0]
frames=bytearray();clipped=0
for left,right in zip(*channels):
    values=[]
    for channel,value in enumerate((left,right)):
        sample=round((value-shifts[channel])*gain)
        if sample<-32768 or sample>32767:clipped+=1
        values.append(max(-32768,min(32767,sample)))
    frames.extend(struct.pack('<hh',*values))
output.parent.mkdir(parents=True,exist_ok=True)
with wave.open(str(output),'wb') as wav:
    wav.setnchannels(2);wav.setsampwidth(2);wav.setframerate(rate);wav.writeframes(frames)
metadata=dict(status='OBSERVED_ONLY',candidate=False,hardware_validation='pending',
    provenance='Actual two-state HDL PCM samples; declared raw scaling, no independent audio-ROM/channel waveform oracle',
    source_sha256=data['source_sha256'],observation_sha256=hashlib.sha256(report_path.read_bytes()).hexdigest(),
    renderer_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    dac_event_log_sha256=event_identity,
    sample_log_sha256=identity,output_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
    seed=data['seed'],rate=rate,frames=count,channels=['raw byte DAC','raw four-bit DAC latch'],
    mean_subtracted=shifts,gain=gain,clipped_samples=clipped,
    raw_ranges=[dict(min=min(c),max=max(c),mean=mean) for c,mean in zip(channels,means)],
    limitations=data['limitations']+['Stereo separation is a diagnostic; physical mixing/bit weights/analog/discrete/speech absent'])
output.with_suffix('.json').write_text(json.dumps(metadata,indent=2)+'\n')
print('Private '+('DC-removed preview' if args.preview else 'raw DAC WAV')+' saved to '+str(output))
