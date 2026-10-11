#!/usr/bin/env python3
"""Render retained synthetic P3 pixel diagnostics, never ROM/register captures."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

parser=argparse.ArgumentParser()
parser.add_argument('observed',type=Path)
parser.add_argument('--expected',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--scale',type=int,default=2,choices=range(1,9))
parser.add_argument('--kind',choices=['sprite','character'],default='sprite')
args=parser.parse_args()
observed=Image.open(args.observed).convert('RGB')
expected=Image.open(args.expected).convert('RGB')
dimensions=(227,256) if args.kind=='sprite' else (256,256)
if observed.size!=dimensions or expected.size!=observed.size or observed.tobytes()!=expected.tobytes():
    raise SystemExit('Synthetic RTL/reference image mismatch')
args.output.parent.mkdir(parents=True,exist_ok=True)
observed.resize(tuple(n*args.scale for n in dimensions),Image.Resampling.NEAREST).save(args.output)
provenance='Synthetic S2636 geometric fixture, no game ROM; colour-bit RGB diagnostic mapping only' if args.kind=='sprite' else 'Synthetic normalized character/bullet fixture, no game ROM; digital palette RGB, not calibrated analog output'
metadata={'provenance':provenance,
          'source_dimensions':list(dimensions),'scale':args.scale,'pillow_version':Image.__version__,
          'inputs':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [args.observed,args.expected]},
          'output_sha256':hashlib.sha256(args.output.read_bytes()).hexdigest()}
args.output.with_suffix('.json').write_text(json.dumps(metadata,indent=2)+'\n')
print('Synthetic RTL/reference pixels identical; preview saved to '+str(args.output))
