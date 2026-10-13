"""The code of a C64 extra track file ($5300-$5AFF): the patches its track
hook ($5A30 -> ModifyGameCode) applies to the main game, and a recursive
disassembly of the routines they call, with the BBC labels of the same
track file (same layout at $5300) and the C64 names of main game routines.

Usage: python tools/c64_trackcode.py "Brands Hatch" [patches|code]
"""
import re
import sys
from pathlib import Path

from py65.devices.mpu6502 import MPU
from py65.disassembler import Disassembler

sys.path.insert(0, str(Path(__file__).resolve().parent))
from c64_image import TRACKS, load_parts, main_image, selector_image  # noqa: E402
from dis6502 import c64_labels  # noqa: E402
import bbc_tracks  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def raw_image(track):
    """The C64 image after the Revs+ installer, before the track hook."""
    mem = load_parts()
    sel = selector_image()
    st = 0x1800 + 0x800 * TRACKS.index(track)
    mem[0x5300:0x5b00] = sel[st:st + 0x800]
    mem[0x9c00:0x9e00] = sel[0x4800:0x4a00]
    cpu = MPU(memory=list(mem))
    cpu.pc, cpu.sp = 0x9c00, 0xff
    while cpu.pc != 0x5a30:
        cpu.step()
    return bytes(cpu.memory)


def patches(track):
    """[(address, old bytes, new bytes)] applied by the track hook."""
    a = raw_image(track)
    b = bytearray(a)
    cpu = MPU(memory=list(a))
    cpu.pc, cpu.sp = 0x5a30, 0xfd
    cpu.memory[0x1fe], cpu.memory[0x1ff] = 0xef, 0xff
    while cpu.pc != 0xfff0:
        cpu.step()
    b = bytes(cpu.memory)
    d = [x for x in range(0x0400, 0xff00) if a[x] != b[x] and not (0x5300 <= x < 0x5b00) and not (0x100 <= x < 0x200)]
    groups = []
    for x in d:
        if groups and x <= groups[-1][-1] + 2:
            groups[-1].append(x)
        else:
            groups.append([x])
    return [(g[0], a[g[0]:g[-1] + 1], b[g[0]:g[-1] + 1]) for g in groups], a, b


def disassemble(track):
    pts, before, after = patches(track)
    labels = c64_labels()
    bbc = bbc_tracks.labels(bbc_tracks.parse()[bbc_tracks.FILES[track]])
    bbc_at = {}
    for k, v in bbc.items():
        bbc_at.setdefault(v, []).append(k)
    mem = after
    mpu = MPU(memory=list(mem))
    dis = Disassembler(mpu)
    # entry points: JSR/JMP targets in the track block from the patches
    todo = []
    for addr, old, new in pts:
        for i in range(len(new)):
            if new[i] in (0x20, 0x4C) and i + 2 < len(new) + 1:
                t = new[i + 1] | (new[i + 2] << 8) if i + 2 < len(new) else None
                if t and 0x5300 <= t < 0x5b00:
                    todo.append(t)
        # 3-byte JSR written across the patch boundary
        for k in range(1, 3):
            x = addr - k
            if mem[x] in (0x20, 0x4C):
                t = mem[x + 1] | (mem[x + 2] << 8)
                if 0x5300 <= t < 0x5b00:
                    todo.append(t)
    seen = set()
    code = {}
    while todo:
        pc = todo.pop()
        while pc not in seen and 0x5300 <= pc < 0x5b00:
            seen.add(pc)
            length, text = dis.instruction_at(pc)
            code[pc] = (length, text)
            op = mem[pc]
            m = re.search(r'\$([0-9a-f]{4})', text)
            target = int(m.group(1), 16) if m else None
            if op in (0x20, 0x4C) and target is not None and 0x5300 <= target < 0x5b00:
                todo.append(target)
            if op in (0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0) and target is not None:
                todo.append(target)
            if op in (0x60, 0x40, 0x4C, 0x6C):
                break
            pc += length
    return pts, code, labels, bbc_at, mem


def main():
    track = sys.argv[1]
    what = sys.argv[2] if len(sys.argv) > 2 else 'code'
    pts, code, labels, bbc_at, mem = disassemble(track)
    if what == 'patches':
        for addr, old, new in pts:
            print(f'{addr:04x} {labels.get(addr, ""):24s} {old.hex()} -> {new.hex()}')
        return
    prev = None
    for pc in sorted(code):
        if prev is not None and pc != prev:
            print('        ...')
        for lab in bbc_at.get(pc, []):
            print(f'.{lab}')
        length, text = code[pc]
        raw = ' '.join(f'{b:02x}' for b in mem[pc:pc + length])
        m = re.search(r'\$([0-9a-f]{4})', text)
        note = ''
        if m:
            t = int(m.group(1), 16)
            if t in labels:
                note = labels[t]
            elif t in bbc_at:
                note = bbc_at[t][0]
        print(f'  {pc:04x}  {raw:9s} {text:18s} {note}')
        prev = pc + length


if __name__ == '__main__':
    main()
