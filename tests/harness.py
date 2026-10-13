"""Differential test harness: C64 6502 routines (py65) vs Z80 routines (skoolkit).

C64: the decoded Revs+ memory image with Silverstone; routines are called with
a return sentinel. Z80: the built snapshot; routines are called by symbol name.
Variables are mapped by name (BBC names) to both address spaces.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))

from py65.devices.mpu6502 import MPU  # noqa: E402
from skoolkit.csimulator import CSimulator  # noqa: E402
from skoolkit.simutils import from_snapshot, PC, SP, A, F, B, C, D, E, H, L, T  # noqa: E402
from skoolkit.snapshot import Snapshot  # noqa: E402

from c64_image import main_image  # noqa: E402


def c64_symbols():
    syms = {}
    for line in (ROOT / 'notes/c64-labels.txt').read_text().split('\n'):
        m = re.match(r'\$([0-9a-f]{4}) (\S+)', line)
        if m:
            syms.setdefault(m.group(2), int(m.group(1), 16))
    return syms


def track_code(track):
    """The Z80 track code of a track as built (build/revs_trackcode_<track>.bin)."""
    return (ROOT / f"build/revs_trackcode_{track.lower().replace(' ', '')}.bin").read_bytes()


def z80_symbols():
    """The main program's symbols from the z80asm map (build/revs.map); local
    labels as Parent.local (z80asm: Parent@local)."""
    syms = {}
    for line in (ROOT / 'build/revs.map').read_text().split('\n'):
        m = re.match(r'(\S+)\s+=\s+\$([0-9A-Fa-f]+)\s*;\s*[^,]*,\s*[^,]*,\s*[^,]*,\s*([^,]*),', line)
        if m and m.group(3) == 'main':
            syms[m.group(1).replace('@', '.')] = int(m.group(2), 16)
    syms['ZP'] = syms['ZPAGE']          # (ZP is reserved in z80asm)
    # constants the code does not use are not in the map: those of memmap.asm
    # with a plain value
    for m in re.finditer(r'^(\w+)\s+EQU\s+\$([0-9A-Fa-f]+)\b', (ROOT / 'src/memmap.asm').read_text(), re.M):
        syms.setdefault(m.group(1), int(m.group(2), 16))
    return syms


# C64 addresses of variables not covered (or wrongly covered) by c64-labels
C64_VARS = {
    'playerMoving': 0x90, 'thisSectionFlags': 0x91, 'thisVectorNumber': 0x02,
    'currentPosition': 0x03, 'thisSectionNumber': 0x04, 'sectionListStart': 0x05,
    'sectionListValid': 0x06, 'sectionListSize': 0x07, 'sectionListPointer': 0x08,
    'playerYawAngleLo': 0x0a, 'playerYawAngleHi': 0x0b, 'playerPitchAngle': 0x0d,
    'segmentOffset': 0x0e, 'edgeDistanceLo': 0x10, 'edgeDistanceHi': 0x11,
    'segmentListPointer': 0x12, 'edgeSegmentNumber': 0x13, 'prevSegmentOffset': 0x14,
    'segmentListRight': 0x15, 'previousSteering': 0x16, 'turnCounter': 0x17,
    'prevDriverSpeed06': 0x18, 'debugSpinning': 0x1a, 'horizonLine': 0x1f,
    'prevDriverSpeed7': 0x20, 'sectionBehind': 0x21, 'playerSegmentIndex': 0x22,
    'prevSegmentIndex': 0x23, 'frontSegmentIndex': 0x24, 'directionFacing': 0x25,
    'scaleUp': 0x2a, 'scaleDown': 0x2b, 'pastHalfway': 0x30, 'segmentCounter': 0x42,
    'currentPlayer': 0x6f, 'resetSectionList': 0x62, 'newSectionFetched': 0x6735,
    'horizonListIndex': 0x51, 'prevHorizonIndex': 0x52, 'segmentDirection': 0x49,
    'markerNumber': 0x56, 'markersToDraw': 0x57, 'edgeSegmentPointer': 0x5c,
    'edgeYawAngle': 0x5e, 'spinPitchAngle': 0x4e,
    'II': 0x8a, 'JJ': 0x8b, 'K': 0x7c, 'L': 0x7d, 'LL': 0x8d,
    'OBJ_SECTION': 0x88e8, 'OBJ_SEGMT': 0x0880, 'OBJ_SEGLO': 0x08d0, 'OBJ_SEGHI': 0x08e8,
    'OBJ_STATUS': 0x018c, 'DRIVER_LAPNUMBER': 0x86b4,
    'SEG_LO': 0x0900, 'SEG_HI': 0x0a00, 'SEGDATA': 0x8900,
    'VERGE_XLO': 0x8400, 'VERGE_XHI': 0x8450, 'VERGE_DATA': 0x84a0, 'VERGE_Y': 0x84e0,
    'sectionSteering': 0x8520, 'refCoord': 0x66c0,
    'spinYawAngleHi': 0x6712, 'spinYawAngleTop': 0x6722,
}


class C64:
    SENTINEL = 0xFFF0

    def __init__(self):
        self.mem = list(main_image('Silverstone'))
        for a in (0xFFC2, 0xFFE0, 0xFFE3, 0xFFE7, 0xFFEE, 0xFFF1, 0xFFF4, 0xFFF7):
            self.mem[a] = 0x60              # OS / KERNAL entry points: RTS
        self.cpu = MPU(memory=self.mem)

    def call(self, addr, a=0, x=0, y=0, carry=0, limit=2_000_000):
        cpu = self.cpu
        cpu.pc, cpu.sp, cpu.a, cpu.x, cpu.y = addr, 0xFD, a, x, y
        cpu.p = 0x30 | (carry & 1)
        ret = self.SENTINEL - 1
        cpu.memory[0x1FE] = ret & 0xFF
        cpu.memory[0x1FF] = ret >> 8
        start = cpu.processorCycles
        for _ in range(limit):
            if cpu.pc == self.SENTINEL:
                return cpu.processorCycles - start
            cpu.step()
        raise AssertionError(f'C64 call ${addr:04x} did not return (pc ${cpu.pc:04x})')

    @property
    def carry(self):
        return self.cpu.p & 1

    def get(self, name, n=1):
        a = C64_VARS[name]
        return self.mem[a:a + n]

    def set(self, name, values):
        a = C64_VARS[name]
        if isinstance(values, int):
            values = [values]
        self.mem[a:a + len(values)] = list(values)


class Z80:
    SENTINEL = 0x0000                   # RET into ROM address 0 stops the run

    def __init__(self, sna=ROOT / 'build/revs.sna'):
        snap = Snapshot.get(str(sna))
        snap.sp = (snap.sp + 2) % 65536
        self.sim = from_snapshot(CSimulator, snap, config={'fast_djnz': False, 'fast_ldir': False})
        self.mem = self.sim.memory
        self.reg = self.sim.registers
        self.syms = z80_symbols()
        self.addr = dict(self.syms)
        e = self.syms['EDGE_PAGE1']             # empty edge tables, as StoreUI
        self.mem[e:e + 512] = [0] * 512         # leaves them (the UI is there)

        class _T:
            border = [(0, 0)]
            def read_port(self, registers, port):
                return 0xFF
            def write_port(self, registers, port, value, offset=0):
                pass
        self.sim.set_tracer(_T())

    def sym(self, name):
        return self.syms[name]

    def call(self, name, a=0, b=0, c=0, carry=0, limit=20_000_000, ix=None, iy=None, de=None, hl=None):
        r = self.reg
        if hl is not None:
            r[H], r[L] = hl >> 8, hl & 255
        if ix is not None:
            r[8], r[9] = ix >> 8, ix & 255
        if iy is not None:
            r[10], r[11] = iy >> 8, iy & 255
        if de is not None:
            r[D], r[E] = de >> 8, de & 255
        r[SP] = 0xFD50
        self.mem[0xFD50] = self.SENTINEL & 0xFF
        self.mem[0xFD51] = self.SENTINEL >> 8
        r[A], r[B], r[C] = a, b, c
        r[F] = carry & 1
        start = r[T]
        self.sim.trace(self.syms[name], self.SENTINEL, 0, start + limit, 0, None, None, None, None, None)
        if r[PC] != self.SENTINEL:
            raise AssertionError(f'Z80 call {name} did not return (pc ${r[PC]:04x})')
        return r[T] - start

    @property
    def carry(self):
        return self.reg[F] & 1

    RENAMED = {'H': 'Hv', 'I': 'Iv', 'L': 'Lv'}   # BBC names that clash with registers

    def get(self, name, n=1):
        a = self.syms[self.RENAMED.get(name, name)]
        return list(self.mem[a:a + n])

    def set(self, name, values):
        a = self.syms[self.RENAMED.get(name, name)]
        if isinstance(values, int):
            values = [values]
        for i, v in enumerate(values):
            self.mem[a + i] = v
