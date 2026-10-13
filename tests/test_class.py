"""The race class after qualifying (UiAdjustClass) against the C64 MainLoop
game6-game10 ($68AE-$6901 without its texts): when the player qualified
last, the class drops to the number of the track's two lap time limits
(trackLapTimeSec/Min, $5A00/$5A03; the third is 0:00) the best lap beat,
never rises; then the steering and base speed for the class
(GetSectionSteering), the grid order in driversInOrder2 and the player's
grid row. Best laps around the real limits of all six tracks."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import test_drivers as td  # noqa: E402
from c64_image import TRACKS, main_image  # noqa: E402
from harness import C64, Z80  # noqa: E402

LIMITS = {t: bytes(main_image(t)[0x5a00:0x5a06]) for t in TRACKS}
CHECK = ('raceClass', 'baseSpeed', 'sectionSteering', 'driversInOrder2', 'driverGridRow')


def from_bcd(b):
    return (b >> 4) * 10 + (b & 15)


def to_bcd(v):
    return (v // 10) << 4 | v % 10


def c64_run(c64, start, stop, limit=500_000):
    cpu = c64.cpu
    cpu.pc, cpu.sp = start, 0xFD
    for _ in range(limit):
        if cpu.pc == stop:
            return
        cpu.step()
    raise AssertionError(f'C64 ${start:04x} did not reach ${stop:04x} (pc ${cpu.pc:04x})')


def trial(c64, z, rng, track):
    td.randomise(c64, z, rng)
    limits = LIMITS[track]
    c64.mem[0x5a00:0x5a06] = list(limits)
    z.mem[z.sym('trackLapTimeSec'):z.sym('trackLapTimeSec') + 6] = limits
    order = list(range(20))
    rng.shuffle(order)
    if rng.random() < 0.7:                              # the player qualified last
        order.remove(19)
        order.append(19)
    td.put(c64, z, 'driversInOrder', order)
    td.put(c64, z, 'positionNumber', sorted(rng.randrange(20) for _ in range(20)))
    cls = rng.randrange(3)
    td.put(c64, z, 'raceClass', [cls])
    c64.mem[0x84f9] = 19                                # lowestPlayerNumber
    kind = rng.random()
    if kind < 0.1:
        sec, mins = 0, 0x10                             # no lap: 10:00
    else:
        i = rng.randrange(2)
        t = from_bcd(limits[3 + i]) * 60 + from_bcd(limits[i]) + rng.randrange(-3, 4)
        if kind > 0.9:
            t = rng.randrange(40, 200)
        sec, mins = to_bcd(t % 60), to_bcd(t // 60)
    for name, v in (('bestLapSeconds', sec), ('bestLapMinutes', mins), ('bestLapTenths', to_bcd(rng.randrange(10)))):
        ca, zs, _ = td.REGIONS[name]
        c64.mem[ca + 19] = v
        z.mem[z.sym(zs) + 19] = v
    c64_run(c64, 0x68ae, 0x68d8)                        # game6-game8: to the texts
    c64_run(c64, 0x68ea, 0x6902)                        # game10-game11
    z.call('UiAdjustClass')
    for name in CHECK:
        ca, zs, n = td.REGIONS[name]
        have, want = list(z.mem[z.sym(zs):z.sym(zs) + n]), list(c64.mem[ca:ca + n])
        assert have == want, f'{track} class {cls} best {mins:x}:{sec:02x} last {order[19]}: {name} {have} C64 {want}'
    assert z.mem[z.sym('uiClass')] == z.mem[z.sym('raceClass')]
    return cls, z.mem[z.sym('raceClass')]


def main(n=300, seed=1):
    rng = random.Random(seed)
    c64, z = C64(), Z80()
    drops = 0
    for i in range(n):
        before, after = trial(c64, z, rng, TRACKS[i % len(TRACKS)])
        drops += after < before
    print(f'class: {n} random qualifying results OK ({drops} lowered the class)')


if __name__ == '__main__':
    main(*(int(a) for a in sys.argv[1:3]))      # [trials] [seed]
