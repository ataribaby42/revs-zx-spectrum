"""Cockpit data and the generated view-copy routine.

Input: assets/cockpit/cockpit0.png (the user's repainted cockpit, 256x77,
placed at screen row 115; palette 0 = white, 1 = black, 2 = transparent).
cockpit1.png is the second tyre-animation phase.

Outputs (written by tools/gen_src.py, not by the build):
  src/gfx/cockpit.bin      77 rows x 32 bytes of cockpit bitmap (ink = black)
  src/mirrors.asm, src/wheel.asm: wing mirror glass masks, steering wheel
                           marks and the CAS indicator
  src/viewcopy.asm         ViewCopy: copies the view buffer (rows VIEW_TOP..
                           VIEW_TOP+79) to the screen, merging with the cockpit
                           where the two overlap. Bytes hidden by the cockpit
                           are skipped.
"""
from pathlib import Path

import sys

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import srcdata  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
COCKPIT_TOP = 115
# Screen row of view row 0 (track line 79). The horizon then sits about as
# far above the cowl (row 119) as on the C64 (17 lines above its cowl); the
# bottom view rows (152 and below) are hidden by the opaque cockpit.
VIEW_TOP = 82
VIEW_ROWS = 80


def screen_addr(y, cx=0):
    return 0x4000 | ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | cx


def load_cockpit(name='cockpit0.png'):
    img = Image.open(ROOT / 'assets/cockpit' / name).convert('RGBA')
    w, h = img.size
    px = img.load()
    bits = []          # per row: list of 32 (ink byte, opaque mask byte)
    for y in range(h):
        row = []
        for cx in range(32):
            ink = mask = 0
            for b in range(8):
                r, g, bl, a = px[cx * 8 + b, y]
                if a >= 128:
                    mask |= 0x80 >> b
                    if r < 128:
                        ink |= 0x80 >> b
            row.append((ink, mask))
        bits.append(row)
    return bits


# Wing mirror glass: the white areas at the screen edges below the mirror
# housings, rows MIRROR_TOP..MIRROR_TOP + MIRROR_ROWS - 1, up to the black
# edge of the glass (at most MIRROR_IN pixels in from the screen edge). Each
# mirror has three segments (BBC order: left outer, middle, inner, right
# inner, middle, outer); the car is centred on row MIRROR_MID.
MIRROR_TOP = 148
MIRROR_ROWS = 21
MIRROR_MID = 158
MIRROR_IN = 22
MIRROR_SEGMENTS = [(0, 6), (7, 13), (14, 21), (234, 241), (242, 248), (249, 255)]


def mirror_glass(px, y):
    """Glass pixel x range on the left and right of screen row y."""
    def white(x):
        r, g, b, a = px[x, y - COCKPIT_TOP]
        return a >= 128 and r >= 128
    left = right = None
    if white(0):
        x = 0
        while x + 1 < MIRROR_IN and white(x + 1):
            x += 1
        left = (0, x)
    if white(255):
        x = 255
        while x - 1 > 255 - MIRROR_IN and white(x - 1):
            x -= 1
        right = (x, 255)
    return left, right

def wheel_runs(cock):
    """Steering wheel rim marks: the right-hand poses of the user's original
    ZX version (assets/cockpit/steering_data.asm, BBC marks scaled to the
    cockpit), as vertical runs (top row, column, rows, mask). The left-hand
    poses are their mirror images (user's choice); both are clipped to the
    white cockpit pixels when drawn."""
    import re
    txt = (ROOT / 'assets/cockpit/steering_data.asm').read_text()
    poses = {}
    for m in re.finditer(r'steering_pose_(\d+):\s*\n\s*defb ([\d,]+)', txt):
        vals = [int(v) for v in m.group(2).split(',')]
        poses[int(m.group(1))] = [(vals[i] | vals[i + 1] << 8, vals[i + 2]) for i in range(0, len(vals), 3)]

    def yx(a):
        a -= 0x4000
        return ((a >> 5) & 0xC0) | ((a >> 8) & 7) | ((a >> 2) & 0x38), a & 31
    result = []
    for k in range(62):
        runs = []
        for c, b, y in sorted((yx(a)[1], b, yx(a)[0]) for a, b in poses[2 * k]):
            if runs and runs[-1][1] == c and runs[-1][3] == b and runs[-1][0] + runs[-1][2] == y:
                runs[-1][2] += 1
            else:
                runs.append([y, c, 1, b])
        for y, c, n, b in runs:            # both sides must be opaque cockpit
            assert 128 <= y and y + n <= 192 and n <= 8
            for r in range(y, y + n):
                for col in (c, 31 - c):
                    assert cock[r - COCKPIT_TOP][col][1] == 0xFF, (k, r, col)
        result.append(runs)
    return result


def cas_indicator(cock):
    """The C64 Revs+ CAS indicator: four multicolour bytes of the C64
    dashboard bitmap ($7C23, $7C24, $7C1C, $7C1B, values at $9C99 when on),
    colour-2 pixels mapped onto the cockpit (C64 dashboard 320 x 96 from
    bitmap row 104 = cockpit 256 x 77, scale 4/5), as in the user's version."""
    from c64_image import selector_image
    on = selector_image()[0x4800 + 0x99:0x4800 + 0x9D]
    pixels = set()
    for address, value in zip((0x7C23, 0x7C24, 0x7C1C, 0x7C1B), on):
        offset = address - 0x7040
        y = offset // 320 * 8 + offset % 8
        x = offset % 320 // 8 * 8
        for bit in range(4):
            if (value >> (6 - 2 * bit)) & 3 == 2:
                pixels.update(((x + 2 * bit, y), (x + 2 * bit + 1, y)))
    masks = {}
    for y in range(77):
        for x in range(256):
            if (x * 5 // 4, y * 5 // 4) in pixels:
                masks[(y, x >> 3)] = masks.get((y, x >> 3), 0) | (0x80 >> (x & 7))
    assert masks
    return [(screen_addr(COCKPIT_TOP + y, c), m, cock[y][c][0]) for (y, c), m in sorted(masks.items())]


def main():
    global img_px
    img_px = Image.open(ROOT / 'assets/cockpit/cockpit0.png').convert('RGBA').load()
    cock = load_cockpit()
    srcdata.write_bin('gfx/cockpit.bin', [ink for row in cock for ink, _ in row])

    # bottom view rows behind fully opaque cockpit rows: never shown
    hidden = 0
    while hidden < VIEW_ROWS:
        y = VIEW_TOP + VIEW_ROWS - 1 - hidden
        if y < COCKPIT_TOP or any(m != 0xFF for _, m in cock[y - COCKPIT_TOP]):
            break
        hidden += 1
    lines = ['; Generated by tools/gen_cockpit.py - do not edit', '',
             'VIEW_TOP        EQU %d                  ; screen row of view buffer row 0' % VIEW_TOP,
             'COCKPIT_TOP     EQU %d' % COCKPIT_TOP,
             'HIDDEN_LINES    EQU %d                  ; track lines 0.. hidden by the cockpit' % hidden, '',
             '; ViewCopy: view buffer -> screen rows %d..%d' % (VIEW_TOP, VIEW_TOP + VIEW_ROWS - 1),
             'ViewCopy:']
    full_rows = []
    for r in range(VIEW_ROWS):
        y = VIEW_TOP + r
        src = 'VIEW_BUF + %d' % (r * 32)
        lines.append('vcRow%d:' % r)
        if y < COCKPIT_TOP or all(m == 0 for _, m in cock[y - COCKPIT_TOP]):
            lines.append('        ld hl, %s' % src)
            lines.append('        ld de, $%04X' % screen_addr(y))
            lines.append('        call CopyRow32')
            full_rows.append(y)
            continue
        row = cock[y - COCKPIT_TOP]
        cx = 0
        while cx < 32:
            ink, mask = row[cx]
            if mask == 0xFF:
                cx += 1
                continue
            if mask == 0:
                n = 1
                while cx + n < 32 and row[cx + n][1] == 0:
                    n += 1
                lines.append('        ld hl, %s + %d' % (src, cx))
                lines.append('        ld de, $%04X' % screen_addr(y, cx))
                lines.extend(['        ldi'] * n)
                cx += n
                continue
            lines.append('        ld a, (%s + %d)' % (src, cx))
            lines.append('        and $%02X' % (~mask & 0xFF))
            if ink:
                lines.append('        or $%02X' % ink)
            lines.append('        ld ($%04X), a' % screen_addr(y, cx))
            cx += 1
    lines.append('        ret')
    lines.append('')
    lines.append('; ViewCopyFrom: copy view rows A..%d (the rows above are unchanged sky)' % (VIEW_ROWS - 1))
    lines.append('ViewCopyFrom:')
    lines.append('        add a, a')
    lines.append('        ld l, a')
    lines.append('        ld h, 0')
    lines.append('        ld de, viewCopyRows')
    lines.append('        add hl, de')
    lines.append('        ld a, (hl)')
    lines.append('        inc hl')
    lines.append('        ld h, (hl)')
    lines.append('        ld l, a')
    lines.append('        jp (hl)')
    lines.append('viewCopyRows:')
    for r in range(0, VIEW_ROWS + 1, 8):
        lines.append('        dw ' + ', '.join('vcRow%d' % k for k in range(r, min(r + 8, VIEW_ROWS + 1))))
    lines.append('vcRow%d:' % VIEW_ROWS)
    lines.append('        ret')
    lines.append('')
    # tyre tread animation: opaque bytes that differ between the two phases
    c1 = load_cockpit('cockpit1.png')
    lines.append('; tyreTab: screen address and XOR mask of the tyre tread bytes')
    lines.append('tyreTab:')
    count = 0
    for y in range(len(cock)):
        for cx in range(32):
            (i0, m0), (i1, m1) = cock[y][cx], c1[y][cx]
            if i0 != i1:
                assert m0 == 0xFF and m1 == 0xFF
                lines.append('        dw $%04X' % screen_addr(COCKPIT_TOP + y, cx))
                lines.append('        db $%02X' % (i0 ^ i1))
                count += 1
    lines.append('TYRE_BYTES      EQU %d' % count)
    lines.append('')
    lines.append('CopyRow32:')
    lines.extend(['        ldi'] * 32)
    lines.append('        ret')
    srcdata.write('viewcopy.asm', lines)

    # wing mirrors: glass masks per segment and row (three byte columns from
    # the segment's first column), screen addresses of the mirror rows
    mirror = ['; Generated by tools/gen_cockpit.py - wing mirror glass masks', '',
              'MIRROR_TOP      EQU %d' % MIRROR_TOP,
              'MIRROR_ROWS     EQU %d' % MIRROR_ROWS,
              'MIRROR_MID      EQU %d' % MIRROR_MID,
              'mirrorRows:                             ; screen address of each mirror row']
    for y in range(MIRROR_TOP, MIRROR_TOP + MIRROR_ROWS):
        mirror.append('        dw $%04X' % screen_addr(y))
    mirror.append('mirrorShift:                            ; pixel of the segment start in its byte')
    mirror.append('        db ' + ', '.join(str(x0 & 7) for x0, x1 in MIRROR_SEGMENTS))
    mirror.append('mirrorSegs:                             ; mask table of each segment')
    mirror.append('        dw ' + ', '.join('mirrorTab + %d' % (43 * k) for k in range(6)))
    mirror.append('mirrorTab:                              ; per segment: first byte column, '
                  '%d rows x 2 masks' % MIRROR_ROWS)
    for x0, x1 in MIRROR_SEGMENTS:
        c0 = x0 >> 3
        assert (x1 >> 3) - c0 <= 1
        mirror.append('        db %d' % c0)
        for y in range(MIRROR_TOP, MIRROR_TOP + MIRROR_ROWS):
            spans = [g for g in mirror_glass(img_px, y) if g]
            masks = []
            for c in range(c0, c0 + 2):
                m = 0
                for b in range(8):
                    x = c * 8 + b
                    if x0 <= x <= x1 and x < 256 and any(a <= x <= z for a, z in spans):
                        m |= 0x80 >> b
                masks.append(m)
            mirror.append('        db ' + ', '.join('$%02X' % v for v in masks))
    srcdata.write('mirrors.asm', mirror)

    # steering wheel rim marks and the CAS indicator
    runs = wheel_runs(cock)
    wheel = ['; Generated by tools/gen_cockpit.py - steering wheel marks, CAS indicator', '',
             'wheelPoseIdx:                           ; first run of right-hand pose k (63 entries)']
    idx, n = [], 0
    for r in runs:
        idx.append(n)
        n += len(r)
    idx.append(n)
    assert n < 256
    for i in range(0, 63, 16):
        wheel.append('        db ' + ', '.join(str(v) for v in idx[i:i + 16]))
    wheel.append('wheelRuns:                              ; top row - 128, column | (rows - 1) << 5, mask')
    for r in runs:
        wheel.append('        db ' + ', '.join(f'{y - 128}, {c | (n - 1) << 5}, ${b:02X}' for y, c, n, b in r))
    wheel.append('casIndicator:                           ; screen address, mask, cockpit byte')
    for a, m, orig in cas_indicator(cock):
        wheel.append(f'        dw ${a:04X}')
        wheel.append(f'        db ${m:02X}, ${orig:02X}')
    wheel.append('        dw 0')
    srcdata.write('wheel.asm', wheel)


if __name__ == '__main__':
    main()
