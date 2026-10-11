"""Manually enumerated contracts for the bounded startup reference."""
import json
from pathlib import Path
import sys

# Execute the frozen core's model, including disposable source mutations,
# rather than an unchanged helper copied beside the adapter runner.
sys.path.insert(0, str(Path.cwd() / 'sim/bdsm'))
from startup_model import model


def image(prefix, routine):
    data = bytearray([0xff]) * 0xc820
    data[:len(prefix)] = bytes(prefix)
    data[0x40:0x40+len(routine)] = bytes(routine)
    return data


prefix = [0x76,0x60,0x75,0x10,0x04,0xaa,0x05,2,0x06,2,0x3f,0,0x40]
routine = [0xcd,0x54,0x10,0x59,0x7b,0x74,0x40,0x04,0xbb,0x05,0,
           0xcd,0x38,0x10,0xfa,0x7b,0x07,0xff,0xcf,0x17,0x10,0xd4,0,0x17]
want = [(1,0,0,0x1411,1,0xaa),(1,0,0,0x1410,1,0xaa),
        (1,0,0,0x1811,0,0xbb),(1,0,0,0x1812,0,0xbb),
        (1,0,0,0x1710,0,0xff),(0,1,1,0,0,0xbb)]
try:
    events, metadata = model(image(prefix, routine))
    if events != want or metadata['resume'] != len(prefix) or not metadata['interrupts_inhibited']:
        print('BDSM '+json.dumps(dict(status='FAIL',label='startup_oracle_order',cycle=0,
                                     expected=str(want),observed=str(events))))
        raise SystemExit(1)
    for bad_prefix, bad_routine in [(prefix,[0x40]),
                                    (prefix,[0xcd,0xd4,0x10]),
                                    (prefix,[0x77,0x10,0x17]),
                                    (prefix,[0xcf,0x1c,0,0x17]),
                                    (prefix,[0x76,1,0x17]),
                                    ([0x17],routine),
                                    (prefix,[0x1f,0,0x40]),
                                    (prefix,[0xcc,0x1c,0,0x59,0xfb])]:
        try:
            model(image(bad_prefix,bad_routine))
        except ValueError:
            continue
        print('BDSM '+json.dumps(dict(status='FAIL',label='startup_oracle_rejection',cycle=0,expected=1,observed=0)))
        raise SystemExit(1)
    print('BDSM '+json.dumps(dict(status='PASS',observed='Manually enumerated indexed decrement/increment, BDRR, FLAG, unindexed register store, extended I/O and return; unsupported state/indirection/bounds rejected')))
except (OSError,ValueError) as exc:
    print('BDSM '+json.dumps(dict(status='ERROR',reason=str(exc))))
    raise SystemExit(2)
