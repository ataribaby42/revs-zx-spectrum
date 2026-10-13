"""Labels and instructions of the BBC extra track files (from the BBC
assembler listing, its part up to the track files in
assets/bbc/tracks-listing.txt), for the port of the track code: the C64
track files have the same layout at $5300.

Usage: python tools/bbc_tracks.py [track]   summary of the code routines
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LISTING = ROOT / 'assets/bbc/tracks-listing.txt'
FILES = {'Brands Hatch': 'BrandsHatch', 'Donington Park': 'DoningtonPark', 'Nurburgring': 'Nurburgring',
         'Oulton Park': 'OultonPark', 'Silverstone': 'Silverstone', 'Snetterton': 'Snetterton'}


def parse():
    """{file name: [(label or None, address, bytes, text)]} per track file."""
    tracks = {}
    cur = []
    for line in LISTING.read_text(encoding='latin-1').splitlines():
        m = re.match(r"Saving file '3-assembled-output/(\w+)\.bin'", line)
        if m:
            tracks[m.group(1)] = cur
            cur = []
            continue
        m = re.match(r'^\.(\w+)', line)
        if m:
            cur.append((m.group(1), None, b'', ''))
            continue
        m = re.match(r'^\s+([0-9A-F]{4})\s+((?:[0-9A-F]{2} )*[0-9A-F]{2})\s*(.*)$', line)
        if m:
            data = bytes(int(x, 16) for x in m.group(2).split())
            cur.append((None, int(m.group(1), 16), data, m.group(3).strip()))
    return tracks


def labels(entries):
    out = {}
    pending = []
    for lab, addr, data, text in entries:
        if lab:
            pending.append(lab)
        elif addr is not None:
            for p in pending:
                out[p] = addr
            pending = []
    return out


def routines(entries):
    """[(label, start, end, instruction count)] for labels followed by code."""
    out = []
    cur = None
    for lab, addr, data, text in entries:
        if lab:
            if cur:
                out.append(cur)
            cur = [lab, None, None, 0]
        elif cur is not None and addr is not None:
            if cur[1] is None:
                cur[1] = addr
            cur[2] = addr + len(data)
            if re.match(r'[A-Z]{3}\b', text):
                cur[3] += 1
    if cur:
        out.append(cur)
    return out


if __name__ == '__main__':
    tracks = parse()
    names = [FILES[sys.argv[1]]] if len(sys.argv) > 1 else [f for f in FILES.values()]
    for n in names:
        rs = [r for r in routines(tracks[n]) if r[3] > 0]
        total = sum(r[2] - r[1] for r in rs)
        print(f'{n}: {len(rs)} code routines, {total} bytes')
        for lab, s, e, k in rs:
            print(f'  {s:04X}-{e - 1:04X} {e - s:4d} {lab}')
