"""Restricted independent instruction semantics for unchanged ROM's RAM clear.

This is not a full CPU emulator or an observed-output regression. No game bytes
are embedded. Unsupported instructions/unknown registers are preparation errors.
"""
from pathlib import Path
import hashlib
import json

def expectations(image_path, output):
    image=Path(image_path).read_bytes()
    if len(image)!=0xc820:raise ValueError('Bootstrap image size')
    pc=0;registers=[None]*4;flag=False;psl=None;psu=0;writes=[]
    def byte():
        nonlocal pc
        value=image[pc];pc=(pc&0x6000)|((pc+1)&0x1fff);return value
    for instruction in range(5000):
        op=byte()
        if op==0x1f:
            high=byte();low=byte()
            if high&0x80:raise ValueError('Indirect bootstrap branch unsupported')
            pc=((high<<8)|low)&0x7fff
        elif op in (0x75,0x76,0x77):
            mask=byte()
            if op==0x76:psu|=mask;flag=bool(psu&0x40)
            elif op==0x75:
                if psl is None and mask!=0xff:raise ValueError('Unknown PSL mask')
                psl=(psl or 0)&~mask
            else:
                # Bootstrap explicitly sets compare mode then clears RS/WC.
                # Only those fields are relevant to this restricted model.
                psl=(psl or 0)|mask
        elif op==0x20:registers[0]=0
        elif op in (0xc1,0xc2,0xc3):registers[op&3]=registers[0]
        elif op==0xcd:
            high=byte();low=byte();index=registers[1]
            if high&0x80 or index is None or registers[0] is None:raise ValueError('Unknown indexed bootstrap store')
            mode=(high>>5)&3
            if mode==2:index=(index-1)%256
            elif mode==1:index=(index+1)%256
            elif mode!=3:raise ValueError('Unindexed bootstrap store unsupported')
            registers[1]=index
            addr=(pc&0x6000)|((((high&31)*256+low)+index)&0x1fff)
            writes.append((addr,int(flag),registers[0]))
            if len(writes)==1024:break
        elif op==0x59:
            displacement=byte()
            if displacement&0x80 or registers[1] is None:raise ValueError('Unsupported relative bootstrap branch')
            if registers[1]:pc=(pc&0x6000)|((pc+(displacement if displacement<64 else displacement-128))&0x1fff)
        else:raise ValueError(f'Unsupported bootstrap opcode at {pc-1:04x}')
    if len(writes)!=1024 or {a for a,f,d in writes}!=set(range(0x1c00,0x2000)) or any(f!=1 or d!=0 for a,f,d in writes):
        raise ValueError('Bootstrap model did not produce complete FLAG-high RAM clear')
    output=Path(output)
    output.write_text(''.join(f'{(a<<9)|(f<<8)|d:06x}\n' for a,f,d in writes))
    metadata=dict(provenance='Restricted independent bootstrap instruction model, early RAM clear only',
        image_sha256=hashlib.sha256(image).hexdigest(),expectations_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
        instructions=instruction+1,writes=1024,unique_system_words=1024,flag=1,modeled_irq_inhibit=bool(psu&0x20))
    output.with_suffix('.log').write_text(json.dumps(metadata,indent=2)+'\n')
    return metadata
