"""Compare the Z80 object renderer (DrawObject) with a Python model of the
same geometry: BBC scaffold scaling, parts with edges and fills, clipping,
dither patterns per track line parity. The average time of DrawObject must
stay within the budget.

Usage: python tests/test_objdraw.py [cases]
"""
import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Z80  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = [(0xFF, 0xFF), (0xAA, 0x55), (0x00, 0x00), (0x88, 0x22)]   # [colour][line parity]
LOD_CAR = 14
BUDGET = 8_700                          # average T-states of DrawObject (no contention)


def load_tables():
    text = (ROOT / 'src/objdata.asm').read_text()
    tables = {}
    name = None
    for line in text.split('\n'):
        m = re.match(r'(\w+):', line)
        if m:
            name = m.group(1)
            tables[name] = []
            continue
        m = re.match(r'\s+db (.*)', line)
        if m and name:
            for v in m.group(1).split(','):
                v = v.strip()
                tables[name].append(int(v[1:], 16) if v.startswith('$') else int(v))
    return tables


T = load_tables()


def scale(obj_type, scale_up):
    down = 0
    su = scale_up
    if su < 64:
        su *= 4
        down = 2
    rng = [su >> n for n in range(6)]
    first, last = T['scafIndexTab'][obj_type], T['scafIndexTab'][obj_type + 1]
    v, h = [0] * 16, [0] * 8
    for i, code in enumerate(T['scaffoldTab'][first:last]):
        if code & 0x80:
            a = rng[(code & 7) - 2] + rng[((code >> 3) & 7) - 2]
            if code & 0x40:
                a += rng[1]
            a &= 255
        else:
            a = rng[code - 2]
        if down:
            a2 = a >> 2
            a = a2 + ((a >> 1) & 1)
        if a >= 128:
            return None
        v[i], v[i + 8] = a, -a
        h[i] = T['h13Tab'][a]
    return v, h


def draw_model(buf, obj_type, x, y, scale_up, lowest, palette, facing_back=False):
    if scale_up == 0:
        return
    kind = obj_type
    if kind == 4 and scale_up < LOD_CAR:
        kind = 5
    elif kind >= 10:
        kind = 9
    while True:
        sc = scale(kind, scale_up)
        if sc is None:
            return
        parts(buf, kind, x, y, sc, lowest, palette)
        if kind != 9 or facing_back or obj_type < 10:
            return
        kind = obj_type


def parts(buf, kind, xc, y, sc, lowest, palette):
    v, h = sc

    def hx(idx):
        return xc + h[idx & 7] * (-1 if idx & 8 else 1)

    def vy(idx):
        return (y + (v[idx] & 255)) & 255

    left_half = xc < 128
    mm = T['objIndexTab'][kind]
    while True:
        col = T['objColourTab'][mm]
        top = vy(T['objTopTab'][mm])
        bottom = vy(T['objBottomTab'][mm])
        visible = True
        if top >= 128:
            visible = False
        top = min(top, 79)
        if bottom >= 128 or bottom < lowest:
            bottom = lowest
        if bottom >= top:
            visible = False
        xl, xr = hx(T['objLeftTab'][mm]), hx(T['objRightTab'][mm]) + 1
        if xl > 255 or xr < 0:
            visible = False
        if not visible:
            if col & 0x80:
                if col & 0x40:
                    return
                mm += 1
                col = T['objColourTab'][mm]
            if col & 0x40:
                return
            mm += 1
            continue
        line = {}

        def run(x0, x1, c):
            for px in range(max(x0, 0), min(x1, 255) + 1):
                line[px] = palette[c]

        def edge_col(c, side):
            if c & 0x10 and ((side == 'L' and left_half) or (side == 'R' and not left_half)):
                return c & 3
            return (c >> 2) & 3

        if col & 0x80:
            mm += 1
            x2 = hx(T['objLeftTab'][mm])
            x3 = hx(T['objTopTab'][mm])
            c2 = T['objRightTab'][mm]
            c3 = T['objColourTab'][mm]
            run(xl, x2 - 1, col & 3)
            run(x2, x3 - 1, c2 & 3)
            run(x3, xr, c3 & 3)
            run(xl, xl + 1, (col >> 2) & 3)
            run(x2, x2 + 1, (c2 >> 2) & 3)
            run(x3, x3 + 1, (c3 >> 2) & 3)
            run(xr - 1, xr, (c3 >> 2) & 3)
            col = c3
        else:
            fill = col & 3
            run(xl, xr, fill)
            e = edge_col(col, 'L')
            if e != fill:
                run(xl, xl + 1, e)
            e = edge_col(col, 'R')
            if e != fill:
                run(xr - 1, xr, e)
        lo, hi = max(xl, 0), min(xr, 255)
        for tl in range(bottom + 1, top + 1):
            row = 79 - tl
            for px in range(lo, hi + 1):
                pat = PATTERNS[line[px]][tl & 1]
                bit = 0x80 >> (px & 7)
                a = row * 32 + (px >> 3)
                buf[a] = (buf[a] & ~bit) | (pat & bit)
        if col & 0x40:
            return
        mm += 1


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    rng = random.Random(7)
    z = Z80()
    vb = z.sym('VIEW_BUF')
    fails = 0
    total = 0
    for i in range(n):
        buf = [rng.randrange(256) for _ in range(2560)]
        for k in range(2560):
            z.mem[vb + k] = buf[k]
        t = rng.randrange(13)
        x = rng.randrange(-120, 380)
        y = rng.randrange(0, 100)
        su = rng.choice([rng.randrange(1, 20), rng.randrange(256)])
        lowest = rng.choice([0, 0, rng.randrange(80)])
        back = rng.random() < 0.2
        pal = [rng.randrange(4) for _ in range(4)]
        z.set('objX', [x & 255, (x >> 8) & 255])
        z.set('yPixelCoord', y)
        z.set('scaleUp', su)
        z.set('objectType', t)
        z.set('directionFacing', 0x80 if back else 0)
        z.set('colourPalette', pal)
        width = 0 if lowest == 0 else 255
        z.set('horizonTrackWidth', width)
        z.set('horizonLine', lowest)
        total += z.call('DrawObject', c=23)
        draw_model(buf, t, x, y, su, lowest if su < width else 0, pal, back)   # clipped beyond the horizon
        got = [z.mem[vb + k] for k in range(2560)]
        if got != buf:
            fails += 1
            if fails <= 3:
                diff = [k for k in range(2560) if got[k] != buf[k]]
                print(f'case {i}: type {t} x {x} y {y} size {su} lowest {lowest}: {len(diff)} bytes differ, '
                      f'first row {diff[0] // 32} col {diff[0] % 32}: Z80 {got[diff[0]]:08b} model {buf[diff[0]]:08b}')
    avg = total / n
    print(f'objdraw: {fails}/{n}, average {avg:.0f} T (budget {BUDGET})')
    return fails + (avg > BUDGET)


if __name__ == '__main__':
    sys.exit(1 if main() else 0)
