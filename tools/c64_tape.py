"""Decode the turbo-loaded pages of the C64 Revs+ tape (assets/c64/Revs+_cleaned.tap).

The turbo blocks use two pulse lengths ($30 = 0 bit, $5A = 1 bit), MSB first.
Each page frame is 264 bytes: page number, load address (2), end address (2),
two further bytes, 256 data bytes and a checksum byte such that the XOR of
bytes 7..263 is zero. This module scans the whole tape for such frames rather
than relying on fixed offsets, and returns every decoded page.
"""
import sys
from functools import reduce
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TAPE = ROOT / 'assets/c64/Revs+_cleaned.tap'


def pulses(data):
    """Return the pulse byte stream with extended (0x00) pulses marked as 0."""
    out = []
    i = 20
    while i < len(data):
        b = data[i]
        if b == 0:
            out.append(0)
            i += 4
        else:
            out.append(b)
            i += 1
    return out


def runs(p):
    """Yield (start, length) of maximal runs consisting of $30/$5A pulses."""
    i = 0
    n = len(p)
    while i < n:
        if p[i] in (0x30, 0x5a):
            j = i
            while j < n and p[j] in (0x30, 0x5a):
                j += 1
            yield i, j - i
            i = j
        else:
            i += 1


def decode_bytes(p, start, count):
    return bytes(sum((p[start + i * 8 + b] == 0x5a) << (7 - b) for b in range(8)) for i in range(count))


def frames(p):
    """Find all candidate 264-byte page frames anywhere in the turbo runs.

    Every pulse offset is tried. Candidates must have a page-aligned load
    address below their end address and a valid XOR checksum; overlapping
    false positives are resolved later by group consistency.
    """
    found = []
    bits = bytes(1 if x == 0x5a else 0 for x in p)
    for start, length in runs(p):
        if length < 2112:
            continue
        for pos in range(start, start + length - 2111):
            if any(bits[pos + 8:pos + 16]):          # load address low byte must be 0
                continue
            data = decode_bytes(p, pos, 264)
            addr = data[1] | data[2] << 8
            end = data[3] | data[4] << 8
            if end > addr and reduce(int.__xor__, data[7:], 0) == 0:
                found.append((pos, data))
    return found


def memory_images():
    """Return {group_end_address: bytearray(65536)} keyed by the frames' end field."""
    p = pulses(TAPE.read_bytes())
    groups = {}
    for pos, data in frames(p):
        addr = data[1] | data[2] << 8
        end = data[3] | data[4] << 8
        mem = groups.setdefault(end, [bytearray(65536), []])
        mem[0][addr:addr + 256] = data[7:263]
        mem[1].append((data[0], addr, pos))
    return groups


if __name__ == '__main__':
    p = pulses(TAPE.read_bytes())
    print('pulses', len(p))
    for s, l in runs(p):
        if l > 500:
            print(f'run at {s} len {l}')
    groups = memory_images()
    for end, (mem, pages) in groups.items():
        addrs = sorted(a for _, a, _ in pages)
        print(f'end ${end:04x}: {len(pages)} pages ${addrs[0]:04x}..${addrs[-1] + 255:04x}',
              'page#', pages[0][0], '..', pages[-1][0])
