"""The UI overlay round trip: InitDrivingScreen stores the overlay away
(StoreUI) and every way back from driving (the end of a session, Caps
Shift + 1/2/3) goes through StopDriving, which must bring it back (it falls
through into LoadUI) byte for byte, whatever driving left in the view
buffer and edge pages."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Z80  # noqa: E402


def check(seed):
    rng = random.Random(seed)
    z = Z80()
    lo, hi = z.sym('UI_RUN'), z.sym('UI_LIMIT')
    ui = bytes(rng.randrange(256) for _ in range(hi - lo))
    z.mem[lo:hi] = ui
    z.call('StoreUI')
    z.mem[lo:hi] = bytes(rng.randrange(256) for _ in range(hi - lo))     # driving
    z.set('viewReady', [0])
    z.call('StopDriving')
    bad = [a for a in range(lo, hi) if z.mem[a] != ui[a - lo]]
    assert not bad, 'StopDriving: overlay not back at ' + ' '.join(f'${a:04X}' for a in bad[:8])


if __name__ == '__main__':
    for seed in range(3):
        check(seed)
    print('uiswap: StopDriving restores the UI overlay OK')
