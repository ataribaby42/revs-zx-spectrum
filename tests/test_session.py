"""The length of qualifying and the number of laps chosen in the menus reach
the game: the whole game runs in the emulator from the main menu; for each
option the driving loop has the C64's qualifyingTime ($04, $09, $19: 5, 10,
20 minutes, BCD minutes the clock passes; C64 timeFromOption $3DF0) and
numberOfLaps (5, 10, 20; lapsFromOption $3DF4).

Usage: python tests/test_session.py [qualifying option] [laps option]
(1-3 each; without arguments the pairs 1/3, 2/1, 3/2)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import test_wings as tw  # noqa: E402
from c64_image import main_image  # noqa: E402
from harness import ROOT  # noqa: E402
from zx import Machine  # noqa: E402

S = tw.S
C64 = main_image()
TIMES = list(C64[0x3DF0:0x3DF3])               # qualifyingTime per option
LAPS = list(C64[0x3DF4:0x3DF7])                # numberOfLaps per option


def run(q, laps):
    m = Machine(ROOT / 'build/revs.sna')
    m.run_frames(20)
    tw.keys(m, '2', '1', str(q), 'X', 'ENTER')  # competition, Novice, qualifying option
    tw.wings(m, 20, 20)
    tw.keys(m, '5')                             # Silverstone
    tw.until(m, 'MainDrivingLoop.main5')
    have = m.mem[S['qualifyingTime']]
    assert have == TIMES[q - 1], f'qualifying option {q}: qualifyingTime ${have:02X}, C64 ${TIMES[q - 1]:02X}'
    tw.keys(m, 'CAPS+2')                        # end qualifying
    tw.until(m, 'UiTable', 20000)
    for loop, key in (('UiSpace.s1', 'SPACE'), ('UiThreeOptions.w1', str(laps)), ('UiSpace.s1', 'SPACE')):
        tw.until(m, loop)
        tw.keys(m, key)
    tw.wings(m, 20, 20)
    tw.until(m, 'MainDrivingLoop.main5')
    have = m.mem[S['numberOfLaps']]
    assert have == LAPS[laps - 1], f'laps option {laps}: numberOfLaps {have}, C64 {LAPS[laps - 1]}'
    assert m.mem[S['raceStarted']] & 0x80
    print(f'session: qualifying option {q} -> ${TIMES[q - 1]:02X}, laps option {laps} -> {LAPS[laps - 1]} OK',
          flush=True)


if __name__ == '__main__':
    pairs = [tuple(int(a) for a in sys.argv[1:3])] if len(sys.argv) > 2 else [(1, 3), (2, 1), (3, 2)]
    for q, laps in pairs:
        run(q, laps)
