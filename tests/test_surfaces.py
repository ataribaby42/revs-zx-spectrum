"""The grass under the front tyres (CheckSurfaces) is what the view shows
there: the original reads its own screen (C64: two bytes of track line 10),
so leftSurface / rightSurface must say grass exactly when Compose drew grass
over the whole span (SURF_LEFT / SURF_RIGHT) of line 10. Compose runs with
the grass patterns set to $FF and the road and verge patterns to 0, so the
bits of the line are its grass pixels. Random scenes on all six tracks, the
car on and off the track, turned up to sideways, both directions."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import zx_scene  # noqa: E402
from c64_image import TRACKS, main_image  # noqa: E402
from harness import Z80, track_code  # noqa: E402

EXTRA = ['Brands Hatch', 'Donington Park', 'Nurburgring', 'Oulton Park', 'Snetterton']
LINE = 10


def machine(track):
    z = Z80()
    t = z.sym('TRACK')
    z.mem[t:t + 0x800] = main_image(track)[0x5300:0x5B00]
    if track in EXTRA:
        code = track_code(track)
        z.mem[z.sym('TRACKCODE'):z.sym('TRACKCODE') + len(code)] = code
        z.call('TcLoaded')
    return z


def span(e):
    return e >> 8, e & 255


def run(track, seed, frames=25):
    rng = random.Random(seed * 7 + TRACKS.index(track))
    z = machine(track)
    cp = z.sym('cpPatterns')
    road = z.sym('Compose.road')                    # LD C,PAT_ROAD
    spans = {'leftSurface': span(z.sym('SURF_LEFT')), 'rightSurface': span(z.sym('SURF_RIGHT'))}
    zx_scene.setup(z, rng.randrange(z.mem[z.sym('TRACK') + 0x6FA] // 8), rng.randrange(20),
                   rng.choice([0, 0, 0x80]))
    for f in range(frames):
        zx_scene.place(z, rng.random(), rng.uniform(-2.0, 3.0), rng.randrange(-20000, 20000))
        z.call('GetTrackAndMarkers')
        z.call('BuildEdges')
        z.mem[cp:cp + 10] = [0] * 8 + [0xFF, 0xFF]            # verge, grass
        z.mem[road + 1] = 0                                     # road
        z.set('skyClean', 0)
        z.call('Compose')
        z.call('CheckSurfaces')
        row = z.sym('VIEW_BUF') + 32 * (79 - LINE)
        for name, (lo, hi) in spans.items():
            drawn = all(z.mem[row + x // 8] >> (7 - x % 8) & 1 for x in range(lo, hi + 1))
            found = z.get(name)[0] == 0xFF
            edges = [z.mem[z.sym(k) + LINE] for k in ('EDGE_LOUT', 'EDGE_LIN', 'EDGE_RIN', 'EDGE_ROUT',
                                                       'EDGE_COLL', 'EDGE_COLR')]
            assert drawn == found, (f'{track} seed {seed} frame {f}: {name} {z.get(name)[0]:02x}, '
                                    f'drawn grass {drawn} (line {LINE} edges, colours {edges})')
        if rng.random() < 0.6:
            z.call('GetTrackSegment')


if __name__ == '__main__':
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    for track in TRACKS:
        for seed in range(n):
            run(track, seed)
    print(f'surfaces: {len(TRACKS) * n * 25} scenes OK')
