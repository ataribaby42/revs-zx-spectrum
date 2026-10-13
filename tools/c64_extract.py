"""Extract the parts of the C64 Revs+ tape that the port uses into
assets/c64 (done once; the files are kept, tools/c64_image.py reads them).

The tape's turbo-loaded frames are grouped (keyed by end address and bytes
5/6); a frame belongs to a group only when its load address equals
group_base + 256 * (page - first_page). Ghost frames (bit-shifted decodes of
real frames) fail this test or form tiny groups and are discarded. Of the
groups, the main game ($0B00-$52FF, $6400-$92FF, $A000-$CBFF) and the track
selector block ($1400-$4BFF: the six track files from $1800, the Revs+
installer at $4800) are written as plain binaries (c64_image.PARTS).

Usage: python tools/c64_extract.py
"""
import collections
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from c64_image import ASSETS, PARTS  # noqa: E402
from c64_tape import TAPE, frames, pulses  # noqa: E402


def groups():
    p = pulses(TAPE.read_bytes())
    g = collections.defaultdict(list)
    for pos, d in frames(p):
        key = (d[3] | d[4] << 8, d[5], d[6])
        g[key].append((d[0], d[1] | d[2] << 8, pos, d))
    result = {}
    for key, items in g.items():
        # majority base: addr - 256*page
        bases = collections.Counter((a - 256 * pg) & 0xffff for pg, a, _, _ in items)
        base, count = bases.most_common(1)[0]
        if count < 3:
            continue
        good = {}
        for pg, a, pos, d in items:
            if (a - 256 * pg) & 0xffff == base:
                good.setdefault(a, d)
        result[key] = good
    return result


def extract(out=ASSETS):
    images = {}
    for key, pages in groups().items():
        mem = bytearray(65536)
        for a, d in pages.items():
            mem[a:a + 256] = d[7:263]
        images[key] = mem
    out.mkdir(parents=True, exist_ok=True)
    for name, key, lo, hi in PARTS:
        (out / name).write_bytes(images[key][lo:hi])
        print(f'{name}: ${lo:04x}-${hi - 1:04x}')


if __name__ == '__main__':
    extract()
