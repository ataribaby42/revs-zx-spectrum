"""Compare GetTrackAndMarkers (verge buffer) with the C64 code on real track data."""
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import C64, C64_VARS, Z80  # noqa: E402

C64_GETTRACKSEGMENT = 0x12AB
C64_GETTRACKANDMARKERS = 0x2222

C64_VARS.update({'horizonTrackWidth': 0x673c, 'markerListIndex': 0x66f4, 'markerData': 0x66d9,
                 'xMarkerLo': 0x66f7, 'xMarkerHi': 0x66fa, 'segmentStep': 0x3dd0})

SCALARS = ['horizonLine', 'horizonListIndex', 'prevHorizonIndex', 'edgeDistanceLo', 'edgeDistanceHi',
           'edgeSegmentNumber', 'edgeSegmentPointer', 'edgeYawAngle', 'segmentListPointer',
           'segmentListRight', 'prevSegmentOffset', 'markersToDraw', 'sectionListStart',
           'sectionListValid', 'sectionListPointer', 'thisSectionNumber', 'horizonTrackWidth',
           'segmentOffset', 'segmentDirection', 'newSectionFetched']


def set_both(c64, z80, name, values):
    c64.set(name, values)
    z80.set(name, values)


def seg_coord(m, idx):
    lo = m.get('SEG_LO', 256)
    hi = m.get('SEG_HI', 256)
    return [(lo[idx + a] | hi[idx + a] << 8) for a in range(3)]


def to_signed(v):
    return v - 65536 if v >= 32768 else v


def place_player(c64, z80, rng, frac, lateral, direction):
    """Put the player near segment playerSegmentIndex, facing along the track."""
    p = c64.get('playerSegmentIndex')[0]
    a = seg_coord(c64, p)
    b = seg_coord(c64, (p + 3) % 120)
    o = seg_coord(c64, p + 0x78)
    pos = []
    for ax in range(3):
        base = to_signed(a[ax]) + frac * to_signed((b[ax] - a[ax]) & 0xFFFF)
        across = lateral * to_signed((o[ax] - a[ax]) & 0xFFFF)
        pos.append(int(base + across) & 0xFFFF)
    pos[1] = (pos[1] + 172 + rng.randrange(-40, 40)) & 0xFFFF
    dx = to_signed((b[0] - a[0]) & 0xFFFF)
    dz = to_signed((b[2] - a[2]) & 0xFFFF)
    yaw = int(math.atan2(dx, dz) / (2 * math.pi) * 65536 + rng.randrange(-1500, 1500))
    if direction:
        yaw += 32768
    yaw &= 0xFFFF
    # C64 layout: $66c0 xHi,yHi,zHi, xTop,yTop,zTop
    rc = c64.get('refCoord', 12)
    for ax in range(3):
        rc[ax] = pos[ax] & 255
        rc[3 + ax] = pos[ax] >> 8
    c64.set('refCoord', rc)
    for ax, nm in enumerate(('playerCoordX', 'playerCoordY', 'playerCoordZ')):
        z80.set(nm, [0, pos[ax] & 255, pos[ax] >> 8])
    set_both(c64, z80, 'playerYawAngleLo', yaw & 255)
    set_both(c64, z80, 'playerYawAngleHi', yaw >> 8)
    set_both(c64, z80, 'playerPitchAngle', rng.randrange(-4, 5) & 255)


def compare(c64, z80, label):
    errors = []
    for v in SCALARS:
        a, b = c64.get(v)[0], z80.get(v)[0]
        if a != b:
            errors.append(f'{v}: C64 {a} Z80 {b}')
    for page in ('VERGE_XLO', 'VERGE_XHI', 'VERGE_DATA', 'VERGE_Y'):
        a, b = list(c64.get(page, 80)), list(z80.get(page, 80))
        idx = range(80) if page in ('VERGE_XLO', 'VERGE_XHI') else list(range(24)) + list(range(40, 64))
        diff = [(i, a[i], b[i]) for i in idx if a[i] != b[i]]
        if diff:
            errors.append(f'{page}: {diff[:8]}')
    for arr, n in (('markerListIndex', 3), ('markerData', 3), ('xMarkerLo', 3), ('xMarkerHi', 3)):
        a, b = list(c64.get(arr, n)), list(z80.get(arr, n))
        if a != b:
            errors.append(f'{arr}: C64 {a} Z80 {b}')
    if errors:
        raise AssertionError(label + '\n  ' + '\n  '.join(errors))


def run(seed, frames=40):
    rng = random.Random(seed)
    c64, z80 = C64(), Z80()
    direction = 0 if seed % 3 else 0x80
    track = c64.mem[0x5300:0x5B00]
    sec = rng.randrange(track[0x6FA] // 8)
    init = {'directionFacing': direction, 'frontSegmentIndex': 0, 'resetSectionList': 0,
            'turnCounter': 0, 'prevDriverSpeed7': 0, 'sectionListValid': 6, 'sectionListPointer': 5,
            'sectionListStart': 3, 'sectionListSize': 3, 'newSectionFetched': 0, 'pastHalfway': 0,
            'currentPlayer': 19, 'thisSectionFlags': 0, 'thisVectorNumber': 0,
            'spinYawAngleHi': 0, 'spinYawAngleTop': 0, 'spinPitchAngle': 0, 'markersToDraw': 0,
            'prevHorizonIndex': 0, 'horizonListIndex': 0}
    junk = {k: [rng.randrange(256) for _ in range(256)] for k in ('SEG_LO', 'SEG_HI', 'SEGDATA')}
    vjunk = {k: [rng.randrange(256) for _ in range(80)] for k in ('VERGE_XLO', 'VERGE_XHI', 'VERGE_DATA', 'VERGE_Y')}
    steering = [rng.randrange(256) for _ in range(26)]
    for m in (c64, z80):
        for k, v in list(junk.items()) + list(vjunk.items()):
            m.set(k, v)
        m.set('sectionSteering', steering)
        for k, v in init.items():
            m.set(k, v)
    size = track[0x607 + sec * 8]
    for k, v in {'OBJ_SECTION': sec * 8, 'OBJ_SEGMT': size - 1, 'OBJ_SEGLO': 5, 'OBJ_SEGHI': 1}.items():
        c64.mem[C64_VARS[k] + 23] = v
        z80.mem[z80.sym(k) + 23] = v
    for _ in range(40):
        c64.call(C64_GETTRACKSEGMENT)
        z80.call('GetTrackSegment')
    for f in range(frames):
        place_player(c64, z80, rng, rng.random(), rng.uniform(-0.2, 1.2), direction)
        if rng.random() < 0.3:
            spin = rng.randrange(-300, 300) & 0xFFFF
            set_both(c64, z80, 'spinYawAngleHi', spin & 255)
            set_both(c64, z80, 'spinYawAngleTop', spin >> 8)
            set_both(c64, z80, 'spinPitchAngle', rng.randrange(-3, 4) & 255)
        else:
            for k in ('spinYawAngleHi', 'spinYawAngleTop', 'spinPitchAngle'):
                set_both(c64, z80, k, 0)
        c64.call(C64_GETTRACKANDMARKERS)
        z80.call('GetTrackAndMarkers')
        compare(c64, z80, f'seed {seed} frame {f}')
        set_both(c64, z80, 'markersToDraw', 0)
        if rng.random() < 0.7:
            c64.call(C64_GETTRACKSEGMENT)
            z80.call('GetTrackSegment')


if __name__ == '__main__':
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    for seed in range(n):
        run(seed)
    print(f'verges: {n} sequences OK')
