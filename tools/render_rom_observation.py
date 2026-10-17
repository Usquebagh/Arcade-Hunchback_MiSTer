#!/usr/bin/env python3
# SPDX-License-Identifier: BSD-3-Clause
"""Preview a hash-authenticated private diagnostic capture; no reference PASS."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('capture',type=Path)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--scale',type=int,default=2,choices=range(1,9))
args=parser.parse_args()
capture=args.capture.resolve();output=args.output.resolve()
root=Path(__file__).resolve().parents[1]
if not capture.is_relative_to(root/'build') or not output.is_relative_to(root/'build'):
    parser.error('Captures/previews must stay in this project’s ignored build directory')
report=json.loads((capture.parent/'observation.json').read_text())
if report.get('status')!='OBSERVED_ONLY':
    raise SystemExit('Only a completed diagnostic may be previewed')
identity=hashlib.sha256(capture.read_bytes()).hexdigest()
if not any(item['name']==capture.name and item['sha256']==identity for item in report['captures']):
    raise SystemExit('Capture hash is absent from its observation report')
source=Image.open(capture).convert('RGB')
if source.size!=(244,248):raise SystemExit('Unexpected native CVS source dimensions')
# Pinned MAME CVS Hunchback declares ROT90. Rotation preserves the native
# 244x248 source; integer --scale is only for local preview readability.
preview=source.transpose(Image.Transpose.ROTATE_270)
preview=preview.resize(tuple(n*args.scale for n in preview.size),Image.Resampling.NEAREST)
output.parent.mkdir(parents=True,exist_ok=True);preview.save(output)
metadata=dict(status='OBSERVED_ONLY',provenance='Actual machine diagnostic pixels; no independent game-frame oracle',
              source_sha256=report['source_sha256'],capture_sha256=identity,seed=report['seed'],
              pillow_version=Image.__version__,
              orientation='Clockwise 90 degrees per pinned MAME ROT90; preview only',scale=args.scale,
              output_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),limitations=report['limitations'])
output.with_suffix('.json').write_text(json.dumps(metadata,indent=2)+'\n')
print('Private observed-only preview saved to '+str(output))
