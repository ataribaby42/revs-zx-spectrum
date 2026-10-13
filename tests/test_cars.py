"""Compare race set-up, lap and timer routines with the C64 code, using the
whole mapped game state (tests/state.py)."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import state  # noqa: E402
import test_physics as tp  # noqa: E402

C64 = {'BuildRoadSign': 0x4cfb, 'ProcessContact': 0x4f72, 'CheckForCrash': 0x1053,
       'FinishRace': 0x10a5, 'BuildPlayerCar': 0x1182, 'BuildVisibleCar': 0x278f, 'MoveAndDrawCars': 0x2399, 'MoveCars': 0x25d3, 'ProcessOvertaking': 0x23f6, 'ResetVariables': 0xb317, 'PlaceCarsOnTrack': 0x0c47, 'CompareSegments': 0x2583,
       'SwapDriverPosition': 0x23e3, 'UpdateLaps': 0x4e5f, 'AddTimeToTimer': 0xb2d5,
       'ProcessTime': 0x4f38, 'UpdateLapTimers': 0x0fa8, 'UpdatePositionInfo': 0x5221}

ENTRIES = state.all_entries()
ZP = {'frontSegmentIndex': 0x24, 'currentPlayer': 0x6f, 'raceStarted': 0x6c, 'raceStarting': 0x6d, 'numberOfLaps': 0x6e,
      'timerAdjust': 0x46, 'pastHalfway': 0x30, 'updateDrivingInfo': 0x66, 'leaveTrackTimer': 0x0f,
      'qualifyTimeEnding': 0x65, 'positionChangeBCD': 0x2f, 'currentPositionBCD': 0x31,
      'positionAhead': 0x4d, 'positionBehind': 0x5b, 'currentPosition': 0x03}
# scratch written differently by the C64 print routines
IGNORE = set()


def bcd(rng, hi=99):
    v = rng.randrange(hi + 1)
    return (v // 10) * 16 + v % 10


def setzp(c64, z, name, v):
    state.put(c64, z, state.find(f'zp{ZP[name]:02x}'), [v])


def setv(c64, z, name, values):
    state.put(c64, z, state.find(name), values)


def plausible(c64, z, rng):
    state.randomise(c64, z, rng, ENTRIES)
    # a vector number within the track's vectors (the extra tracks generate
    # vectors at it: the C64 would overwrite its track code beyond them)
    vn = z.mem[z.sym('ZP') + 2] % z.mem[z.sym('trackVectorCount')]
    setv(c64, z, 'zp02', [vn])                                      # thisVectorNumber
    order = list(range(20))
    rng.shuffle(order)
    setv(c64, z, 'driversInOrder', order)
    setzp(c64, z, 'currentPlayer', rng.choice([19, 19, rng.randrange(20)]))
    setzp(c64, z, 'raceStarted', rng.choice([0, 0x80, 0x28]))
    setzp(c64, z, 'raceStarting', rng.choice([0, 0x80, 0x28]))
    setzp(c64, z, 'numberOfLaps', rng.choice([5, 1, 10]))
    setzp(c64, z, 'pastHalfway', rng.choice([0, 1, 2]))
    setzp(c64, z, 'positionChangeBCD', rng.choice([0, 1, 0x99, 2]))
    setzp(c64, z, 'currentPositionBCD', bcd(rng, 20))
    setzp(c64, z, 'timerAdjust', rng.randrange(4))
    state.put(c64, z, state.find('zp4a'), [rng.randrange(20)])      # setSpeedForDriver
    setv(c64, z, 'driverGridRow', [rng.randrange(10) for _ in range(20)])
    setv(c64, z, 'raceClass', [rng.randrange(3)])
    setv(c64, z, 'driverLapNumber', [rng.choice([0, 1, 4, 5, 6, 0x80]) for _ in range(20)])
    for name, top in (('bestLapTenths', 99), ('bestLapSeconds', 59), ('bestLapMinutes', 3),
                      ('totalRaceTenths', 99), ('totalRaceSeconds', 59)):
        setv(c64, z, name, [bcd(rng, top) for _ in range(24)])
    setv(c64, z, 'bestLapSeconds', [bcd(rng, 59) for _ in range(20)] + [rng.choice([0x59, bcd(rng, 59)]), 0x59, 0, 0])
    setv(c64, z, 'bestLapTenths', [bcd(rng, 99) for _ in range(20)] + [rng.choice([0x99, 0x90, bcd(rng, 99)]), 0x88, 0, 0])
    setv(c64, z, 'bestLapMinutes', [bcd(rng, 3) for _ in range(20)] + [rng.choice([0x79, bcd(rng, 9)]), 1, 0, 0])
    setv(c64, z, 'totalRaceMinutes', [rng.choice([0x80, bcd(rng, 9)]) for _ in range(20)])
    setv(c64, z, 'qualifyingTime', [rng.choice([0x80, 4, 1, 0])])
    c64.mem[0x5a19] = z.mem[z.sym('trackTimerAdjust')]


# C64 text output routines -> RTS (PrintSpaces returns A = 0, Z set)
PRINT_STUBS = [0x0b47, 0x1045, 0x0e75, 0x37d0, 0x4dcb, 0x4dc7, 0xb30e, 0x4f05, 0x4f16, 0x4f18, 0x6ad8, 0x42d0]


def stub_printing(c64):
    for a in PRINT_STUBS:
        c64.mem[a] = 0x60
    c64.mem[0x297e:0x2981] = [0xA6, 0x45, 0x60]     # DrawCarOrSign: LDX driverPrinted; RTS
    c64.mem[0x3d50:0x3d53] = [0xA9, 0x00, 0x60]
    c64.mem[0x3d60] = 0x60          # DrawFence: only playerMoving = 0 (LDA #0, STA $90)


def run(name, n=200, seed=11, prep=None, args=None, ignore=()):
    rng = random.Random(seed)
    c64, z = tp.C64R(), tp.Z80()
    stub_printing(c64)
    fails = 0
    for i in range(n):
        plausible(c64, z, rng)
        if prep:
            prep(c64, z, rng)
        rnd = [rng.randrange(256) for _ in range(1500)]
        c64.rand = list(rnd)
        tp.patch_z80_random(z, rnd + [0] * 500)     # the C64 reads 0 when exhausted
        kw = args(rng) if args else {}
        x, y, a, carry = kw.get('x', 0), kw.get('y', 0), kw.get('a', 0), kw.get('carry', 0)
        c64.call(C64[name], a=a, x=x, y=y, carry=carry, limit=50_000_000)
        zk = {'a': a, 'c': x, 'b': y, 'carry': carry}
        if 'ix' in kw:
            zk['ix'] = kw['ix']
        z.call(name, limit=2_000_000_000, **zk)
        errs = state.diff(c64, z, ENTRIES, ignore=IGNORE | set(ignore))
        if kw.get('ret_carry') and c64.cpu.p & 1 != z.carry:
            errs.append(f'carry: C64 {c64.cpu.p & 1} Z80 {z.carry}')
        if kw.get('ret_a') and (c64.cpu.p & 1) == 0 and c64.cpu.a != z.reg[0]:
            errs.append(f'A: C64 {c64.cpu.a} Z80 {z.reg[0]}')
        if errs:
            fails += 1
            if fails <= 3:
                print(f'{name} case {i} {kw}\n  ' + '\n  '.join(errs[:12]))
    print(f'{name}: {fails}/{n}')
    return fails


def near_segments(c64, z, rng):
    tl = z.mem[z.sym('trackLength')] + 256 * z.mem[z.sym('trackLength') + 1]
    lo = [0] * 24
    hi = [0] * 24
    base = rng.randrange(tl)
    for i in range(24):
        v = (base + rng.choice([rng.randrange(-200, 200), rng.randrange(tl)])) % tl
        lo[i], hi[i] = v & 255, v >> 8
    setv(c64, z, 'objectSegmentLo', lo)
    setv(c64, z, 'objectSegmentHi', hi)


def valid_objects(c64, z, rng):
    near_segments(c64, z, rng)
    count = z.mem[z.sym('trackSectionCount')] // 8
    setv(c64, z, 'objTrackSection', [8 * rng.randrange(count) for _ in range(24)])
    setv(c64, z, 'objSectionSegmt', [rng.randrange(30) for _ in range(24)])
    setv(c64, z, 'carSpeedHi', [rng.choice([rng.randrange(256), rng.randrange(60, 140)]) for _ in range(20)])
    setv(c64, z, 'carStatus', [rng.choice([0, 0x40, 0x80, 0x10, 0x01, rng.randrange(256)]) for _ in range(20)])
    setv(c64, z, 'objectStatus', [rng.choice([0, 0x40, 0x80, rng.randrange(256)]) for _ in range(24)])
    setzp(c64, z, 'currentPosition', [i for i in range(20)
                                      if c64.mem[0x013c + i] == c64.mem[0x6f]][0]
          if c64.mem[0x6f] < 20 else 0)


def close_cars(c64, z, rng):
    valid_objects(c64, z, rng)
    tl = z.mem[z.sym('trackLength')] + 256 * z.mem[z.sym('trackLength') + 1]
    base = rng.randrange(tl)
    lo, hi = [], []
    for i in range(24):
        v = (base + rng.randrange(-12, 12)) % tl
        lo.append(v & 255)
        hi.append(v >> 8)
    setv(c64, z, 'objectSegmentLo', lo)
    setv(c64, z, 'objectSegmentHi', hi)


# scratch bytes that the C64 projection and vector routines use, but the Z80
# versions keep elsewhere (own temporaries, vecX/Y/Z)
PROJ_SCRATCH = {f'zp{a:02x}' for a in list(range(0x70, 0x78)) + list(range(0x80, 0x90))}


def view_cars(c64, z, rng):
    close_cars(c64, z, rng)
    setzp(c64, z, 'frontSegmentIndex', 3 * rng.randrange(40))
    state.put(c64, z, state.find('zp25'), [rng.choice([0, 0, 0x80])])         # directionFacing
    setzp(c64, z, 'qualifyingTime', 0) if False else setv(c64, z, 'qualifyingTime', [rng.choice([0, 4, 4, 0x80])])
    setzp(c64, z, 'positionBehind', rng.randrange(20))
    setzp(c64, z, 'positionAhead', rng.randrange(20))
    state.put(c64, z, state.find('zp1d'), [rng.randrange(20)])                 # thisPosition


def near_view(c64, z, rng):
    view_cars(c64, z, rng)
    tops = [rng.randrange(256), rng.randrange(8), rng.randrange(256)]
    for ax, name in enumerate(('x', 'y', 'z')):
        setv(c64, z, f'{name}PlayerCoordTop', [tops[ax]])
    hi = [(tops[i % 3] + rng.choice([-1, 0, 0, 0, 1])) & 255 for i in range(256)]
    setv(c64, z, 'segHi', hi)
    setzp(c64, z, 'positionAhead', c64.mem[0x1d])     # thisPosition
    state.put(c64, z, state.find('zp22'), [3 * rng.randrange(40)])               # playerSegmentIndex


def contact(c64, z, rng):
    near_view(c64, z, rng)
    state.put(c64, z, state.find('zp68'), [rng.choice([0, 0xFF, 0xFE])])        # processContact
    state.put(c64, z, state.find('zp41'), [rng.randrange(0x30)])                # objectDistanceLo
    state.put(c64, z, state.find('zp67'), [rng.randrange(24)])                  # collisionDriver


def finishing(c64, z, rng):
    """A consistent grid (ResetVariables on both machines), cars about to
    finish the race or qualifying nearly over."""
    plausible(c64, z, rng)
    setzp(c64, z, 'currentPlayer', 19)
    setzp(c64, z, 'raceStarted', rng.choice([0, 0x80]))
    count = z.mem[z.sym('trackSectionCount')] // 8
    setv(c64, z, 'driverSpeed', [rng.randrange(140, 170) for _ in range(20)])
    c64.rand = [rng.randrange(256) for _ in range(64)]
    tp.patch_z80_random(z, list(c64.rand))
    c64.call(0xb317, limit=50_000_000)
    z.call('ResetVariables', limit=2_000_000_000)
    setzp(c64, z, 'numberOfLaps', 0)
    setv(c64, z, 'driverLapNumber', [rng.choice([1, 1, 1, 0]) for _ in range(20)])
    setv(c64, z, 'objectStatus', [rng.choice([0, 0x40]) for _ in range(24)])
    setv(c64, z, 'carSpeedHi', [150] * 20)
    state.put(c64, z, state.find('physHi'), [0] * 15 + [rng.choice([9, 10, 11])])
    c64.mem[0x87f4] = 0                                                         # configStop


if __name__ == '__main__':
    total = 0
    if len(sys.argv) > 1:
        only = sys.argv[1]
        prep = {'BuildRoadSign': near_view, 'ProcessContact': contact, 'CheckForCrash': near_view,
                'FinishRace': finishing, 'BuildPlayerCar': near_view, 'MoveCars': valid_objects, 'ProcessOvertaking': close_cars, 'BuildVisibleCar': view_cars,
                'MoveAndDrawCars': view_cars, 'near': near_view}.get(only)
        if only == 'near':
            only = 'BuildVisibleCar'
        args = {'BuildVisibleCar': lambda r: {'x': r.randrange(20)}}.get(only)

        n = 10 if only == 'FinishRace' else 300
        sys.exit(1 if run(only, n=n, prep=prep, args=args, ignore=PROJ_SCRATCH) else 0)
    total += run('MoveCars', n=300, prep=valid_objects)
    total += run('ProcessOvertaking', n=300, prep=close_cars)
    total += run('CompareSegments', n=500, prep=near_segments,
                 args=lambda r: {'x': r.randrange(24), 'y': r.randrange(24), 'carry': r.choice([1, 1, 0]),
                                 'ret_carry': True, 'ret_a': True})
    total += run('SwapDriverPosition', args=lambda r: {'x': r.randrange(20), 'y': r.randrange(20)})
    total += run('AddTimeToTimer', n=500, args=lambda r: {'x': r.choice([0, 1]), 'ret_carry': True})
    total += run('ProcessTime', n=500)
    total += run('UpdatePositionInfo')

    def lap_args(r):
        x = r.choice([19, r.randrange(24)])
        return {'x': x, 'ix': 0xCF00 + 128 + x}
    total += run('UpdateLaps', n=500, args=lap_args)
    total += run('UpdateLapTimers', n=500)
    # GetTrackSegment keeps its vectors in vecX/Y/Z, not in T,U,V,W / SS,TT,UU
    # (zp1b, zp45: the extra tracks' C64 track code keeps Y and X there)
    vec_scratch = {'zp74', 'zp75', 'zp76', 'zp77', 'zp83', 'zp84', 'zp85', 'zp1b', 'zp45'}
    total += run('ResetVariables', n=30, ignore=vec_scratch)

    def start_line(c64, z, rng):
        sl = [z.mem[z.sym('trackStartLine')], z.mem[z.sym('trackStartLine') + 1]]
        setv(c64, z, 'objectSegmentLo', [sl[0]] * 24)
        setv(c64, z, 'objectSegmentHi', [sl[1]] * 24)
        setv(c64, z, 'objTrackSection', [0] * 24)
        setv(c64, z, 'objSectionSegmt', [0] * 24)
    total += run('PlaceCarsOnTrack', n=30, prep=start_line, args=lambda r: {'a': r.choice([1, 2, 3])},
                 ignore=vec_scratch)
    sys.exit(1 if total else 0)
