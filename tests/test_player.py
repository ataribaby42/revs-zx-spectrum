"""Compare ProcessDrivingKeys, MovePlayerOnTrack, MovePlayerSegment and
ScaleWingSettings with the C64 code."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_physics as tp  # noqa: E402

# C64 key code -> Z80 key name
KEYS = {0x2D: 'O', 0x16: 'P', 0x27: 'SPACE', 0x29: 'Q', 0x11: 'A', 0x17: 'S', 0x37: 'W'}
ZROW = {'O': (5, 1), 'P': (5, 0), 'SPACE': (7, 0), 'Q': (2, 0), 'A': (1, 0), 'S': (1, 1), 'W': (2, 1)}

EXTRA = {'steeringLo': (0x66e2, 'steeringLo', 0), 'steeringHi': (0x66e5, 'steeringHi', 0),
         'gearChange': (0x19, 'gearChange', 0), 'leaveTrackTimer': (0x0f, 'leaveTrackTimer', 0),
         'edgeYawAngle': (0x5e, 'edgeYawAngle', 0), 'edgeSegmentPointer': (0x5c, 'edgeSegmentPointer', 0),
         'edgeDistanceLo': (0x10, 'edgeDistanceLo', 0), 'playerPastSegment': (0x43, 'playerPastSegment', 0),
         'carRacingLine19': (0x0178 + 19, 'CAR_RACINGLINE', 19), 'currentPlayer': (0x6f, 'currentPlayer', 0),
         'edgeSegmentNumber': (0x13, 'edgeSegmentNumber', 0),
         'frontWing': (0x84fd, 'frontWingSetting', 0), 'rearWing': (0x84fe, 'rearWingSetting', 0)}


def setup(c64, z, rng, keys):
    tp.set_state(c64, z, rng)
    for k, (ca, zs, off) in EXTRA.items():
        v = rng.randrange(256)
        if k == 'currentPlayer':
            v = 19
        if k == 'steeringHi':
            v = rng.randrange(150)
        if k in ('frontWing', 'rearWing'):
            v = rng.randrange(41)
        c64.mem[ca] = v
        z.mem[z.sym(zs) + off] = v
    c64.mem[0x9300:0x9400] = [0] * 256
    rows = [0] * 8
    for code in keys:
        c64.mem[0x9300 + code] = 0xFF
        r, b = ZROW[KEYS[code]]
        rows[r] |= 1 << b
    for i in range(8):
        z.mem[z.sym('keyRows') + i] = rows[i]


def compare(c64, z, label):
    tp.compare(c64, z, label)
    errs = []
    for k, (ca, zs, off) in EXTRA.items():
        a, b = c64.mem[ca], z.mem[z.sym(zs) + off]
        if a != b:
            errs.append(f'{k}: C64 {a} Z80 {b}')
    if errs:
        raise AssertionError(label + '\n  ' + '\n  '.join(errs))


def run(name, c64addr, n=500, seed=3, keys=True):
    rng = random.Random(seed)
    c64, z = tp.C64R(), tp.Z80()
    c64.mem[0x0E50:0x0E57] = [0xBD, 0x00, 0x93, 0xAA, 0xE0, 0xFF, 0x60]   # LDA $9300,X; TAX; CPX #$FF; RTS
    fails = 0
    for i in range(n):
        ks = [k for k in KEYS if keys and rng.random() < 0.3]
        setup(c64, z, rng, ks)
        c64.call(c64addr)
        z.call(name)
        try:
            compare(c64, z, f'{name} case {i} keys {[KEYS[k] for k in ks]}')
        except AssertionError as e:
            fails += 1
            if fails <= 2:
                print(e)
    print(f'{name}: {fails}/{n}')


if __name__ == '__main__':
    run('ProcessDrivingKeys', 0x1545)
    run('MovePlayerOnTrack', 0x4676, keys=False)
    run('ScaleWingSettings', 0x0B5F, keys=False)
