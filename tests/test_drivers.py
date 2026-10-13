"""Compare the driver routines (InitialiseDrivers, SetDriverSpeed,
GetSectionSteering, SetPlayerPositions, SortDrivers) with the C64 code."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_physics as tp  # noqa: E402

# name: (C64 address, Z80 symbol, length)
REGIONS = {
    'driversInOrder': (0x013c, 'DRIVERS_IN_ORDER', 20), 'driverGridRow': (0x86a0, 'DRIVER_GRIDROW', 20),
    'driverSpeed': (0x0128, 'DRIVER_SPEED', 20), 'positionNumber': (0x0100, 'POSITION_NUMBER', 20),
    'totalPointsLo': (0x3864, 'TOTAL_POINTS_LO', 20), 'totalPointsHi': (0x39e4, 'TOTAL_POINTS_HI', 20),
    'totalPointsTop': (0x86f0, 'TOTAL_POINTS_TOP', 20),
    'bestLapTenths': (0x88a0, 'BEST_LAP_TENTHS', 24), 'bestLapSeconds': (0x88b8, 'BEST_LAP_SECONDS', 24),
    'bestLapMinutes': (0x88d0, 'BEST_LAP_MINUTES', 24),
    'totalRaceTenths': (0x0898, 'TOTAL_RACE_TENTHS', 20), 'totalRaceSeconds': (0x08ac, 'TOTAL_RACE_SECONDS', 20),
    'totalRaceMinutes': (0x86dc, 'TOTAL_RACE_MINUTES', 20), 'driversInOrder2': (0x86c8, 'DRIVERS_IN_ORDER2', 20),
    'sectionSteering': (0x8520, 'sectionSteering', 26), 'baseSpeed': (0x8500, 'baseSpeed', 1),
    'raceClass': (0x84fa, 'raceClass', 1), 'setSpeedForDriver': (0x4a, 'setSpeedForDriver', 1),
    'currentPlayer': (0x6f, 'currentPlayer', 1), 'currentPosition': (0x03, 'currentPosition', 1),
    'positionAhead': (0x4d, 'positionAhead', 1), 'positionBehind': (0x5b, 'positionBehind', 1),
    'T': (0x74, 'T', 1), 'U': (0x75, 'U', 1), 'V': (0x76, 'V', 1), 'W': (0x77, 'W', 1),
    'G': (0x78, 'G', 1), 'H': (0x79, 'Hv', 1),
}

C64 = {'InitialiseDrivers': 0x4da4, 'SetDriverSpeed': 0x678f, 'GetSectionSteering': 0x4516,
       'SetPlayerPositions': 0x67d4, 'SortDrivers': 0x0f0e}


def bcd(rng, hi=99):
    v = rng.randrange(hi + 1)
    return (v // 10) * 16 + v % 10


def put(c64, z, name, values):
    ca, zs, n = REGIONS[name]
    for i, v in enumerate(values[:n]):
        c64.mem[ca + i] = v
        z.mem[z.sym(zs) + i] = v


def randomise(c64, z, rng):
    for name, (ca, zs, n) in REGIONS.items():
        put(c64, z, name, [rng.randrange(256) for _ in range(n)])
    order = list(range(20))
    rng.shuffle(order)
    put(c64, z, 'driversInOrder', order)
    put(c64, z, 'driverGridRow', [rng.randrange(10) for _ in range(20)])
    put(c64, z, 'raceClass', [rng.randrange(3)])
    put(c64, z, 'setSpeedForDriver', [rng.randrange(20)])
    put(c64, z, 'currentPlayer', [rng.choice([19, rng.randrange(20), 25])])
    few = rng.random() < 0.5             # many ties
    for name in ('totalPointsLo', 'totalPointsHi', 'totalPointsTop', 'bestLapTenths', 'bestLapSeconds',
                 'bestLapMinutes', 'totalRaceTenths', 'totalRaceSeconds', 'totalRaceMinutes'):
        top = 2 if few else 99
        vals = [bcd(rng, top) for _ in range(24)]
        if name == 'totalRaceMinutes':
            vals = [v | rng.choice([0, 0, 0x80, 0xC0]) for v in vals]   # $C0: ClearTotalRaceTime
        put(c64, z, name, vals)
    # random track base speeds and steering
    for i in range(3):
        v = rng.randrange(256)
        c64.mem[0x5a14 + i] = v
        z.mem[z.sym('trackBaseSpeed') + i] = v
    for i in range(26):
        v = rng.randrange(256)
        c64.mem[0x59d0 + i] = v
        z.mem[z.sym('trackSteering') + i] = v


def compare(c64, z, label):
    errs = []
    for name, (ca, zs, n) in REGIONS.items():
        a = list(c64.mem[ca:ca + n])
        b = [z.mem[z.sym(zs) + i] for i in range(n)]
        if a != b:
            errs.append(f'{name}: C64 {a} Z80 {b}')
    if errs:
        raise AssertionError(label + '\n  ' + '\n  '.join(errs))


def run(name, n=300, seed=5, args=None):
    rng = random.Random(seed)
    c64, z = tp.C64R(), tp.Z80()
    # Silverstone section count (sections * 8)
    sc = z.mem[z.sym('trackSectionCount')]
    c64.mem[0x59fa] = sc
    fails = 0
    for i in range(n):
        randomise(c64, z, rng)
        rnd = [rng.randrange(256) for _ in range(64)]
        c64.rand = list(rnd)
        tp.patch_z80_random(z, rnd)
        a = args(rng) if args else 0
        c64.call(C64[name], a=a, x=a)
        z.call(name, a=a, c=a)
        try:
            compare(c64, z, f'{name} case {i} a={a}')
        except AssertionError as e:
            fails += 1
            if fails <= 3:
                print(e)
    print(f'{name}: {fails}/{n}')
    return fails


if __name__ == '__main__':
    total = 0
    total += run('SetDriverSpeed')
    total += run('GetSectionSteering', args=lambda r: r.randrange(3))
    total += run('InitialiseDrivers', n=50)
    total += run('SetPlayerPositions')
    total += run('SortDrivers', args=lambda r: r.choice([0, 0x80, 0x40, 0xC0]))
    sys.exit(1 if total else 0)
