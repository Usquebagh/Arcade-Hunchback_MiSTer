"""Independent restricted S2650 model through the first startup subroutine.

Game bytes are read at runtime. This models write order, not CPU cycle timing,
video output, interrupts or a complete instruction set. Unknown state and
unsupported instructions are preparation errors rather than assumed zeros.
"""
from pathlib import Path
import hashlib
import json


def model(image):
    if len(image) != 0xc820:
        raise ValueError('Startup image size')
    pc = 0
    registers = [None] * 4
    flag = False
    inhibited = False
    rs_known = False
    stack = []
    events = []
    called = False

    def byte():
        nonlocal pc
        value = image[pc]
        pc = (pc & 0x6000) | ((pc + 1) & 0x1fff)
        return value

    def register(index):
        if registers[index] is None:
            raise ValueError(f'Unknown R{index} at {pc:04x}')
        return registers[index]

    def relative():
        displacement = byte()
        if displacement & 0x80:
            raise ValueError('Indirect relative startup branch unsupported')
        return (pc & 0x6000) | ((pc + (displacement if displacement < 64 else displacement - 128)) & 0x1fff)

    for instruction in range(10000):
        origin = pc
        op = byte()
        if op in (0x1f, 0x3f):
            high, low = byte(), byte()
            if high & 0x80:
                raise ValueError('Indirect absolute startup branch unsupported')
            if op == 0x3f:
                if not inhibited:
                    raise ValueError('Startup boundary requires inhibited interrupts')
                stack.append(pc)
                called = True
            pc = ((high << 8) | low) & 0x7fff
        elif op == 0x17:
            if not stack:
                raise ValueError('Startup return without a modeled call')
            pc = stack.pop()
            if not stack:
                return events, dict(instructions=instruction + 1, resume=pc,
                                    interrupts_inhibited=inhibited, first_call_completed=called)
        elif op in (0x74, 0x76):
            mask = byte()
            if mask & 7:
                raise ValueError('Stack pointer status masks unsupported')
            setting = op == 0x76
            if mask & 0x40:
                flag = setting
            if mask & 0x20:
                inhibited = setting
        elif op in (0x75, 0x77):
            mask = byte()
            if mask & 0x10:
                if op == 0x77:
                    raise ValueError('Alternate register bank unsupported')
                rs_known = True
        elif 0x04 <= op <= 0x07:
            if op & 3 and not rs_known:
                raise ValueError('Unknown register bank')
            registers[op & 3] = byte()
        elif op == 0x20:
            registers[0] = 0
        elif op in (0xc1, 0xc2, 0xc3):
            if not rs_known:
                raise ValueError('Unknown register bank')
            registers[op & 3] = register(0)
        elif 0xcc <= op <= 0xcf:
            high, low = byte(), byte()
            if high & 0x80:
                raise ValueError('Indirect startup store unsupported')
            mode = (high >> 5) & 3
            source = op & 3
            addr = (high & 31) * 256 + low
            if mode:
                index = register(source)
                if mode == 1:
                    index = (index + 1) % 256
                elif mode == 2:
                    index = (index - 1) % 256
                registers[source] = index
                addr = (addr + index) & 0x1fff
                source = 0
            addr |= pc & 0x6000
            events.append((1, 0, 0, addr, int(flag), register(source)))
        elif 0x58 <= op <= 0x5b or 0xf8 <= op <= 0xfb:
            target = relative()
            index = op & 3
            value = register(index)
            if op >= 0xf8:
                value = (value - 1) % 256
                registers[index] = value
            if value:
                pc = target
        elif 0xd4 <= op <= 0xd7:
            addr = byte()
            events.append((0, 1, 1, addr, int(flag), register(op & 3)))
        else:
            raise ValueError(f'Unsupported startup opcode at {origin:04x}')
    raise ValueError('First startup call did not complete within model bound')


def pack(event):
    memory, extended, data, address, flag, value = event
    return (memory << 26) | (extended << 25) | (data << 24) | (address << 9) | (flag << 8) | value


def expectations(image_path, output):
    image = Path(image_path).read_bytes()
    events, metadata = model(image)
    if len(events) > 8192 or not events:
        raise ValueError('Startup fixture event capacity')
    output = Path(output)
    output.write_text(''.join(f'{pack(event):07x}\n' for event in events))
    metadata.update(provenance='Independent restricted S2650 instruction semantics, first initialization call only',
                    image_sha256=hashlib.sha256(image).hexdigest(),
                    expectations_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
                    writes=len(events), memory_writes=sum(e[0] for e in events),
                    io_writes=sum(not e[0] for e in events))
    output.with_suffix('.log').write_text(json.dumps(metadata, indent=2) + '\n')
    return metadata
