"""Lockstep test of the whole main driving loop: the C64 MainDrivingLoop and
the Z80 MainDrivingLoop run iteration by iteration with the same key presses
and random numbers, and the mapped game state (tests/state.py) is compared
after every iteration.

The C64 routines in page 3 ($0300-$03FF) are created at run time and are not
in the tape image: ShowStartingLights is reassembled from the fragments left
in memory (same layout and constants), the others are display routines and
are stubbed. Display, sound and text routines are stubbed on both sides.

Usage: python tests/test_lockstep.py [iterations] [seed] [race|practice|qual]
       [CAS from iteration|-] [front,rear wing settings, default 20,20]
       [race class 0-2, default 0] [laps of a race / qualifyingTime|-]
       [shifty: gear changes at any speed too]
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import state  # noqa: E402
import test_physics as tp  # noqa: E402
import test_cars as tc  # noqa: E402
from skoolkit.simutils import PC  # noqa: E402

C64_MAIN5 = 0xB227
C64_MAINLOOP = 0xB202
# the return addresses of MainDrivingLoop: the session has ended (the player
# retires from an Amateur or Professional race after a crash, ...)
C64_END = 0xFFF8
Z80_END = 0x0008

# C64 key code -> Z80 (half-row, bit)
KEYS = {'O': (0x2D, 5, 1), 'P': (0x16, 5, 0), 'SPACE': (0x27, 7, 0), 'Q': (0x29, 2, 0), 'A': (0x11, 1, 0),
        'S': (0x17, 1, 1), 'W': (0x37, 2, 1), 'T': (0x32, 2, 4)}

SHOW_STARTING_LIGHTS = bytes([
    0xA5, 0x6C, 0x10, 0x3A, 0xA6, 0x6D, 0xF0, 0x36, 0x10, 0x10, 0xE0, 0x80, 0xD0, 0x0C, 0x24, 0x61,
    0x10, 0x02, 0xA2, 0xD7, 0xA0, 0x00, 0xA9, 0x95, 0xD0, 0x1D, 0xE0, 0xA0, 0xF0, 0x0D, 0xCA, 0x10,
    0x12, 0xE0, 0xB6, 0xB0, 0xEF, 0xA9, 0x88, 0xA0, 0x2A, 0xD0, 0x0C, 0xA5, 0x6A, 0x29, 0x1F, 0xD0,
    0xF4, 0xA2, 0x28, 0xA9, 0xAE, 0xA0, 0x15, 0x86, 0x6D, 0x48, 0x84, 0x74, 0x68, 0x60, 0x60])

# scratch bytes (zero page temporaries) that the C64 display code and the
# Z80 port use differently; compared state excludes them
SCRATCH = {f'zp{a:02x}' for a in [0x1b, 0x1e, 0x27, 0x29, 0x2c, 0x32, 0x33, 0x34, 0x35, 0x36, 0x42, 0x45,
                                   0x47, 0x48, 0x4b, 0x4c, 0x4f, 0x50, 0x53, 0x54]
           + list(range(0x70, 0x90))}
IGNORE = SCRATCH | {'leftSurface', 'rightSurface', 'segData', 'markerData', 'markerListIndex', 'xMarkerLo', 'xMarkerHi', 'vergeEdgeRight',
                    'objectPalette', 'soundBuffer', 'tyreSqueal', 'zp2a', 'zp2b', 'zp37', 'mirrorContents', 'lowestTrackLine',
                    'thisObjectType'}


def c64_machine():
    c64 = tp.C64R()
    tc.stub_printing(c64)
    m = c64.mem
    m[0x0300] = 0x60                    # unknown page-3 routine
    m[0x039C] = 0x60                    # PrintTimer
    m[0x03DA] = 0x60                    # DrawTrackView
    m[0x034A:0x034A + len(SHOW_STARTING_LIGHTS)] = SHOW_STARTING_LIGHTS
    m[0x0E50:0x0E57] = [0xBD, 0x00, 0x93, 0xAA, 0xE0, 0xFF, 0x60]   # ScanKeyboard: LDA $9300,X ...
    m[0x9300:0x9400] = [0] * 256
    m[0xB27B:0xB27D] = [0xEA, 0xEA]     # crash: no wait for the interrupt counter
    m[0x87F4] = 0                       # configStop
    m[0xFFF0] = 0x60                    # KERNAL PLOT (texts at the end of a session)
    m[0x3139:0x313B] = [0xFF, 0x00]     # display code: LDX $DC04 -> LDX $00FF (keep randoms in step)
    return c64


def z80_machine():
    z = tp.Z80()
    for name in ('FramePace', 'WaitView', 'ReadKeys', 'StoreUI'):   # StoreUI: keeps $5B00 for the randoms
        z.mem[z.sym(name)] = 0xC9
    w = z.sym('MainDrivingLoop.wait')
    z.mem[w] = 0x00                     # crash: no HALT
    return z


class CyclicRandom:
    """The C64's random numbers ($DC04 reads, C64R pops them): the 1024-entry
    table over and over, as the Z80's Random reads it (patch_random_wrap)."""

    def __init__(self, table):
        self.table, self.i = table, 0

    def __bool__(self):
        return True

    def pop(self, _=0):
        v = self.table[self.i % len(self.table)]
        self.i += 1
        return v


def patch_random_wrap(z, values):
    """Random -> 1024-entry table at $5C00, wrapping (stub at $5B00; the
    BASIC area is free once the game runs)."""
    assert len(values) == 1024
    for i, v in enumerate(values):
        z.mem[0x5C00 + i] = v
    # ld hl,(ptr); ld a,(hl); inc hl; push af; ld a,h; cp $60; jr nz,+2;
    # ld h,$5C; pop af; ld (ptr),hl; ret
    code = [0x2A, 0xFE, 0x5B, 0x7E, 0x23, 0xF5, 0x7C, 0xFE, 0x60, 0x20, 0x02, 0x26, 0x5C, 0xF1,
            0x22, 0xFE, 0x5B, 0xC9]
    for i, b in enumerate(code):
        z.mem[0x5B00 + i] = b
    z.mem[0x5BFE], z.mem[0x5BFF] = 0x00, 0x5C
    a = z.sym('Random')
    z.mem[a:a + 3] = [0xC3, 0x00, 0x5B]


def set_keys(c64, z, keys):
    c64.mem[0x9300:0x9400] = [0] * 256
    rows = [0] * 8
    for k in keys:
        code, r, b = KEYS[k]
        c64.mem[0x9300 + code] = 0xFF
        rows[r] |= 1 << b
    for i in range(8):
        z.mem[z.sym('keyRows') + i] = rows[i]


def c64_run_to(c64, pc, limit=20_000_000, end=None):
    cpu = c64.cpu
    for _ in range(limit):
        cpu.step()
        if cpu.pc == pc or cpu.pc == end:
            return
    raise AssertionError(f'C64 did not reach ${pc:04x} (pc ${cpu.pc:04x})')


def z80_run_to(z, pc, limit=200_000_000):
    r = z.reg
    start = r[25]
    z.sim.trace(r[PC], pc, 0, start + limit, 0, None, None, None, None, None)
    if r[PC] != pc:
        raise AssertionError(f'Z80 did not reach ${pc:04x} (pc ${r[PC]:04x})')


def setup(c64, z, rng, race, wings=(20, 20), race_class=0, length=None):
    """Game set-up as GameStart/HeadToTrack do it, on both machines (wings:
    the front and rear wing settings as entered, 0-40; race_class: 0 Novice,
    1 Amateur, 2 Professional, as MainLoop sets it with GetSectionSteering;
    length: the number of laps of a race, qualifyingTime of qualifying)."""
    tc.plausible(c64, z, rng)
    # the verge buffer as the C64 has it (its power-on RAM pattern): the
    # extra tracks' horizon width reads entries beyond the verge lists
    for page in ('VERGE_XLO', 'VERGE_XHI', 'VERGE_DATA', 'VERGE_Y'):
        z.set(page, c64.get(page, 80))
    table = [rng.randrange(256) for _ in range(1024)]
    c64.rand = CyclicRandom(table)          # both wrap round the same table
    patch_random_wrap(z, table)
    c64.call(0x4da4, x=0)                               # InitialiseDrivers
    z.call('InitialiseDrivers', a=0)
    if race_class:
        c64.mem[0x84fa] = race_class
        z.set('raceClass', race_class)
        c64.call(0x4516, x=race_class)                  # GetSectionSteering
        z.call('GetSectionSteering', c=race_class)
    practice = race == 'practice'          # BBC/C64 practice: player 0, no time limit
    race = race is True
    qual_time = 0xFF if practice else (length if length is not None and not race else 4)
    laps = length if length is not None and race else 5
    for c, zs, v in ((0x84fb, 'qualifyingTime', qual_time), (0x6f, 'ZP', 0 if practice else 19),
                     (0x6e, 'ZP', laps)):
        off = 0x6f if c == 0x6f else (0x6e if c == 0x6e else 0)
        c64.mem[c] = v
        z.mem[z.sym(zs) + off] = v
    v = 0x80 if race else 0x28
    for a in (0x6c, 0x6d):
        c64.mem[a] = v
        z.mem[z.sym('ZP') + a] = v
    for i in range(20):                                 # best laps 10:00.00
        for base, zs, val in ((0x88a0, 'BEST_LAP_TENTHS', 0), (0x88b8, 'BEST_LAP_SECONDS', 0),
                              (0x88d0, 'BEST_LAP_MINUTES', 0x10)):
            c64.mem[base + i] = val
            z.mem[z.sym(zs) + i] = val
    for name, v in zip(('frontWingSetting', 'rearWingSetting'), wings):
        state.put(c64, z, state.find(name), [v])
    for name, ca, zs in (('engineStatus', 0x61, 0x61),):
        c64.mem[ca] = 0
        z.mem[z.sym('ZP') + zs] = 0
    # enter the main loops
    cpu = c64.cpu
    cpu.pc, cpu.sp = C64_MAINLOOP, 0xFD
    c64.mem[0x1FE], c64.mem[0x1FF] = (C64_END - 1) & 255, (C64_END - 1) >> 8
    z.reg[PC] = z.sym('MainDrivingLoop')
    z.reg[12] = 0xFD50
    z.mem[0xFD50], z.mem[0xFD51] = Z80_END & 255, Z80_END >> 8
    c64_run_to(c64, C64_MAIN5)
    z80_run_to(z, z.sym('MainDrivingLoop.main5'))


class Driver:
    """Simple driving policy from the (shared) game state: start the engine,
    change up at high revs, mostly accelerate, random steering."""

    def __init__(self, rng):
        self.rng = rng
        self.hold = 0

    def keys(self, mem):
        rng = self.rng
        keys = set()
        gear, revs, engine = mem[0x40], mem[0x3c], mem[0x61]
        if self.hold:
            self.hold -= 1
            keys.add('Q')
            return keys
        if not engine:
            keys.add('T')
            if gear != 1 and rng.random() < 0.3:
                keys.add('S')
                self.hold = 1
            return keys
        if gear == 1:
            keys.add('Q')
            if revs > 100:
                keys.add('W')
            return keys
        if gear < 6 and revs > 140 and rng.random() < 0.3:
            keys.add('W')
            keys.add('Q')
            return keys
        if rng.random() < 0.85:
            keys.add('Q')
        elif rng.random() < 0.5:
            keys.add('A')
        r = rng.random()
        if r < 0.12:
            keys.add('O')
        elif r < 0.24:
            keys.add('P')
        return keys


def run(n=300, seed=1, race=False, cas_from=None, wings=(20, 20), race_class=0, length=None, shifty=False):
    rng = random.Random(seed)
    c64, z = c64_machine(), z80_machine()
    setup(c64, z, rng, race, wings, race_class, length)
    entries = state.all_entries()
    err = state.diff(c64, z, entries, ignore=IGNORE)
    if err:
        print('after set-up:\n  ' + '\n  '.join(err[:20]))
        return 1
    driver = Driver(rng)
    if shifty:                              # also gear changes at any speed
        plain = driver.keys
        driver.keys = lambda mem: plain(mem) | ({rng.choice('SW')} if rng.random() < 0.15 else set())
    for i in range(n):
        if i == cas_from:                   # C64 Revs+ CAS on ($9C43) on both
            c64.mem[0x9c43] = 0x80
            z.mem[z.sym('casOn')] = 0x80
        keys = driver.keys(c64.mem)
        set_keys(c64, z, keys)
        # the C64 reads the surfaces from its screen bitmap (not drawn here):
        # use its values on both machines
        z.mem[z.sym('leftSurface')] = c64.mem[0x757d]
        z.mem[z.sym('rightSurface')] = c64.mem[0x7645]
        c64_run_to(c64, C64_MAIN5, end=C64_END)
        ended = c64.cpu.pc == C64_END
        z80_run_to(z, Z80_END if ended else z.sym('MainDrivingLoop.main5'))
        if ended:                           # the C64 main loop ends with FinishRace,
            z.call('FinishRace', limit=4_000_000_000)   # ours leaves it to UiFinish
        err = state.diff(c64, z, entries, ignore=IGNORE)
        if err:
            print(f'iteration {i} keys {sorted(keys)}:\n  ' + '\n  '.join(err[:25]))
            return 1
        if ended:
            print(f'lockstep: the session ended on both machines after {i + 1} iterations '
                  f'(player totalRaceMinutes {c64.mem[0x86dc + 19]:02x}), state OK')
            return 0
        if i % 50 == 49:
            spd = c64.mem[0x63]
            mm = c64.mem
            print(f'{i + 1} iterations OK (speed {spd}, segment {mm[0x22]}, laps {mm[0x86b4 + 19]}, '
                  f'gear {mm[0x40]}, revs {mm[0x3c]}, engine {mm[0x61]:02x}, tb {mm[0x3e]:02x}/{mm[0x3f]:02x}, '
                  f'clutch {mm[0x59]}, height {mm[0x2d]}, raceStarting {mm[0x6d]:02x})', flush=True)
    print(f'lockstep: {n} iterations OK')
    return 0


if __name__ == '__main__':
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    race = len(sys.argv) > 3 and sys.argv[3] == 'race' or (len(sys.argv) > 3 and sys.argv[3] == 'practice' and 'practice')
    cas_from = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] != '-' else None  # CAS on from here
    wings = tuple(int(v) for v in sys.argv[5].split(',')) if len(sys.argv) > 5 else (20, 20)  # front,rear
    race_class = int(sys.argv[6]) if len(sys.argv) > 6 else 0
    length = int(sys.argv[7]) if len(sys.argv) > 7 and sys.argv[7] != '-' else None
    shifty = len(sys.argv) > 8 and sys.argv[8] == 'shifty'
    sys.exit(run(n, seed, race, cas_from, wings, race_class, length, shifty))
