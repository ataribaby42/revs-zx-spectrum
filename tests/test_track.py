"""Compare the segment-buffer routines (GetTrackSegment etc.) with the C64 code."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import C64, Z80  # noqa: E402

C64_GETTRACKSEGMENT = 0x12AB
C64_TURNPLAYERAROUND = 0x13E1

VARS = ['frontSegmentIndex', 'prevSegmentIndex', 'playerSegmentIndex', 'thisVectorNumber',
        'thisSectionFlags', 'sectionListSize', 'sectionListValid', 'sectionBehind',
        'turnCounter', 'prevDriverSpeed7', 'prevDriverSpeed06', 'previousSteering',
        'pastHalfway', 'newSectionFetched', 'directionFacing']


def setup(c64, z80, rng, direction):
    steering = [rng.randrange(256) for _ in range(26)]
    track = c64.mem[0x5300:0x5B00]
    nsec = track[0x6FA] // 8
    sec = rng.randrange(nsec)
    size = track[0x607 + sec * 8]
    segmt = rng.randrange(size)
    seg = rng.randrange(1024)
    state = {
        'directionFacing': direction, 'frontSegmentIndex': 3 * rng.randrange(40),
        'resetSectionList': 0, 'turnCounter': 0, 'prevDriverSpeed7': rng.randrange(256),
        'prevDriverSpeed06': 0, 'previousSteering': 0, 'sectionListValid': 6,
        'thisVectorNumber': rng.randrange(track[0x6FB]), 'thisSectionFlags': track[0x600 + sec * 8],
        'pastHalfway': 0, 'currentPlayer': 19,
    }
    junk = {k: [rng.randrange(256) for _ in range(256)] for k in ('SEG_LO', 'SEG_HI', 'SEGDATA')}
    for m in (c64, z80):
        for k, v in junk.items():
            m.set(k, v)
        m.set('sectionSteering', steering)
        for k, v in state.items():
            m.set(k, v)
        m.set_index('OBJ_SECTION', 23, sec * 8) if hasattr(m, 'set_index') else None
    for m in (c64, z80):
        base = {'OBJ_SECTION': sec * 8, 'OBJ_SEGMT': segmt, 'OBJ_SEGLO': seg & 255, 'OBJ_SEGHI': seg >> 8}
        for k, v in base.items():
            if m is c64:
                c64.mem[c64_addr(k) + 23] = v
            else:
                z80.mem[z80.sym(k) + 23] = v


def c64_addr(name):
    from harness import C64_VARS
    return C64_VARS[name]


def compare(c64, z80, label):
    errors = []
    for v in VARS:
        a, b = c64.get(v)[0], z80.get(v)[0]
        if a != b:
            errors.append(f'{v}: C64 {a} Z80 {b}')
    for page in ('SEG_LO', 'SEG_HI'):
        a = c64.get(page, 0xF4)
        b = z80.get(page, 0xF4)
        if list(a) != list(b):
            diff = [i for i in range(0xF4) if a[i] != b[i]]
            errors.append(f'{page} differs at {diff[:10]}')
    a, b = c64.get('SEGDATA', 120), z80.get('SEGDATA', 120)
    if list(a) != list(b):
        diff = [(i, a[i], b[i]) for i in range(120) if a[i] != b[i]]
        errors.append(f'SEGDATA differs {diff[:10]}')
    for k in ('OBJ_SECTION', 'OBJ_SEGMT', 'OBJ_SEGLO', 'OBJ_SEGHI'):
        a = c64.mem[c64_addr(k) + 23]
        b = z80.mem[z80.sym(k) + 23]
        if a != b:
            errors.append(f'{k}[23]: C64 {a} Z80 {b}')
    if errors:
        raise AssertionError(label + '\n  ' + '\n  '.join(errors))


def run(seed, steps=60):
    rng = random.Random(seed)
    c64, z80 = C64(), Z80()
    direction = rng.choice([0, 0x80])
    setup(c64, z80, rng, direction)
    for i in range(steps):
        if rng.random() < 0.05:
            n = rng.choice([1, 2, 39, 40])
            c64.call(C64_TURNPLAYERAROUND, x=n)
            z80.call('TurnPlayerAround', a=n)
            compare(c64, z80, f'seed {seed} step {i} TurnPlayerAround({n})')
        else:
            c64.call(C64_GETTRACKSEGMENT)
            z80.call('GetTrackSegment')
            compare(c64, z80, f'seed {seed} step {i} GetTrackSegment')


if __name__ == '__main__':
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    for seed in range(n):
        run(seed)
    print(f'track: {n} random sequences OK')
