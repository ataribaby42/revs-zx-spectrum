"""Compare race set-up, lap and timer routines with the C64 code, using the
whole mapped game state (tests/state.py). The computer drivers' routines
(MoveCars, ProcessOvertaking) must also stay within their time budgets
(average T-states over the cases, no contention).

A car pushed off the track (PushCarOffTrack) is an approved deviation that
the C64 reference has too (tools/c64_image.py): while it brakes to a stop
its racing line moves to the nearer verge (a slow car rolls on to it
before braking further), where it stands for the rest of the race and is
drawn as before (pushed_off: both machines iteration by iteration; a car
pushed off just behind a standing one gets past it and stops at a verge
too, two_retired). Its retirement is the original's: FinishRace does not
wait for it and it has no race time, so it comes after every car with a
time (retired_results). With every computer driver pushed off, nothing waits for
them or loops (all_retired)."""
import functools
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import state  # noqa: E402
import test_physics as tp  # noqa: E402
from c64_image import TRACKS, main_image  # noqa: E402
from harness import track_code  # noqa: E402

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
BUDGETS = {'MoveCars': 10_850, 'ProcessOvertaking': 16_250}   # (MoveCars: stopped and retired cars are frequent here)
TRACK = 'Silverstone'                   # the track of machines()


@functools.lru_cache(maxsize=None)
def track_image(track):
    return bytes(main_image(track))


def machines():
    """Both machines with TRACK: the C64 image of the track (its data and the
    extra tracks' patches) and on the Spectrum its data and, for the extra
    tracks, its code (TcLoaded), as tests/test_surfaces.py."""
    c64, z = tp.C64R(), tp.Z80()
    if TRACK != 'Silverstone':
        img = track_image(TRACK)
        keep = {a: c64.mem[a] for a in list(range(0x0E50, 0x0E55)) +       # ScanKeyboard, KERNAL stubs
                [0xFFC2, 0xFFE0, 0xFFE3, 0xFFE7, 0xFFEE, 0xFFF1, 0xFFF4, 0xFFF7]}
        c64.mem[:] = list(img)
        for a, v in keep.items():
            c64.mem[a] = v
        t = z.sym('TRACK')
        z.mem[t:t + 0x800] = img[0x5300:0x5B00]
        code = track_code(TRACK)
        z.mem[z.sym('TRACKCODE'):z.sym('TRACKCODE') + len(code)] = code
        z.call('TcLoaded')
    return c64, z


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


def run(name, n=200, seed=11, prep=None, args=None, ignore=(), budget=True):
    rng = random.Random(seed)
    c64, z = tp.C64R(), tp.Z80()
    stub_printing(c64)
    fails = 0
    total_t = 0
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
        total_t += z.call(name, limit=2_000_000_000, **zk)
        errs = state.diff(c64, z, ENTRIES, ignore=IGNORE | set(ignore))
        if kw.get('ret_carry') and c64.cpu.p & 1 != z.carry:
            errs.append(f'carry: C64 {c64.cpu.p & 1} Z80 {z.carry}')
        if kw.get('ret_a') and (c64.cpu.p & 1) == 0 and c64.cpu.a != z.reg[0]:
            errs.append(f'A: C64 {c64.cpu.a} Z80 {z.reg[0]}')
        if errs:
            fails += 1
            if fails <= 3:
                print(f'{name} case {i} {kw}\n  ' + '\n  '.join(errs[:12]))
    if name in BUDGETS and budget:
        avg = total_t / n
        print(f'{name}: {fails}/{n}, average {avg:.0f} T (budget {BUDGETS[name]})')
        return fails + (avg > BUDGETS[name])
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
TRACK_XY = {'zp1b', 'zp45'}             # the extra tracks' C64 track code keeps Y and X there


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


def retired_cars(c64, z, rng):
    """Cars pushed off the track ($91) among the others, at any speed and
    racing line, in a race."""
    valid_objects(c64, z, rng)
    status = list(c64.mem[0x0100:0x0114])
    for k in rng.sample(range(20), 6):
        status[k] = 0x91
    setv(c64, z, 'carStatus', status)
    setzp(c64, z, 'raceStarting', 0)


def pushed_off(seed):
    """A car pushed off the track at racing speed or slowly (a slow car rolls
    on to the verge before it stops), from any racing line or the middle of
    the track, the player 100 segments away (even seeds) or 10: MoveCars on
    both machines, the whole state compared after every iteration. The
    racing line must move steadily to the nearer verge and the car stop
    there; with the player close behind it, BuildVisibleCar shows it exactly
    when it would show a racing car there. Returns the problems found."""
    rng = random.Random(seed)
    c64, z = machines()
    stub_printing(c64)
    plausible(c64, z, rng)
    valid_objects(c64, z, rng)
    setzp(c64, z, 'raceStarted', 0x80)
    setzp(c64, z, 'raceStarting', 0)
    setv(c64, z, 'carStatus', [0] * 20)
    player = c64.mem[0x6f]
    car = rng.choice([k for k in range(20) if k != player])
    line = [rng.randrange(256), 128, 127][seed % 3]
    tl = z.mem[z.sym('trackLength')] + 256 * z.mem[z.sym('trackLength') + 1]
    lo, hi = list(c64.mem[0x08d0:0x08e8]), list(c64.mem[0x08e8:0x0900])
    seg = lo[car] | hi[car] << 8

    def put_seg(k, v):
        v %= tl
        lo[k], hi[k] = v & 255, v >> 8
        setv(c64, z, 'objectSegmentLo', lo)
        setv(c64, z, 'objectSegmentHi', hi)
    put_seg(player, seg + (100 if seed % 2 == 0 else 10))
    speeds = list(c64.mem[0x0150:0x0164])
    speeds[car] = [180, 10, 120, 31, 60, 1, 90, 33, 45, 200][seed % 10]
    setv(c64, z, 'carSpeedHi', speeds)
    lines = list(c64.mem[0x0178:0x018c])
    lines[car] = line
    setv(c64, z, 'carRacingLine', lines)
    rnd = [rng.randrange(256) for _ in range(1500)]
    c64.rand = list(rnd)
    tp.patch_z80_random(z, rnd + [0] * 500)
    problems = []
    c64.call(0x10ed, x=car)                                 # PushCarOffTrack
    z.call('PushCarOffTrack', c=car)
    trace = [line]
    for i in range(80):
        c64.call(C64['MoveCars'], limit=50_000_000)
        z.call('MoveCars', limit=2_000_000_000)
        errs = state.diff(c64, z, ENTRIES, ignore=IGNORE)
        if errs:
            return [f'iteration {i}: ' + '; '.join(errs[:4])]
        trace.append(c64.mem[0x0178 + car])
    verge = 0 if line < 128 else 255
    steps = [b - a for a, b in zip(trace, trace[1:])]
    if any(d * (1 if verge else -1) < 0 for d in steps) or trace[-1] != verge:
        problems.append(f'racing line {trace[:6]} ... {trace[-1]}, verge {verge}')
    if c64.mem[0x0150 + car] != 0:
        problems.append(f'speed {c64.mem[0x0150 + car]} after 80 iterations')
    if c64.mem[0x0100 + car] != 0x91:
        problems.append(f'status ${c64.mem[0x0100 + car]:02X}')
    seg = c64.mem[0x08d0 + car] | c64.mem[0x08e8 + car] << 8
    put_seg(player, seg - 5)                                # close behind it
    put_seg(23, seg - 5)
    state.put(c64, z, state.find('zp25'), [0])              # directionFacing
    pos = list(c64.mem[0x013c:0x0150]).index(car)
    # the player's coordinates do not match his segment here: the working
    # values of the car's vector (vectorNumber, prevBlockNumber, xCoord2 and
    # yCoord2 after the segment list at $09FD) may differ, the results not
    view = [(n, ca, zs, off, 253 if n == 'segLo' else cnt) for n, ca, zs, off, cnt in ENTRIES]
    shown = []
    for status, objst in ((0x91, 0xC0), (0, 0x80)):         # retired, then racing
        setv(c64, z, 'carStatus', [status if k == car else 0 for k in range(20)])
        setv(c64, z, 'objectStatus', [objst if k == car else v for k, v in enumerate(c64.mem[0x018c:0x01a4])])
        c64.call(C64['BuildVisibleCar'], x=pos, limit=50_000_000)
        z.call('BuildVisibleCar', c=pos, limit=2_000_000_000)
        errs = state.diff(c64, z, view, ignore=IGNORE | PROJ_SCRATCH | {'zp0c', 'zp7c'})
        if errs:
            problems.append('BuildVisibleCar: ' + '; '.join(errs[:4]))
        shown.append(not c64.mem[0x018c + car] & 0x80)
    if shown[0] != shown[1]:
        problems.append(f'shown {shown[0]}, a racing car there {shown[1]}')
    return problems


def two_retired(seed):
    """Two cars pushed off the track close together: A stands at a verge, B
    is 1-4 segments behind it in the race order, on the same side, at any
    speed. ProcessOvertaking steers B away from A to get past it; MoveCars
    and ProcessOvertaking alternate on both machines (the state compared).
    In the end A still stands at its verge and B stands at a verge too.
    Returns the problems found."""
    rng = random.Random(300 + seed)
    c64, z = machines()
    stub_printing(c64)
    plausible(c64, z, rng)
    valid_objects(c64, z, rng)
    setzp(c64, z, 'raceStarted', 0x80)
    setzp(c64, z, 'raceStarting', 0)
    player = c64.mem[0x6f]
    order = list(c64.mem[0x013c:0x0150])
    pa = rng.choice([p for p in range(19) if player not in order[p:p + 2]])
    a, b = order[pa], order[pa + 1]
    tl = z.mem[z.sym('trackLength')] + 256 * z.mem[z.sym('trackLength') + 1]
    lo, hi = list(c64.mem[0x08d0:0x08e8]), list(c64.mem[0x08e8:0x0900])
    seg = lo[a] | hi[a] << 8
    for k, v in ((b, seg - rng.randrange(1, 5)), (player, seg + 120)):    # (the player far away)
        v %= tl
        lo[k], hi[k] = v & 255, v >> 8
    setv(c64, z, 'objectSegmentLo', lo)
    setv(c64, z, 'objectSegmentHi', hi)
    verge = rng.choice([0, 255])
    lines = list(c64.mem[0x0178:0x018c])
    lines[a] = verge
    lines[b] = rng.choice([verge ^ 0x40, verge ^ 0x10, 128 if verge else 127])
    setv(c64, z, 'carRacingLine', lines)
    speeds = list(c64.mem[0x0150:0x0164])
    speeds[a] = 0
    speeds[b] = [60, 31, 20, 100, 45, 10][seed % 6]
    setv(c64, z, 'carSpeedHi', speeds)
    setv(c64, z, 'carStatus', [0x91 if k in (a, b) else 0 for k in range(20)])
    setv(c64, z, 'carSteering', [0] * 20)                   # (ProcessOvertaking clears it)
    setv(c64, z, 'objectStatus', [0x40 if k in (a, b) else v & 0x3F for k, v in enumerate(c64.mem[0x018c:0x01a4])])
    rnd = [rng.randrange(256) for _ in range(1500)]
    c64.rand = list(rnd)
    tp.patch_z80_random(z, rnd + [0] * 500)
    for i in range(150):
        for name, addr in (('MoveCars', C64['MoveCars']), ('ProcessOvertaking', 0x23f6)):
            c64.call(addr, limit=50_000_000)
            z.call(name, limit=200_000_000)
            errs = state.diff(c64, z, ENTRIES, ignore=IGNORE)
            if errs:
                return [f'iteration {i}, {name}: ' + '; '.join(errs[:4])]
    sa, la, sb, lb = (c64.mem[0x0150 + a], c64.mem[0x0178 + a], c64.mem[0x0150 + b], c64.mem[0x0178 + b])
    if sa or la != verge or sb or lb not in (0, 255):
        return [f'A speed {sa} line {la} (verge {verge}), B speed {sb} line {lb}']
    return []


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


def retired_results(seed):
    """The end of a race with two cars pushed off the track that never reach
    the line: FinishRace must not wait for them, and sorted by race time
    (SortDrivers) they come after every car with a time and have none
    themselves. Both machines, compared. Returns the problems found."""
    rng = random.Random(100 + seed)
    c64, z = machines()
    stub_printing(c64)
    finishing(c64, z, rng)
    setzp(c64, z, 'raceStarted', 0x80)
    out = rng.sample(range(19), 2)
    status = list(c64.mem[0x0100:0x0114])
    minutes = list(c64.mem[0x86dc:0x86f0])
    objst = list(c64.mem[0x018c:0x01a4])
    speeds = list(c64.mem[0x0150:0x0164])
    laps = [1] * 20                                         # the others have finished
    for k in out:
        status[k], minutes[k], objst[k], speeds[k], laps[k] = 0x91, 0xC0, 0xC0, 0, 0
    for name, v in (('carStatus', status), ('totalRaceMinutes', minutes), ('objectStatus', objst),
                    ('carSpeedHi', speeds), ('driverLapNumber', laps)):
        setv(c64, z, name, v)
    c64.call(C64['FinishRace'], limit=50_000_000)
    z.call('FinishRace', limit=2_000_000_000)
    scratch = IGNORE | PROJ_SCRATCH | TRACK_XY              # (as the FinishRace test)
    problems = ['FinishRace: ' + '; '.join(e[:4]) for e in [state.diff(c64, z, ENTRIES, ignore=scratch)] if e]
    c64.call(0x0f0e, a=0x80, limit=50_000_000)              # SortDrivers by race time
    z.call('SortDrivers', a=0x80, limit=2_000_000_000)
    problems += ['SortDrivers: ' + '; '.join(e[:4]) for e in [state.diff(c64, z, ENTRIES, ignore=scratch)] if e]
    order = list(c64.mem[0x013c:0x0150])
    timed = [d for d in range(20) if c64.mem[0x86dc + d] < 0x80]
    for k in out:
        if c64.mem[0x86dc + k] != 0xC0 or any(order.index(k) < order.index(d) for d in timed):
            problems.append(f'car {k}: race minutes ${c64.mem[0x86dc + k]:02X}, position {order.index(k) + 1}')
    return problems


def all_retired(seed):
    """Every computer driver pushed off the track during a race, close to
    the player (even seeds) or anywhere on the track (odd seeds): 60
    iterations of MoveCars, ProcessOvertaking, HideAllCars, BuildVisibleCar
    (each position) and SetPlayerPositions on both machines, the state
    compared after each (every call must return); every car that was moving
    stands at a verge, even close to others (ProcessOvertaking's steer must
    not move it off). Then FinishRace (it must not wait for them) and
    SortDrivers by race time: every computer driver without a time. Returns
    the problems found."""
    rng = random.Random(200 + seed)
    c64, z = machines()
    stub_printing(c64)
    plausible(c64, z, rng)
    view_cars(c64, z, rng)
    if seed % 2:
        near_segments(c64, z, rng)                          # spread round the track
    setzp(c64, z, 'raceStarted', 0x80)
    setzp(c64, z, 'raceStarting', 0)
    setzp(c64, z, 'numberOfLaps', 5)
    setv(c64, z, 'driverLapNumber', [rng.randrange(1, 5) for _ in range(20)])
    setv(c64, z, 'carStatus', [rng.choice([0, 0x40, 0x80]) for _ in range(20)])
    rnd = [rng.randrange(256) for _ in range(1500)]
    c64.rand = list(rnd)
    tp.patch_z80_random(z, rnd + [0] * 500)
    player = c64.mem[0x6f]
    scratch = IGNORE | PROJ_SCRATCH
    moved = [k for k in range(20) if k != player and c64.mem[0x0150 + k]]
    for k in range(20):
        if k != player:
            c64.call(0x10ed, x=k)                           # PushCarOffTrack
            z.call('PushCarOffTrack', c=k)
    calls = [('MoveCars', 0x25d3, {}), ('ProcessOvertaking', 0x23f6, {}), ('HideAllCars', None, {})]
    calls += [('BuildVisibleCar', 0x278f, {'x': p}) for p in range(20)]
    calls += [('SetPlayerPositions', 0x67d4, {})]
    for i in range(60):
        for name, addr, kw in calls:
            if addr is None:
                c64.mem[0x018c:0x01a3] = [v | 0x80 for v in c64.mem[0x018c:0x01a3]]   # (HideAllCars)
            else:
                c64.call(addr, limit=50_000_000, **kw)
            z.call(name, limit=200_000_000, **({'c': kw['x']} if kw else {}))
            errs = state.diff(c64, z, ENTRIES, ignore=scratch)
            if errs:
                return [f'iteration {i}, {name}: ' + '; '.join(errs[:4])]
    moving = [k for k in range(20) if k != player and c64.mem[0x0150 + k]]
    if moving:
        return [f'computer drivers still moving: {moving}']
    off = [(k, c64.mem[0x0178 + k]) for k in moved if c64.mem[0x0178 + k] not in (0, 255)]
    if off:                                                 # (one pushed standing stays on its line)
        return [f'standing off the verge (car, racing line): {off}']
    setv(c64, z, 'driverLapNumber', [6] * 20)                # the race is over for the player
    c64.call(C64['FinishRace'], limit=50_000_000)
    z.call('FinishRace', limit=200_000_000)
    c64.call(0x0f0e, a=0x80, limit=50_000_000)              # SortDrivers by race time
    z.call('SortDrivers', a=0x80, limit=200_000_000)
    problems = ['FinishRace, SortDrivers: ' + '; '.join(e[:4]) for e in [state.diff(c64, z, ENTRIES, ignore=scratch)] if e]
    timed = [k for k in range(20) if k != player and c64.mem[0x86dc + k] < 0x80]
    if timed:
        problems.append(f'computer drivers with a race time: {timed}')
    return problems


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
    total += run('MoveCars', n=300, prep=retired_cars, budget=False)     # (many retired cars)
    scenarios = [('pushed off the track', pushed_off, 10), ('two cars pushed off close together', two_retired, 12),
                 ('race results with cars pushed off', retired_results, 6),
                 ('every computer driver pushed off', all_retired, 8)]
    for TRACK in TRACKS:                                    # (machines() reads it)
        for label, scenario, n in scenarios:
            n = n if TRACK == 'Silverstone' else (n + 1) // 2
            found = [f'seed {seed}: ' + '; '.join(f) for seed in range(n) for f in [scenario(seed)] if f]
            print(f'{label}, {TRACK}: ' + ('; '.join(found) if found else f'{n} cases OK'))
            total += len(found)
    TRACK = 'Silverstone'
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
