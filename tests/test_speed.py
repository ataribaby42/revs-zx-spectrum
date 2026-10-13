"""The player's speed in the HUD in mph: playerSpeed (8.8) * 1.3125 (1 + 1/4
+ 1/16; the car moves 2 units per iteration per unit of speed, Silverstone
is 124,289 units for 2.932 miles, an iteration is 0.13 s; at most 254),
right-aligned in three columns of row 1 and followed by MPH: "152MPH" at the
left in practice and qualifying, "L: 5 125MPH Behind: ..." in the race (the
laps to go in columns 2-3). UpdateDashboard prints it when it changes, never
over the qualifying time warnings or FINISHED, and not while a notice covers
the HUD; RedrawHud, InitDrivingScreen and PrintSecondLine make it (and MPH)
print again. The rest of both HUD rows stays as it was. The rows are read
back from the screen through the ROM font."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Z80  # noqa: E402

SPEEDS = [(0, 0), (0, 200), (7, 0), (7, 160), (75, 128), (100, 0), (110, 0), (191, 255), (200, 0), (0, 0)]
BUDGET = 500                            # UpdateDashboard, nothing changed (T)


def mph(hi, lo):
    """The Z80 conversion, shift by shift."""
    total = d = hi * 256 + lo
    for _ in range(2):
        d >>= 2
        total += d
        if total > 0xFFFF:
            return 254
    return min(total >> 8, 254)


class Hud:
    def __init__(self):
        self.z = z = Z80()
        self.glyphs = {tuple(z.mem[0x3C00 + 8 * c:0x3C08 + 8 * c]): chr(c) for c in range(32, 128)}
        self.fails = []

    def row(self, r):
        out = ''
        for col in range(32):
            a = 0x4000 | (r & 0x18) << 8 | (r & 7) << 5 | col
            out += self.glyphs.get(tuple(self.z.mem[a + 256 * k] for k in range(8)), '?')
        return out

    def session(self, race=False, qual_end=0, leave=0, laps=5):
        z = self.z
        z.set('raceStarted', 0x80 if race else 0)
        z.set('qualifyingTime', 4 if race or qual_end else 0x80)
        z.set('qualifyTimeEnding', qual_end)
        z.set('leaveTrackTimer', leave)
        if race:
            z.set('DRIVERS_IN_ORDER', list(range(20)))
            z.set('currentPlayer', 19)
            z.set('DRIVER_LAPNUMBER', [1] * 20)
            z.set('numberOfLaps', laps)
            z.set('currentPositionBCD', 0x20)
            z.set('positionAhead', 18)
            z.set('positionBehind', 0)
        z.call('RedrawHud')

    def speed(self, hi, lo=0):
        self.z.set('playerSpeedHi', hi)
        self.z.set('playerSpeedLo', lo)
        return self.z.call('UpdateDashboard')

    def check(self, what, got, want):
        if got != want:
            self.fails.append(f'{what}: {got!r}, expected {want!r}')


def main():
    h = Hud()
    z = h.z

    h.session()                                         # practice: columns 0-2
    top = h.row(0)
    for v in SPEEDS:
        h.speed(*v)
        h.check(f'practice {v}', (h.row(0), h.row(1)), (top, f'{mph(*v):>3}MPH' + ' ' * 26))

    for qual_end in (0x40, 0xC0):                       # time warnings
        h.session(qual_end=qual_end)
        rows = (h.row(0), h.row(1))
        h.speed(93)
        h.check(f'qualifying warning ${qual_end:02X}', (h.row(0), h.row(1)), rows)

    h.session(race=True, laps=20)                       # race, 20 laps to go
    h.speed(94)
    h.check('race, 20 laps', h.row(1)[:12], f'L:20 {mph(94, 0)}MPH ')
    h.session(race=True)                                # race: columns 5-10
    top, line = h.row(0), h.row(1)
    h.check('race row 1 before', line, 'L: 5' + ' ' * 8 + 'Behind: Max Throttle')
    for v in SPEEDS:
        h.speed(*v)
        h.check(f'race {v}', (h.row(0), h.row(1)), (top, line[:5] + f'{mph(*v):>3}MPH' + line[11:]))
    z.call('PrintSecondLine', c=44)                     # the row printed again
    h.speed(*v)
    h.check('race row 1 printed again', h.row(1)[:12], f'L:   {mph(*v):>3}MPH ')

    z.set('leaveTrackTimer', 55)                        # finished
    z.call('PrintFinished')
    finished = h.row(1)
    h.check('FINISHED', finished[:12], 'FINISHED    ')
    h.speed(58)
    h.check('race finished', h.row(1), finished)

    h.session()                                         # a notice covers the HUD
    h.speed(50)
    rows = (h.row(0), h.row(1))
    z.set('hudCovered', 1)
    h.speed(45)
    h.check('under a notice', (h.row(0), h.row(1)), rows)
    z.call('RedrawHud')
    h.speed(45)
    h.check('after the notice', h.row(1)[:6], f'{mph(45, 0):>3}MPH')

    h.session()                                         # a new session
    h.speed(0)
    z.call('InitDrivingScreen')
    h.speed(0)
    h.check('session start', h.row(1)[:6], '  0MPH')

    t = h.speed(0)                                      # nothing changed
    h.check('UpdateDashboard within the budget', t <= BUDGET, True)

    for f in h.fails:
        print(f)
    print(f'speed: {len(h.fails)} problems (UpdateDashboard unchanged: {t} T, budget {BUDGET})')
    return 1 if h.fails else 0


if __name__ == '__main__':
    sys.exit(main())
