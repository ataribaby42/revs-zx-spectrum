"""BuildEdges regression test: random track scenes are rendered and the edge
tables compared with golden data saved from a reference build, with a
tolerance on the x positions (the step division may round differently).
Independently of the golden data, every line from HIDDEN_LINES (the lines
below are behind the cockpit) up to the highest line with road must have road (verge colours set on both sides): the track
in front of the car is never missing.

Usage:
  python tests/test_raster.py golden [n]    save golden data (reference build)
  python tests/test_raster.py [n] [tol]     compare (default tolerance 1 pixel)
"""
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Z80  # noqa: E402
import zx_scene  # noqa: E402

GOLDEN = Path(__file__).resolve().parent / 'raster_golden.json'
HIDDEN = Z80().sym('HIDDEN_LINES')


def scenes(n):
    rng = random.Random(3)
    for i in range(n):
        sec = rng.randrange(24)
        args = (sec, rng.randrange(0, 30), rng.choice([0, 0, 0x80]),
                rng.random(), rng.uniform(-0.3, 1.3), rng.randrange(-2500, 2500),
                rng.choice([172, 172, 400, 120]), rng.choice([0, 0, 3, -3]))
        yield i, args


def render(args):
    z = Z80()
    sec, adv, d, frac, lat, yaw, height, pitch = args
    zx_scene.setup(z, sec, adv, d)
    zx_scene.place(z, frac, lat, yaw, height, pitch)
    z.call('GetTrackAndMarkers')
    t = z.call('BuildEdges')
    e1, e2 = z.sym('EDGE_PAGE1'), z.sym('EDGE_PAGE2')
    hidden = z.sym('HIDDEN_LINES')                  # lines behind the cockpit: not rasterised
    xs = [z.mem[e1 + k] if k % 0x50 >= hidden else 0 for k in range(0xF0)] +          [z.mem[e2 + k] if k >= hidden else 0 for k in range(0x50)]
    cols = [z.mem[e2 + 0x50 + k] if k % 0x50 >= hidden else 0xFF for k in range(0xA0)]
    return xs, cols, t


def missing_road(cols):
    """Lines below the highest line with road that have no road."""
    road = [cols[k] != 0xFF and cols[0x50 + k] != 0xFF for k in range(80)]
    if not any(road):
        return []
    top = max(k for k in range(80) if road[k])
    return [k for k in range(HIDDEN, top) if not road[k]]


def main():
    if len(sys.argv) > 1 and sys.argv[1] == 'golden':
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 80
        data = []
        total = 0
        for i, args in scenes(n):
            xs, cols, t = render(args)
            total += t
            data.append({'xs': xs, 'cols': cols})
        GOLDEN.write_text(json.dumps(data))
        print(f'saved {n} scenes, average {total / n:.0f} T')
        return 0
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 80
    tol = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    gold = json.loads(GOLDEN.read_text())
    fails = 0
    exact = 0
    total = 0
    worst = 0
    for i, args in scenes(min(n, len(gold))):
        xs, cols, t = render(args)
        total += t
        g = gold[i]
        gaps = missing_road(cols)
        if gaps:
            fails += 1
            print(f'scene {i}: no road on lines {gaps[:10]}')
            continue
        dx = max(abs(a - b) for a, b in zip(xs, g['xs']))
        worst = max(worst, dx)
        if dx == 0 and cols == g['cols']:
            exact += 1
        if dx > tol or cols != g['cols']:
            fails += 1
            if fails <= 3:
                d = [k for k in range(len(xs)) if abs(xs[k] - g['xs'][k]) > tol]
                dc = [k for k in range(len(cols)) if cols[k] != g['cols'][k]]
                print(f'scene {i}: x off by up to {dx} at {d[:6]}, colour diffs {dc[:6]}')
    m = min(n, len(gold))
    print(f'raster: {fails}/{m} failures, {exact} exact, worst {worst} px, average {total / m:.0f} T')
    return fails


if __name__ == '__main__':
    sys.exit(1 if main() else 0)
