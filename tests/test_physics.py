"""Compare ApplyDrivingModel (and the routines it calls) with the C64 code.

Random driving states are written to both machines; the random number
source is fed with the same byte sequence on both sides (C64: reads of the
CIA timer $DC04; Z80: the Random routine is patched to read a table).
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import C64, Z80  # noqa: E402
from py65.memory import ObservableMemory  # noqa: E402

C64_APPLYDRIVINGMODEL = 0x46F3

# name: (C64 address, Z80 symbol, offset)
BYTES = {
    'playerYawAngleLo': (0x0a, 'playerYawAngleLo', 0), 'playerYawAngleHi': (0x0b, 'playerYawAngleHi', 0),
    'playerPitchAngle': (0x0d, 'playerPitchAngle', 0), 'directionFacing': (0x25, 'directionFacing', 0),
    'yGravityDelta': (0x26, 'yGravityDelta', 0), 'yJumpHeight': (0x28, 'yJumpHeight', 0),
    'heightAboveTrack': (0x2d, 'heightAboveTrack', 0), 'playerSpeedLo': (0x2e, 'playerSpeedLo', 0),
    'xPrevVelocityLo': (0x38, 'xPrevVelocityLo', 0), 'xPrevVelocityHi': (0x39, 'xPrevVelocityHi', 0),
    'xSpinVelocityLo': (0x3a, 'xSpinVelocityLo', 0), 'xSpinVelocityHi': (0x3b, 'xSpinVelocityHi', 0),
    'revCount': (0x3c, 'revCount', 0), 'engineTorque': (0x3d, 'engineTorque', 0),
    'throttleBrakeState': (0x3e, 'throttleBrakeState', 0), 'throttleBrake': (0x3f, 'throttleBrake', 0),
    'gearNumber': (0x40, 'gearNumber', 0), 'playerHeading': (0x44, 'playerHeading', 0),
    'spinPitchAngle': (0x4e, 'spinPitchAngle', 0), 'gearChangeKey': (0x58, 'gearChangeKey', 0),
    'clutchEngaged': (0x59, 'clutchEngaged', 0), 'revsOnGearChange': (0x5a, 'revsOnGearChange', 0),
    'bumpyGrassHeight': (0x5d, 'bumpyGrassHeight', 0), 'soundRevTarget': (0x5f, 'soundRevTarget', 0),
    'engineStatus': (0x61, 'engineStatus', 0), 'playerSpeedHi': (0x63, 'playerSpeedHi', 0),
    'mainLoopCounterLo': (0x6a, 'mainLoopCounterLo', 0), 'raceStarting': (0x6d, 'raceStarting', 0),
    'oddsOfEngineStart': (0x09, 'oddsOfEngineStart', 0), 'playerMoving': (0x90, 'playerMoving', 0),
    'playerSegmentIndex': (0x22, 'playerSegmentIndex', 0),
    'liftFromTorque': (0x6730, 'liftFromTorque', 0), 'wingBalance': (0x6731, 'wingBalance', 0),
    'playerSideways': (0x6732, 'playerSideways', 0), 'playerDrift': (0x673b, 'playerDrift', 0),
    'zTyreForceBoth': (0x673f, 'zTyreForceBoth', 0),
    'leftSurface': (0x757d, 'leftSurface', 0), 'rightSurface': (0x7645, 'rightSurface', 0),
    'carProgress19': (0x0164 + 19, 'CAR_PROGRESS', 19), 'carSpeedHi19': (0x0150 + 19, 'CAR_SPEEDHI', 19),
}
ARRAYS = {   # name: (C64 address, Z80 symbol, length)
    'sincos': (0x66e0, 'sinYawAngleLo', 6), 'tyreSqueal': (0x66e6, 'tyreSqueal', 2),
    'wingSetting': (0x66e8, 'wingSetting', 2), 'wingForce': (0x66ea, 'wingForce', 2),
    'wingForce95': (0x66ec, 'wingForce95', 2), 'physLo': (0x66ee, 'physLo', 3),
    'physHi': (0x6710, 'physHi', 15), 'physTop': (0x6720, 'physTop', 15),
}
OUT_IGNORE = {'sincos'}


class C64R(C64):
    def __init__(self):
        super().__init__()
        mem = ObservableMemory(subject=self.mem)
        self.rand = []
        mem.subscribe_to_read([0xDC04], lambda addr: self.rand.pop(0) if self.rand else 0)
        self.cpu.memory = mem
        # ScanKeyboard: no key pressed
        self.mem[0x0E50:0x0E55] = [0xA2, 0x00, 0xE0, 0xFF, 0x60]


def patch_z80_random(z, values):
    base = 0x5C00
    for i, v in enumerate(values):
        z.mem[base + i] = v
    code = [0x2A, 0xFE, 0x5B, 0x7E, 0x23, 0x22, 0xFE, 0x5B, 0xC9]   # ld hl,(ptr); ld a,(hl); inc hl; ld (ptr),hl; ret
    a = z.sym('Random')
    stub = 0x5B00
    for i, b in enumerate(code):
        z.mem[stub + i] = b
    z.mem[0x5BFE] = base & 255
    z.mem[0x5BFF] = base >> 8
    z.mem[a] = 0xC3
    z.mem[a + 1] = stub & 255
    z.mem[a + 2] = stub >> 8


def z_addr(z, sym, off):
    return z.sym(sym) + off


def set_state(c64, z, rng):
    vals = {}
    for k, (ca, zs, off) in BYTES.items():
        v = rng.randrange(256)
        vals[k] = v
    # keep the state plausible
    vals['engineStatus'] = rng.choice([0xFF, 0xFF, 0xFF, 0x00]) if False else 0xFF
    vals['gearNumber'] = rng.randrange(7)
    vals['throttleBrakeState'] = rng.choice([0, 1, 0x80])
    vals['heightAboveTrack'] = rng.choice([0, 0, 0, 1, 2, 5, 127])
    vals['directionFacing'] = rng.choice([0, 0x80])
    vals['playerSegmentIndex'] = 3 * rng.randrange(40)
    vals['raceStarting'] = rng.choice([0, 0x80, 160, 0x28])
    vals['leftSurface'] = rng.choice([0, 0xFF])
    vals['rightSurface'] = rng.choice([0, 0xFF])
    vals['playerSpeedHi'] = rng.randrange(120)
    vals['gearChangeKey'] = rng.choice([0, 0, 0xFF])
    for k, (ca, zs, off) in BYTES.items():
        c64.mem[ca] = vals[k]
        z.mem[z_addr(z, zs, off)] = vals[k]
    for k, (ca, zs, n) in ARRAYS.items():
        arr = [rng.randrange(256) for _ in range(n)]
        if k in ('physHi', 'physTop'):
            arr = [rng.randrange(256) for _ in range(n)]
        for i, v in enumerate(arr):
            c64.mem[ca + i] = v
            z.mem[z.sym(zs) + i] = v
    # keep velocities moderate: high bytes small signed values
    for i in range(15):
        v = rng.randrange(-6, 6) & 255
        c64.mem[0x6720 + i] = v
        z.mem[z.sym('physTop') + i] = v
    # player coordinates: C64 Lo $66f1+, Hi $66c0+, Top $66c3+
    for ax, nm in enumerate(('playerCoordX', 'playerCoordY', 'playerCoordZ')):
        lo, hi, top = (rng.randrange(256) for _ in range(3))
        c64.mem[0x66f1 + ax] = lo
        c64.mem[0x66c0 + ax] = hi
        c64.mem[0x66c3 + ax] = top
        z.mem[z.sym(nm)] = lo
        z.mem[z.sym(nm) + 1] = hi
        z.mem[z.sym(nm) + 2] = top
    for page, c64page in (('SEG_LO', 0x0900), ('SEG_HI', 0x0A00), ('SEGDATA', 0x8900)):
        data = [rng.randrange(256) for _ in range(256)]
        for i, v in enumerate(data):
            c64.mem[c64page + i] = v
            z.mem[z.sym(page) + i] = v


def compare(c64, z, label):
    errs = []
    for k, (ca, zs, off) in BYTES.items():
        a, b = c64.mem[ca], z.mem[z_addr(z, zs, off)]
        if a != b:
            errs.append(f'{k}: C64 {a} Z80 {b}')
    for k, (ca, zs, n) in ARRAYS.items():
        if k in OUT_IGNORE:
            continue
        a = list(c64.mem[ca:ca + n])
        b = [z.mem[z.sym(zs) + i] for i in range(n)]
        if a != b:
            errs.append(f'{k}: C64 {a} Z80 {b}')
    for ax, nm in enumerate(('playerCoordX', 'playerCoordY', 'playerCoordZ')):
        a = [c64.mem[0x66f1 + ax], c64.mem[0x66c0 + ax], c64.mem[0x66c3 + ax]]
        b = [z.mem[z.sym(nm) + i] for i in range(3)]
        if a != b:
            errs.append(f'{nm}: C64 {a} Z80 {b}')
    if errs:
        raise AssertionError(label + '\n  ' + '\n  '.join(errs))


def run(n, seed=0, routine=('ApplyDrivingModel', C64_APPLYDRIVINGMODEL)):
    rng = random.Random(seed)
    c64, z = C64R(), Z80()
    fails = 0
    for i in range(n):
        set_state(c64, z, rng)
        rnd = [rng.randrange(256) for _ in range(16)]
        c64.rand = list(rnd)
        patch_z80_random(z, rnd)
        c64.call(routine[1])
        z.call(routine[0])
        try:
            compare(c64, z, f'case {i}')
        except AssertionError as e:
            fails += 1
            if fails <= 3:
                print(e)
    return fails


if __name__ == '__main__':
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    f = run(n)
    print(f'physics: {n} cases, {f} failures')
