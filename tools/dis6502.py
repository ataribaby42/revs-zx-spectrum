"""Disassemble a range of the C64 Revs+ image (or the BBC listing image) with py65.

Usage: python tools/dis6502.py c64 START END   (hex addresses)
Labels from notes/c64-map.txt (BBC name -> C64 address) are shown where known.
"""
import re
import sys
from pathlib import Path

from py65.devices.mpu6502 import MPU
from py65.disassembler import Disassembler

sys.path.insert(0, str(Path(__file__).resolve().parent))
from c64_image import main_image, selector_image  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def c64_labels():
    labels = {}
    p = ROOT / 'notes/c64-map.txt'
    if p.exists():
        for l in p.read_text().split('\n'):
            m = re.match(r'(\S+)\s+\$([0-9a-f]{4}) (SAME|-> \$([0-9a-f]{4})(?:\s|$))', l)
            if m:
                name, bbc, kind, c64 = m.groups()
                a = int(bbc, 16) if kind == 'SAME' else int(c64, 16)
                labels.setdefault(a, name)
    extra = ROOT / 'notes/c64-labels.txt'
    if extra.exists():
        for l in extra.read_text().split('\n'):
            m = re.match(r'\$([0-9a-fA-F]{4})\s+(\S+)', l)
            if m:
                labels[int(m.group(1), 16)] = m.group(2)
    return labels


def disassemble(mem, start, end, labels):
    mpu = MPU(memory=list(mem))
    dis = Disassembler(mpu)
    a = start
    out = []
    while a < end:
        if a in labels:
            out.append(f'.{labels[a]}')
        length, text = dis.instruction_at(a)
        bs = ' '.join(f'{mem[a + i]:02x}' for i in range(length))

        def repl(m):
            v = int(m.group(1), 16)
            return m.group(0) + (f' ({labels[v]})' if v in labels else '')
        text = re.sub(r'\$([0-9a-f]{4}|[0-9a-f]{2})(?![0-9a-f])', repl, text) if not text.startswith(('LDA #', 'LDX #', 'LDY #', 'CMP #', 'CPX #', 'CPY #', 'ADC #', 'SBC #', 'AND #', 'ORA #', 'EOR #')) else text
        out.append(f'  {a:04x}  {bs:9s}  {text}')
        a += length
    return '\n'.join(out)


if __name__ == '__main__':
    which, s, e = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3], 16)
    mem = main_image() if which == 'c64' else selector_image()
    print(disassemble(mem, s, e, c64_labels()))
