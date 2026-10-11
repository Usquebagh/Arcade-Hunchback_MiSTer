"""Independent sanity cases for the restricted runtime-ROM oracle."""
from pathlib import Path
import json
import tempfile
from bootstrap_model import expectations

def image(mode,order):
    data=bytearray([0xff])*0xc820
    program=[0x76,0x60,0x77,2,0x75,0x18,0x20,0xc1]
    for n,block in enumerate(order):
        program += [0xcd,(mode*32 if n==0 else 0x60)+0x1c+block,0]
    program += [0x59,0x72]
    data[:len(program)]=bytes(program)
    return data

try:
    with tempfile.TemporaryDirectory(prefix='bootstrap-oracle-') as temp:
        path=Path(temp)/'synthetic.bin';out=Path(temp)/'synthetic.expect'
        for mode,order,indices in [(2,[0,1,2,3],list(range(255,-1,-1))),
                                  (1,[0,3,2,1],list(range(1,256))+[0])]:
            path.write_bytes(image(mode,order));expectations(path,out)
            got=[int(line,16) for line in out.read_text().splitlines()]
            want=[((0x1c00+block*256+i)<<9)|256 for i in indices for block in order]
            if got!=want:
                print('BDSM '+json.dumps(dict(status='FAIL',label='bootstrap_oracle_order',cycle=0,expected=want[0],observed=got[0])));raise SystemExit(1)
        for invalid in (bytearray([0x40])+image(2,[0,1,2,3])[1:],image(2,[0,1,2,2])):
            path.write_bytes(invalid)
            try:expectations(path,out)
            except ValueError:continue
            print('BDSM '+json.dumps(dict(status='FAIL',label='bootstrap_oracle_rejection',cycle=0,expected=1,observed=0)));raise SystemExit(1)
    print('BDSM '+json.dumps(dict(status='PASS',observed='Independent increment/decrement and reordered 1024-write streams; unsupported instruction and alias closure rejected')))
except (OSError,ValueError) as exc:
    print('BDSM '+json.dumps(dict(status='ERROR',reason=str(exc))));raise SystemExit(2)
