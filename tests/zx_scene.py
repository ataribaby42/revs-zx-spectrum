"""Set up a track scene with the Z80 code and render it (screenshots + timing)."""
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from harness import Z80  # noqa: E402
from zx import BRIGHT, PALETTE  # noqa: E402
from PIL import Image  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def to_signed(v):
    return v - 65536 if v >= 32768 else v


def seg_coord(z, idx):
    lo = z.get('SEG_LO', 256)
    hi = z.get('SEG_HI', 256)
    return [(lo[idx + a] | hi[idx + a] << 8) for a in range(3)]


def setup(z, section, advance, direction=0):
    m = z.mem
    track = z.get('TRACK', 0x800)
    for k, v in {'directionFacing': direction, 'frontSegmentIndex': 0, 'resetSectionList': 0,
                 'turnCounter': 0, 'sectionListValid': 6, 'sectionListPointer': 5,
                 'sectionListStart': 3, 'sectionListSize': 3, 'newSectionFetched': 0,
                 'currentPlayer': 19, 'spinYawAngleHi': 0, 'spinYawAngleTop': 0,
                 'spinPitchAngle': 0, 'markersToDraw': 0}.items():
        z.set(k, v)
    size = track[0x607 + section * 8]
    for k, v in {'OBJ_SECTION': section * 8, 'OBJ_SEGMT': size - 1, 'OBJ_SEGLO': 5, 'OBJ_SEGHI': 1}.items():
        m[z.sym(k) + 23] = v
    for _ in range(40 + advance):
        z.call('GetTrackSegment')


def place(z, frac=0.5, lateral=0.5, yaw_offset=0, height=172, pitch=0):
    p = z.get('playerSegmentIndex')[0]
    a = seg_coord(z, p)
    b = seg_coord(z, (p + 3) % 120)
    o = seg_coord(z, p + 0x78)
    pos = []
    for ax in range(3):
        base = to_signed(a[ax]) + frac * to_signed((b[ax] - a[ax]) & 0xFFFF)
        across = lateral * to_signed((o[ax] - a[ax]) & 0xFFFF)
        pos.append(int(base + across) & 0xFFFF)
    pos[1] = (pos[1] + height) & 0xFFFF
    dx = to_signed((b[0] - a[0]) & 0xFFFF)
    dz = to_signed((b[2] - a[2]) & 0xFFFF)
    yaw = (int(math.atan2(dx, dz) / (2 * math.pi) * 65536) + yaw_offset) & 0xFFFF
    for ax, nm in enumerate(('playerCoordX', 'playerCoordY', 'playerCoordZ')):
        z.set(nm, [0, pos[ax] & 255, pos[ax] >> 8])
    z.set('playerYawAngleLo', yaw & 255)
    z.set('playerYawAngleHi', yaw >> 8)
    z.set('playerPitchAngle', pitch & 255)


def screenshot(z, path, scale=3):
    m = z.mem
    img = Image.new('RGB', (256, 192))
    px = img.load()
    for y in range(192):
        base = 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
        for cx in range(32):
            attr = m[0x5800 + (y >> 3) * 32 + cx]
            pal = BRIGHT if attr & 0x40 else PALETTE
            ink, paper = pal[attr & 7], pal[(attr >> 3) & 7]
            b = m[base + cx]
            for bit in range(8):
                px[cx * 8 + bit, y] = ink if b & (0x80 >> bit) else paper
    img.resize((256 * scale, 192 * scale), Image.NEAREST).save(path)


def scene(seed):
    rng = random.Random(seed)
    z = Z80()
    for a in range(0x5800, 0x5B00):
        z.mem[a] = 0x38
    setup(z, rng.randrange(24), rng.randrange(0, 30))
    place(z, rng.random(), rng.uniform(0.2, 0.8), rng.randrange(-1200, 1200))
    t1 = z.call('GetTrackAndMarkers')
    t2 = z.call('BuildEdges')
    t3 = z.call('Compose')
    t4 = z.call('CopyViewSimple')
    return z, (t1, t2, t3, t4)


if __name__ == '__main__':
    out = ROOT / 'build/scenes'
    out.mkdir(parents=True, exist_ok=True)
    for s in range(int(sys.argv[1]) if len(sys.argv) > 1 else 3):
        z, t = scene(s)
        screenshot(z, out / f'z80_{s}.png')
        print(s, 'verges', t[0], 'edges', t[1], 'compose', t[2], 'copy', t[3])
