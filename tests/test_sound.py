"""The sound while driving, in the emulator (beeper toggles per TV frame):

* silence in the menus and with the engine off; the starter pops while T
  cranks the engine;
* the engine: 1 + revs / 32 clicks per frame (two toggles each);
* a burst of noise when changing gear; squealing tyres add clicks;
* N mutes everything and brings it back; H (pause) is silent;
* leaving a session while the tyres squeal (Caps Shift + 3): the menu is
  silent (the driving sounds stop when the game stands, soundLive);
* a crash: the impact noise, then silence for the rest of the CRASHED
  pause;
* the border stays black at every write to port $FE.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import test_wings as tw  # noqa: E402
from harness import ROOT  # noqa: E402
from zx import Machine  # noqa: E402

S = tw.S
problems = []


def check(cond, text):
    print(('OK   ' if cond else 'FAIL ') + text, flush=True)
    if not cond:
        problems.append(text)


def toggles(m, n, keys=()):
    out = []
    for _ in range(n):
        before = len(m.ports.beeper)
        m.run_frames(1, keys)
        out.append(len(m.ports.beeper) - before)
    return out


def drive_off(m):
    """From the main menu: practice at Silverstone, at the start line."""
    tw.keys(m, '1')
    tw.wings(m, 20, 20)
    tw.keys(m, '5')
    tw.until(m, 'MainDrivingLoop.main5')


def start_engine(m):
    """Hold T until the engine runs: (frames, beeper toggles meanwhile)."""
    before = len(m.ports.beeper)
    for frame in range(1, 300):
        m.run_frames(1, ('T',))
        if m.mem[S['engineStatus']]:
            break
    return frame, len(m.ports.beeper) - before


def main():
    m = Machine(ROOT / 'build/revs.sna')
    border = []
    write = m.ports.write_port

    def write_port(registers, port, value, offset=0):
        if port % 2 == 0 and value & 7:
            border.append(value)
        return write(registers, port, value, offset)
    m.ports.write_port = write_port

    m.run_frames(30)
    check(sum(toggles(m, 100)) == 0, 'main menu: silent')
    drive_off(m)
    check(sum(toggles(m, 60)) == 0, 'engine off: silent')
    frames, pops = start_engine(m)
    check(m.mem[S['engineStatus']] != 0, f'T starts the engine ({frames} frames)')

    # the engine in neutral at different revs: clicks = 1 + revs / 32
    exact = total = 0
    seen = set()
    for keys in [()] * 40 + [('Q',)] * 120 + [()] * 80:
        revs = m.mem[S['revCount']]
        t = toggles(m, 1, keys)[0]
        if m.mem[S['revCount']] == revs and m.mem[S['engineStatus']] and not m.mem[S['noiseFrames']]:
            total += 1
            exact += t == 2 * (1 + revs // 32)
            seen.add(1 + revs // 32)
    check(total > 100 and exact >= 0.9 * total and len(seen) >= 3,
          f'engine: 1 + revs / 32 clicks per frame ({exact} of {total} frames, click counts {sorted(seen)})')

    # a gear change: a burst of noise
    m.run_frames(30, ('Q',))
    t = toggles(m, 10, ('Q', 'W'))
    usual = sorted(t)[len(t) // 2]
    check(max(t) >= usual + 10, f'gear change: noise burst (toggles per frame {t})')
    m.run_frames(20, ('Q',))

    # N mutes, N again brings the sound back
    m.run_frames(10, ('N',))
    m.run_frames(10)
    muted = sum(toggles(m, 40, ('Q',)))
    m.run_frames(10, ('N',))
    m.run_frames(10, ('Q',))
    back = sum(toggles(m, 40, ('Q',)))
    check(muted == 0 and back > 0, f'N: silent ({muted} toggles), N again: sound ({back} toggles)')

    # pause
    m.run_frames(10, ('H',))
    m.run_frames(10)
    paused = sum(toggles(m, 40))
    m.run_frames(10, ('H',))
    m.run_frames(10)
    check(paused == 0, f'pause: silent ({paused} toggles)')

    # squealing tyres, then Caps Shift + 3: a silent menu
    for _ in range(6):
        m.run_frames(10, ('Q', 'W'))
        m.run_frames(60, ('Q',))
    sq = S['tyreSqueal']
    squeal = []
    for _ in range(600):
        revs = m.mem[S['revCount']]
        t = toggles(m, 1, ('Q', 'O'))[0]
        if m.mem[sq] & 0x80 and not m.mem[S['noiseFrames']]:
            squeal.append(t - 2 * (1 + revs // 32))
            if len(squeal) > 10:
                break
    check(len(squeal) > 10 and max(squeal) > 0, f'squealing tyres add clicks ({squeal[:8]})')
    for _ in range(20):                         # (not while a CRASHED pause)
        m.run_frames(8, ('CAPS', '3'))
        if m.run_until(S['UiMainMenu.m1'], 30 * tw.FRAME):
            break
    m.run_frames(12)
    check(sum(toggles(m, 100)) == 0, 'menu after leaving a squeal: silent')

    # a crash: the impact noise, then silence for the CRASHED pause
    drive_off(m)
    start_engine(m)
    crashed = S['crashedIntoFence']
    for _ in range(6):
        m.run_frames(10, ('Q', 'W'))
        m.run_frames(60, ('Q',))
    for _ in range(3000):
        m.run_frames(1, ('Q', 'P'))
        if m.mem[crashed]:
            break
    check(m.mem[crashed] != 0, 'driving into the fence: a crash')
    t = toggles(m, 90)
    check(sum(t[:8]) > 0 and sum(t[16:]) == 0, f'crash: impact noise, then silence ({t[:20]} ...)')
    # after a crash the engine starts hardly (C64: 1 in 32): the starter cranks
    for _ in range(300):
        if m.mem[S['engineStatus']] == 0 and m.run_until(S['MainDrivingLoop.main5'], tw.FRAME):
            break
        m.run_frames(1)
    cranked = popped = 0
    while cranked < 160 and not m.mem[S['engineStatus']]:
        popped += toggles(m, 1, ('T',))[0] > 0
        cranked += 1
    check(cranked < 24 or cranked / 16 <= popped <= cranked / 4,
          f'the starter pops while T cranks ({popped} of {cranked} frames)')

    check(not border, f'the border stays black ({len(border)} writes with border bits)')
    print(f'sound: {len(problems)} problems')
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
