"""The wing settings entered in THE PITS (rear, then front, 0-40) reach the
driving model: the whole game runs in the emulator from the main menu, and
in every session (practice, after Caps Shift + 1, qualifying, the race with
its new wings) the driving loop has the entered values as the C64
rearWingSetting / frontWingSetting ($84FE / $84FD, as its GetWingSettings
stores them) and their scaled forms wingSetting / wingBalance as the C64
ScaleWingSettings ($0B5F) computes them."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from harness import C64, ROOT, z80_symbols  # noqa: E402
from zx import Machine  # noqa: E402

S = z80_symbols()
FRAME = 69888


def until(m, name, frames=3000):
    assert m.run_until(S[name], frames * FRAME), f'{name} not reached (pc ${m.reg[24]:04x})'


def keys(m, *seq):
    for k in seq:
        m.run_frames(6, tuple(k.split('+')))
        m.run_frames(25)


def wings(m, rear, front):
    """THE PITS: rear, front, SPACE (each number when its input waits for
    keys)."""
    until(m, 'UiNumberInput.i3')
    keys(m, *str(rear), 'ENTER')
    until(m, 'UiNumberInput.i3')
    keys(m, *str(front), 'ENTER', 'SPACE')


def check(m, rear, front, session):
    until(m, 'MainDrivingLoop.main5')
    c64 = C64()
    c64.mem[0x84fd], c64.mem[0x84fe] = front, rear
    c64.call(0x0b5f)                                    # ScaleWingSettings
    want = (rear, front, c64.mem[0x66e8], c64.mem[0x66e9], c64.mem[0x6731])
    have = tuple(m.mem[S[n]] for n in ('rearWingSetting', 'frontWingSetting')) + \
        (m.mem[S['wingSetting']], m.mem[S['wingSetting'] + 1], m.mem[S['wingBalance']])
    assert have == want, f'{session}: rear, front, wingSetting, wingBalance {have}, C64 {want}'
    print(f'{session}: rear {rear}, front {front}, wingSetting {have[2]} {have[3]}, '
          f'wingBalance {have[4]} OK', flush=True)


def main():
    m = Machine(ROOT / 'build/revs.sna')
    m.run_frames(20)
    keys(m, '1')                                        # practice
    wings(m, 40, 0)
    keys(m, '5')                                        # Silverstone (in memory)
    check(m, 40, 0, 'practice')
    keys(m, 'CAPS+1')                                   # the pits
    wings(m, 25, 12)
    check(m, 25, 12, 'practice after the pits')
    keys(m, 'CAPS+3')
    until(m, 'UiMainMenu.m1')
    keys(m, '2', '1', '1', 'X', 'Y', 'ENTER')            # competition, Novice, 5 minutes
    wings(m, 7, 33)
    keys(m, '5')
    check(m, 7, 33, 'qualifying')
    keys(m, 'CAPS+2')                                   # end qualifying: grid
    until(m, 'UiTable', 20000)
    for loop, key in (('UiSpace.s1', 'SPACE'),           # GRID POSITIONS
                      ('UiThreeOptions.w1', '1'),        # 5 laps
                      ('UiSpace.s1', 'SPACE')):
        until(m, loop)
        keys(m, key)
    wings(m, 0, 40)
    check(m, 0, 40, 'race')
    assert m.mem[S['raceStarted']] & 0x80
    print('wings: menu settings reach the driving model OK')


if __name__ == '__main__':
    main()
