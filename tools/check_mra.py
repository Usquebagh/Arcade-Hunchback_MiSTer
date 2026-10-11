#!/usr/bin/env python3
"""Evaluate the draft MRA against an independent program address equation.

The private prepared image is authenticated by prepare_hunchback.py. Synthetic
patterns validate placement and padding without redistributing ROM bytes.
"""
import argparse
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
from prepare_hunchback import assemble


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--image', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / 'tools/rom_manifest.json').read_text())
    xml = ET.parse(root / 'releases/Hunchback (CVS).mra').getroot()
    entries = {r['name']: r for r in manifest['roms']}
    synthetic = {name: bytes(((i * 7 + (i >> 10) * 29 + n * 43) & 255) for i in range(e['bytes']))
                 for n, (name, e) in enumerate(entries.items())}
    image = bytearray()
    rom = xml.find("rom[@index='0']")
    if rom is None:
        raise ValueError('No ioctl index-0 ROM')
    for part in rom:
        if part.tag != 'part':
            raise ValueError('Unsupported MRA node')
        name = part.get('name')
        if name:
            if name not in entries or part.get('crc') != entries[name]['crc']:
                raise ValueError('ROM name/CRC mismatch')
            blob = synthetic[name]
            start = int(part.get('offset', '0'), 0)
            size = int(part.get('length', str(len(blob))), 0)
            if start < 0 or size <= 0 or start + size > len(blob):
                raise ValueError('Invalid MRA source slice')
            image.extend(blob[start:start + size])
        else:
            image.extend(bytes.fromhex(part.text or '') * int(part.get('repeat', '1'), 0))
    if len(image) != manifest['image_bytes']:
        raise ValueError('Wrong assembled MRA length')
    prepared_synthetic = assemble(synthetic, manifest)
    # Separate oracle: each CPU address selects an EPROM and a quarter of it.
    for address in range(0x8000):
        offset = address & 0x1fff
        want = 255 if offset >= 0x1400 else synthetic[f'hb-gp{offset // 0x400 + 1}.bin'][(address >> 13) * 0x400 + offset % 0x400]
        if image[address] != want:
            print('BDSM ' + json.dumps(dict(status='FAIL', label='mra_program_byte', cycle=address, expected=want, observed=image[address])))
            return 1
        if prepared_synthetic[address] != want:
            print('BDSM ' + json.dumps(dict(status='FAIL', label='prepare_program_byte', cycle=address, expected=want, observed=prepared_synthetic[address])))
            return 1
    for region in manifest['regions']:
        expected = bytearray([region['fill']]) * region['bytes']
        for chunk in region['chunks']:
            blob = synthetic[chunk['name']]
            expected[chunk['offset']:chunk['offset'] + len(blob)] = blob
        if image[region['offset']:region['offset'] + region['bytes']] != expected:
            raise ValueError('Auxiliary region placement mismatch: ' + region['name'])
        if prepared_synthetic[region['offset']:region['offset'] + region['bytes']] != expected:
            raise ValueError('Synthetic prepared auxiliary region mismatch: ' + region['name'])
    if args.image:
        prepared = args.image.read_bytes()
        if len(prepared) != len(image):
            raise ValueError('Prepared private image length mismatch')
        for page in range(4):
            if prepared[page * 8192 + 5120:(page + 1) * 8192] != bytes([255]) * 3072:
                raise ValueError('Private image program gap mismatch')
    observation = 'Synthetic MRA and preparation match independent address/padding oracle; this is not a boot test'
    if args.image:
        observation += '; 13 parent ROMs authenticated by fixture preparation'
    print('BDSM ' + json.dumps(dict(status='PASS', observed=observation)))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, OSError, KeyError, ET.ParseError) as exc:
        print('BDSM ' + json.dumps(dict(status='ERROR', reason=str(exc))))
        sys.exit(2)
