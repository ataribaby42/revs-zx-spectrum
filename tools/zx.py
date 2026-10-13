"""Headless ZX Spectrum 48K harness for tests and screenshots (skoolkit C simulator).

Machine(sna) loads a 48K SNA snapshot produced by the build. run_frames()
executes whole 50 Hz frames with interrupts and ULA contention, pressing the
given keys. screenshot() writes a PNG of the current screen.
"""
from pathlib import Path

from PIL import Image
from skoolkit.ccmiosimulator import CCMIOSimulator
from skoolkit.csimulator import CSimulator
from skoolkit.simutils import from_snapshot, PC, T
from skoolkit.snapshot import Snapshot

# Spectrum keyboard half-rows (port bits 0..4)
KEYMAP = {}
_ROWS = [
    ['CAPS', 'Z', 'X', 'C', 'V'],      # $FEFE
    ['A', 'S', 'D', 'F', 'G'],         # $FDFE
    ['Q', 'W', 'E', 'R', 'T'],         # $FBFE
    ['1', '2', '3', '4', '5'],         # $F7FE
    ['0', '9', '8', '7', '6'],         # $EFFE
    ['P', 'O', 'I', 'U', 'Y'],         # $DFFE
    ['ENTER', 'L', 'K', 'J', 'H'],     # $BFFE
    ['SPACE', 'SYM', 'M', 'N', 'B'],   # $7FFE
]
for _r, _keys in enumerate(_ROWS):
    for _b, _k in enumerate(_keys):
        KEYMAP[_k] = (_r, _b)

PALETTE = [(0, 0, 0), (0, 0, 205), (205, 0, 0), (205, 0, 205), (0, 205, 0), (0, 205, 205),
           (205, 205, 0), (205, 205, 205)]
BRIGHT = [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255), (0, 255, 0), (0, 255, 255),
          (255, 255, 0), (255, 255, 255)]


class Ports:
    """Tracer providing keyboard (and Kempston joystick) input and recording
    border/beeper output."""

    def __init__(self):
        self.keyboard = [0] * 8
        self.kempston = None            # port $1F value; None: no interface
        self.outfe = 0
        self.beeper = []
        self.border = [(0, 0)]

    def read_port(self, registers, port):
        if port % 2 == 0:
            h = (port >> 8) ^ 0xFF
            v = 0
            for i in range(8):
                if h & (1 << i):
                    v |= self.keyboard[i]
            return (~v & 0x1F) | 0xE0
        if port & 0xFF == 0x1F and self.kempston is not None:
            return self.kempston
        return 0xFF

    def write_port(self, registers, port, value, offset=0):
        if port % 2 == 0:
            if (self.outfe ^ value) & 0x10:
                self.beeper.append(registers[T])
            self.outfe = value


class Machine:
    def __init__(self, sna, contention=True):
        snapshot = Snapshot.get(str(sna))
        snapshot.sp = (snapshot.sp + 2) % 65536 if snapshot.type == 'SNA' else snapshot.sp
        cls = CCMIOSimulator if contention else CSimulator
        self.sim = from_snapshot(cls, snapshot, config={'fast_djnz': False, 'fast_ldir': False})
        self.ports = Ports()
        self.sim.set_tracer(self.ports)
        self.mem = self.sim.memory
        self.reg = self.sim.registers

    @property
    def tstates(self):
        return self.reg[T]

    def press(self, keys):
        kb = [0] * 8
        for k in keys:
            r, b = KEYMAP[k]
            kb[r] |= 1 << b
        self.ports.keyboard[:] = kb

    def run_tstates(self, n, stop=None):
        """Run for n T-states (with interrupts) or until PC == stop."""
        start = self.reg[T]
        self.sim.trace(self.reg[PC], stop if stop is not None else -1, 0, start + n, 1, None, None, None, None, None)

    def run_frames(self, n, keys=()):
        self.press(keys)
        fd = 69888
        target = ((self.reg[T] // fd) + n) * fd
        self.sim.trace(self.reg[PC], -1, 0, target, 1, None, None, None, None, None)

    def run_until(self, pc, max_t=50_000_000):
        start = self.reg[T]
        self.sim.trace(self.reg[PC], pc, 0, start + max_t, 1, None, None, None, None, None)
        return self.reg[PC] == pc

    def peek(self, a):
        return self.mem[a]

    def peekw(self, a):
        return self.mem[a] | self.mem[a + 1] << 8

    def screenshot(self, path, scale=2):
        img = Image.new('RGB', (256, 192))
        px = img.load()
        m = self.mem
        for y in range(192):
            base = 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
            for cx in range(32):
                attr = m[0x5800 + (y >> 3) * 32 + cx]
                pal = BRIGHT if attr & 0x40 else PALETTE
                ink, paper = pal[attr & 7], pal[(attr >> 3) & 7]
                b = m[base + cx]
                for bit in range(8):
                    px[cx * 8 + bit, y] = ink if b & (0x80 >> bit) else paper
        if scale != 1:
            img = img.resize((256 * scale, 192 * scale), Image.NEAREST)
        img.save(path)
