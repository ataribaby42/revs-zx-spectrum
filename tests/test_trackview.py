"""The track view against the C64: the same scene is set up on both machines
and the colour of every point of the track lines below the horizon is
compared (grass, road, verge colours; the objects are not drawn).

C64: GetTrackAndMarkers, DrawTrack (the verge edges into the dash data and
the background colour table) and SetBackground, then the rule of the C64's
DrawTrackView (created at run time; its template is at $3937): each track
line starts with its background colour, a non-zero dash data byte sets the
colour from there on (through the table at $6440). Dash data block I is at
$3000 + $80 * I (40 blocks of 4 pixels), lines dashDataOffset[I] + 1 to 79;
the lines below are behind the dashboard. Colour codes: 0 red, 1 black (road,
black verge), 2 white, 3 green (grass).

Spectrum: GetTrackAndMarkers, BuildEdges, then the colours of Compose's
spans (grass | left verge | road | right verge | grass) from the edge tables.
C64 pixel x (160 across, 4 per yaw unit) is Spectrum pixel 128 + (x - 80) *
1.75. A point differs when its colour is not found within one pixel or one
line in the other view (the two renderers round edges differently).

The two renderers agree in ordinary driving; with the car near or off the
verges, high above the track or pitched they still differ in places (the
C64 skips verge points it hides, fills grass by its own rules and can change
the colour several times on a line), so the limits are per group:

* driving: on the track, heading along it: at most 1% of a scene differs;
* across: heading 55 to 90 degrees from the track, on it and off it (the
  vertical bars and cut-off road of RasterTail's old straight-down tails
  made 4.9% on average): at most 4.2% on average (and 40% of a scene);
* reported: the scenes of those bug reports (formerly up to 29%): at most
  8% each.

Usage: python tests/test_trackview.py [driving scenes] [across scenes] [seed]
"""
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_verges as tv  # noqa: E402
from harness import C64, Z80  # noqa: E402

HIDDEN = Z80().sym('HIDDEN_LINES')


def scene(sec, adv, frac, lat, yaw_off, direction=0, height=172, pitch=0):
    """C64 and Z80 with the same track, player and verge buffer."""
    c64, z80 = C64(), Z80()
    track = c64.mem[0x5300:0x5B00]
    init = {'directionFacing': direction, 'frontSegmentIndex': 0, 'resetSectionList': 0,
            'turnCounter': 0, 'prevDriverSpeed7': 0, 'sectionListValid': 6, 'sectionListPointer': 5,
            'sectionListStart': 3, 'sectionListSize': 3, 'newSectionFetched': 0, 'pastHalfway': 0,
            'currentPlayer': 19, 'thisSectionFlags': 0, 'thisVectorNumber': 0,
            'spinYawAngleHi': 0, 'spinYawAngleTop': 0, 'spinPitchAngle': 0, 'markersToDraw': 0,
            'prevHorizonIndex': 0, 'horizonListIndex': 0}
    for m in (c64, z80):
        for k, v in init.items():
            m.set(k, v)
        for k in ('VERGE_XLO', 'VERGE_XHI', 'VERGE_DATA', 'VERGE_Y'):
            m.set(k, [0] * 256)
    size = track[0x607 + sec * 8]
    for k, v in {'OBJ_SECTION': sec * 8, 'OBJ_SEGMT': size - 1, 'OBJ_SEGLO': 5, 'OBJ_SEGHI': 1}.items():
        c64.mem[tv.C64_VARS[k] + 23] = v
        z80.mem[z80.sym(k) + 23] = v
    for _ in range(40 + adv):
        c64.call(tv.C64_GETTRACKSEGMENT)
        z80.call('GetTrackSegment')
    p = c64.get('playerSegmentIndex')[0]
    a, b, o = tv.seg_coord(c64, p), tv.seg_coord(c64, (p + 3) % 120), tv.seg_coord(c64, p + 0x78)
    s = tv.to_signed
    pos = [int(s(a[ax]) + frac * s((b[ax] - a[ax]) & 0xFFFF) + lat * s((o[ax] - a[ax]) & 0xFFFF)) & 0xFFFF
           for ax in range(3)]
    pos[1] = (pos[1] + height) & 0xFFFF
    along = math.atan2(s((b[0] - a[0]) & 0xFFFF), s((b[2] - a[2]) & 0xFFFF)) / (2 * math.pi) * 65536
    yaw = int(along + yaw_off) & 0xFFFF             # (directionFacing turns the segment list)
    rc = c64.get('refCoord', 12)
    for ax in range(3):
        rc[ax] = pos[ax] & 255
        rc[3 + ax] = pos[ax] >> 8
    c64.set('refCoord', rc)
    for ax, nm in enumerate(('playerCoordX', 'playerCoordY', 'playerCoordZ')):
        z80.set(nm, [0, pos[ax] & 255, pos[ax] >> 8])
    for m in (c64, z80):
        m.set('playerYawAngleLo', yaw & 255)
        m.set('playerYawAngleHi', yaw >> 8)
        m.set('playerPitchAngle', pitch & 255)
    sideways = player_sideways(z80)
    c64.mem[0x6732] = sideways
    z80.set('playerSideways', sideways)
    c64.call(tv.C64_GETTRACKANDMARKERS)
    z80.call('GetTrackAndMarkers')
    tv.compare(c64, z80, 'verge buffer')
    return c64, z80


def player_sideways(z):
    """playerSideways as the driving model computes it (ApplyElevation): the
    heading of the track at the player's segment relative to the player,
    0 (along the track) to 63 (across it)."""
    m = z.mem
    vec = m[z.sym('SEGDATA') + m[z.sym('playerSegmentIndex')]]
    d = m[z.sym('xTrackSegmentI') + vec]
    e = m[z.sym('zTrackSegmentI') + vec]
    sabs = lambda v: (256 - v) & 255 if v & 0x80 else v
    c = sabs(e)
    t = c if c < 60 else sabs(d)
    a = ((t >> 1) + t) >> 2
    if c < 60:
        a ^= 0x3F
    if e & 0x80:
        a ^= 0x80
    if (d ^ e) & 0x80:
        a = (256 - a) & 255
    a = (a - z.get('playerYawAngleHi')[0]) & 255
    if a & 0x80:
        a ^= 0xFF
    return a ^ 0x7F if a >= 64 else a


def c64_view(c64):
    """80 track lines (0 at the bottom) x 160 colour codes, None behind the
    dashboard."""
    m = c64.mem
    offs = m[0x3900:0x3928]
    for i in range(40):
        for line in range(offs[i] + 1, 80):
            m[0x3000 + 0x80 * i + line] = 0
    for a in range(0x63C0, 0x6410):
        m[a] = 0
    c64.call(0xB514)                    # DrawTrack
    c64.call(0xB3D4)                    # SetBackground
    view = []
    for line in range(80):
        a = m[0x63C0 + line]
        row = []
        for i in range(40):
            if line <= offs[i]:
                row += [None] * 4
                continue
            y = m[0x3000 + 0x80 * i + line]
            if y:
                a = m[0x6440 + y]
            row += [(a >> 6) & 3, (a >> 4) & 3, (a >> 2) & 3, a & 3]
        view.append(row)
    return view


def zx_view(z80):
    """80 track lines x 256 colour codes from BuildEdges' edge tables, as
    Compose draws them (None above the horizon)."""
    z80.call('BuildEdges')
    e1, e2 = z80.sym('EDGE_PAGE1'), z80.sym('EDGE_PAGE2')
    m = z80.mem
    horizon = z80.get('horizonLine')[0]
    view = []
    for line in range(80):
        if line > horizon:
            view.append([None] * 256)
            continue
        coll, colr = m[e2 + 0x50 + line], m[e2 + 0xA0 + line]
        if coll == 0xFF or colr == 0xFF:
            view.append([3] * 256)
            continue
        b1 = m[e1 + 0x50 + line]
        b0 = min(m[e1 + line], b1)
        b2 = max(b1, m[e1 + 0xA0 + line])
        b3 = max(b2, m[e2 + line])
        bounds = [v if v < 255 else 256 for v in (b0, b1, b2, b3)] + [257]
        colours = [3, coll, 1, colr, 3]
        row, span = [], 0
        for x in range(256):
            while x >= bounds[span]:
                span += 1
            row.append(colours[span])
        view.append(row)
    return view


def compare(cv, zv, horizon):
    """(points compared, points that differ)."""
    def zx_at(line, cx):
        return zv[line][min(255, max(0, int(128 + (cx + 0.5 - 80) * 1.75)))]
    n = bad = 0
    for line in range(HIDDEN, min(horizon, 79) + 1):
        for cx in range(7, 153):
            c = cv[line][cx]
            if c is None:
                continue
            z = zx_at(line, cx)
            if z is None:
                continue
            n += 1
            near_c = {cv[ln][x] for ln in (line - 1, line, line + 1) if 0 <= ln < 80
                      for x in (cx - 1, cx, cx + 1)}
            near_z = {zx_at(ln, x) for ln in (line - 1, line, line + 1) if HIDDEN <= ln < 80
                      for x in (cx - 1, cx, cx + 1)}
            if z not in near_c or c not in near_z:
                bad += 1
    return n, bad


# (section, advance, fraction, lateral, heading, directionFacing, height, pitch)
REPORTED = [(3, 10, 0.5, 1.8, 16384, 0, 172, 0), (3, 10, 0.5, 0.5, 16384, 0, 172, 0),
            (3, 10, 0.5, 0.5, -16384, 0, 172, 0), (3, 10, 0.5, -0.4, -16384, 0, 172, 0),
            (3, 10, 0.5, 1.2, 12000, 0, 172, 0), (12, 5, 0.5, 0.5, 16000, 0, 172, 0),
            (20, 15, 0.5, 0.4, -16300, 0, 172, 0), (7, 20, 0.5, 1.6, 15000, 0, 172, 0)]
GROUPS = {'driving': (0.01, None), 'across': (0.40, 0.042), 'reported': (0.08, None)}


def scenes(driving, across, seed):
    rng = random.Random(seed)
    for i in range(driving):
        yield 'driving', (rng.randrange(24), rng.randrange(0, 30), rng.random(), rng.uniform(0.3, 0.7),
                          rng.randrange(-1000, 1000), 0, 172, 0)
    for i in range(across):
        yield 'across', (rng.randrange(24), rng.randrange(0, 30), rng.random(), rng.uniform(-0.6, 1.6),
                         rng.choice([1, -1]) * rng.randrange(9000, 16385), rng.choice([0, 0, 0x80]), 172, 0)
    for args in REPORTED:
        yield 'reported', args


def main():
    driving = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    across = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    results = {g: [] for g in GROUPS}
    fails = 0
    for i, (group, args) in enumerate(scenes(driving, across, seed)):
        c64, z80 = scene(*args)
        n, bad = compare(c64_view(c64), zx_view(z80), z80.get('horizonLine')[0])
        frac = bad / n if n else 0
        results[group].append(frac)
        if frac > GROUPS[group][0]:
            fails += 1
            if fails <= 8:
                print(f'{group} scene {i} {args}: {bad} of {n} points differ ({100 * frac:.1f}%)')
    for g, (limit, mean_limit) in GROUPS.items():
        r = results[g]
        if not r:
            continue
        mean = sum(r) / len(r)
        bad_mean = mean_limit is not None and mean > mean_limit
        fails += bad_mean
        print(f'trackview {g}: {sum(v > limit for v in r)}/{len(r)} scenes over {100 * limit:.0f}%, '
              f'worst {100 * max(r):.1f}%, mean {100 * mean:.2f}%'
              + (f' (limit {100 * mean_limit:.1f}%{": FAIL" if bad_mean else ""})' if mean_limit is not None else ''))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
