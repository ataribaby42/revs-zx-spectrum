"""Compare the field of view hook of the extra tracks (C64: the routine that
MapSegmentsToLines calls in place of CheckVergeOnScreen, BBC HookFlattenHills)
with the Z80 HookFov, after GetTrackAndMarkers on real track data: raised
verge lines, the object cut-off line (C64 $1B0C) and horizonTrackWidth.

Needs an extra track with its track code: run it through a wrapper that loads
the track (the C64 image with its track hook, the Z80 track and track code).
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import C64, Z80  # noqa: E402
import test_verges as tv  # noqa: E402

C64_FOV_SITE = 0xB467                   # MapSegmentsToLines: JSR (hook)
C64_CHECKVERGE = 0xB451
C64_CUTOFF = 0x1B0C


def run(seed, frames=40):
    rng = random.Random(seed)
    c64, z80 = C64(), Z80()
    hook = c64.mem[C64_FOV_SITE + 1] | c64.mem[C64_FOV_SITE + 2] << 8
    if hook == C64_CHECKVERGE:
        return False
    cutoff = z80.sym('DrawObject.tcCutoff')
    assert z80.mem[cutoff] == 0x3E, 'track code not applied'
    site = z80.sym('MainDrivingLoop.tcEdges') + 1   # call HookFov (patched)
    z80.syms['HookFov'] = z80.mem[site] | z80.mem[site + 1] << 8
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
        c64.mem[tv.C64_VARS[k] + 23] = v
        z80.mem[z80.sym(k) + 23] = v
    for _ in range(40):
        c64.call(tv.C64_GETTRACKSEGMENT)
        z80.call('GetTrackSegment')
    raised = 0
    for f in range(frames):
        tv.place_player(c64, z80, rng, rng.random(), rng.uniform(-0.2, 1.2), direction)
        c64.call(tv.C64_GETTRACKANDMARKERS)
        z80.call('GetTrackAndMarkers')
        label = f'seed {seed} frame {f}'
        tv.compare(c64, z80, label)
        before = list(c64.get('VERGE_Y', 80))
        hz = c64.get('horizonListIndex')[0]
        for end, first in (('segmentListPointer', hz + 40), ('segmentListRight', hz)):
            e = c64.get(end)[0]
            c64.mem[0x4B] = e                   # MapSegmentsToLines: STY $4B
            c64.call(hook, x=first, y=(e - 1) & 255)
        z80.call('HookFov')
        errors = []
        a, b = list(c64.get('VERGE_Y', 80)), list(z80.get('VERGE_Y', 80))
        idx = list(range(24)) + list(range(40, 64))
        diff = [(i, a[i], b[i]) for i in idx if a[i] != b[i]]
        if diff:
            errors.append(f'VERGE_Y: {diff[:8]}')
        if c64.mem[C64_CUTOFF] != z80.mem[cutoff + 1]:
            errors.append(f'cut-off: C64 {c64.mem[C64_CUTOFF]} Z80 {z80.mem[cutoff + 1]}')
        a, b = c64.get('horizonTrackWidth')[0], z80.get('horizonTrackWidth')[0]
        if a != b:
            errors.append(f'horizonTrackWidth: C64 {a} Z80 {b}')
        if errors:
            raise AssertionError(label + '\n  ' + '\n  '.join(errors))
        raised += sum(1 for i in idx if before[i] != c64.get('VERGE_Y', 80)[i])
        set_both = tv.set_both
        set_both(c64, z80, 'markersToDraw', 0)
        if rng.random() < 0.7:
            c64.call(tv.C64_GETTRACKSEGMENT)
            z80.call('GetTrackSegment')
    return raised


if __name__ == '__main__':
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    total = 0
    for seed in range(n):
        r = run(seed)
        if r is False:
            print('field of view: no hook on this track')
            sys.exit(0)
        total += r
    print(f'field of view: {n} sequences OK ({total} verge lines raised)')
