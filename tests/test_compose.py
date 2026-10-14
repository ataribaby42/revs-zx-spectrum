"""Compose against a Python model: random edge tables, verge colours and
horizon line -> expected view buffer (80 rows x 32 bytes).

Row r shows track line 79 - r. Lines above the horizon are sky. The bottom
HIDDEN_LINES rows (behind the opaque cockpit) are not composed, nor are
the top rows that are still sky from the last frame (skyClean, if they are
sky in this one too). A line
without a verge colour (EDGE_COLL or EDGE_COLR = $FF) is all grass. Other
lines are grass | left verge | road | right verge | grass with the
boundaries b0 = min(LOUT, LIN), b1 = LIN, b2 = max(LIN, RIN),
b3 = max(b2, ROUT); patterns depend on the track line parity. A boundary
of 255 is an edge clamped at the right border (the span ends off the screen).
The average time per case must stay within the budget.
"""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Z80  # noqa: E402

SKY = 0x00
GRASS = (0x88, 0x22)
ROAD = (0xFF, 0xFF)
VERGE = [(0xAA, 0x55), (0xFF, 0xFF), (0x00, 0x00), (0x00, 0x00)]
BUDGET = 47_500                         # average T-states per case (no contention)


def model(lout, lin, rin, rout, coll, colr, horizon):
    buf = [0] * 2560
    for line in range(80):
        row = 79 - line
        p = line & 1
        if line > horizon:
            px = [SKY] * 32
            buf[row * 32:row * 32 + 32] = px
            continue
        if coll[line] == 0xFF or colr[line] == 0xFF:
            buf[row * 32:row * 32 + 32] = [GRASS[p]] * 32
            continue
        b1 = lin[line]
        b0 = min(lout[line], b1)
        b2 = max(b1, rin[line])
        b3 = max(b2, rout[line])
        pats = [GRASS[p], VERGE[coll[line]][p], ROAD[p], VERGE[colr[line]][p], GRASS[p]]
        bounds = [b if b < 255 else 256 for b in (b0, b1, b2, b3)] + [256]   # 255: off the screen
        for c in range(32):
            v = 0
            for bit in range(8):
                x = c * 8 + bit
                span = 0
                while x >= bounds[span]:
                    span += 1
                if pats[span] & (0x80 >> bit):
                    v |= 0x80 >> bit
            buf[row * 32 + c] = v
    return buf


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    rng = random.Random(9)
    z = Z80()
    e1, e2, vb = z.sym('EDGE_PAGE1'), z.sym('EDGE_PAGE2'), z.sym('VIEW_BUF')
    fails = 0
    total = 0
    for i in range(n):
        def edge():
            base = rng.randrange(256)
            return [max(0, min(255, base + rng.randrange(-40, 40) + k * rng.randrange(-3, 4)))
                    for k in range(80)]
        lout, lin, rin, rout = edge(), edge(), edge(), edge()
        if rng.random() < 0.5:                  # realistic ordering
            lout = [min(a, b) for a, b in zip(lout, lin)]
            rin = [max(a, b) for a, b in zip(lin, rin)]
            rout = [max(a, b) for a, b in zip(rin, rout)]
        coll = [rng.choice([0, 1, 2, 3, 0xFF]) if rng.random() < 0.2 else rng.choice([0, 2]) for _ in range(80)]
        colr = [rng.choice([0, 1, 2, 3, 0xFF]) if rng.random() < 0.2 else rng.choice([0, 2]) for _ in range(80)]
        horizon = rng.choice([79, 60, 45, 10, 0, rng.randrange(80)])
        for k in range(80):
            z.mem[e1 + k] = lout[k]
            z.mem[e1 + 0x50 + k] = lin[k]
            z.mem[e1 + 0xA0 + k] = rin[k]
            z.mem[e2 + k] = rout[k]
            z.mem[e2 + 0x50 + k] = coll[k]
            z.mem[e2 + 0xA0 + k] = colr[k]
        z.set('horizonLine', horizon)
        clean = rng.choice([0, 0, 80, rng.randrange(80)])
        z.set('skyClean', clean)
        for k in range(2560):
            z.mem[vb + k] = 0x5A
        t = z.call('Compose')
        total += t
        shown = 32 * (80 - z.sym('HIDDEN_LINES'))     # rows behind the cockpit are skipped
        got = [z.mem[vb + k] for k in range(shown)]
        exp = model(lout, lin, rin, rout, coll, colr, horizon)[:shown]
        sky = 79 - horizon if horizon < 80 else 0
        kept = 32 * min(clean, sky, 80 - z.sym('HIDDEN_LINES'))
        exp[:kept] = [0x5A] * kept                    # clean sky: not written
        if got != exp:
            fails += 1
            if fails <= 3:
                d = [k for k in range(shown) if got[k] != exp[k]]
                r, c = divmod(d[0], 32)
                line = 79 - r
                print(f'case {i}: {len(d)} bytes differ, row {r} (line {line}) col {c}: Z80 {got[d[0]]:08b} '
                      f'model {exp[d[0]]:08b}; edges {lout[line]} {lin[line]} {rin[line]} {rout[line]} '
                      f'cols {coll[line]} {colr[line]} horizon {horizon} skyClean {clean}')
        if i < 3:
            print(f'case {i}: {t} T')
    avg = total / n
    print(f'compose: {fails}/{n}, average {avg:.0f} T (budget {BUDGET})')
    return fails + (avg > BUDGET)


if __name__ == '__main__':
    sys.exit(1 if main() else 0)
