#!/usr/bin/env python3
"""Authenticate private parent ROMs; assemble documented ioctl index-0 image."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import zlib


def validated(archive, manifest):
    blobs = {}
    with zipfile.ZipFile(archive) as roms:
        for entry in manifest['roms']:
            name = entry['name']
            if sum(info.filename == name for info in roms.infolist()) != 1:
                raise ValueError('Missing or ambiguous parent ROM: ' + name)
            blob = roms.read(name)
            identity = (len(blob), f'{zlib.crc32(blob):08x}', hashlib.sha1(blob).hexdigest())
            if identity != (entry['bytes'], entry['crc'], entry['sha1']):
                raise ValueError('ROM identity mismatch: ' + name)
            blobs[name] = blob
    return blobs


def assemble(blobs, manifest):
    image = bytearray([255]) * manifest['image_bytes']
    # Main EPROMs: 1 KiB from each chip in each of four 8 KiB CPU pages.
    for chip in range(5):
        blob = blobs[f'hb-gp{chip + 1}.bin']
        for page in range(4):
            address = page * 0x2000 + chip * 0x400
            image[address:address + 0x400] = blob[page * 0x400:(page + 1) * 0x400]
    for region in manifest['regions']:
        base = region['offset']
        image[base:base + region['bytes']] = bytes([region['fill']]) * region['bytes']
        for chunk in region['chunks']:
            blob = blobs[chunk['name']]
            address = base + chunk['offset']
            image[address:address + len(blob)] = blob
    return bytes(image)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((Path(__file__).with_name('rom_manifest.json')).read_text())
    image = assemble(validated(args.archive, manifest), manifest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)
    print(f'Validated {len(manifest["roms"])} parent ROMs; assembled {len(image)} bytes')


if __name__ == '__main__':
    main()
