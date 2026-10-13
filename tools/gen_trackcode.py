"""Per-track constants for the Z80 track code (src/trackcode.asm), read from
the C64 code of each extra track (the routines its track hook patches into
the main game; see notes/extra-tracks.md).

Writes src/trackconst_<track>.asm for the extra tracks (by tools/gen_src.py,
not by the build): track file addresses as
offsets into the track slot (C64 $5300 = TRACK) and constants.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))

from py65.devices.mpu6502 import MPU  # noqa: E402
from py65.disassembler import Disassembler  # noqa: E402
import c64_trackcode  # noqa: E402
import srcdata  # noqa: E402

EXTRA = ['Brands Hatch', 'Donington Park', 'Nurburgring', 'Oulton Park', 'Snetterton']


def routine(dis, pc, n=60):
    """[(address, mnemonic, operand text)] from pc up to and incl. RTS/JMP."""
    out = []
    for _ in range(n):
        length, text = dis.instruction_at(pc)
        mnem, _, opnd = text.partition(' ')
        out.append((pc, mnem, opnd))
        if mnem in ('RTS', 'JMP'):
            break
        pc += length
    return out


def addr(opnd):
    m = re.search(r'\$([0-9a-f]{4})', opnd)
    return int(m.group(1), 16) if m else None


def imm(opnd):
    m = re.match(r'#\$([0-9a-f]{2})', opnd)
    return int(m.group(1), 16)


def find(code, mnem, pattern, start=0):
    for i in range(start, len(code)):
        a, mn, op = code[i]
        if mn == mnem and re.search(pattern, op):
            return i
    raise AssertionError(f'{mnem} {pattern} not found')


def jsr_target(mem, at):
    assert mem[at] == 0x20, hex(at)
    return mem[at + 1] | mem[at + 2] << 8


def constants(track):
    pts, before, after = c64_trackcode.patches(track)
    mem = after
    dis = Disassembler(MPU(memory=list(mem)))
    c = {}
    hook_from = jsr_target(mem, 0x11fc)
    hook_first = jsr_target(mem, 0x123d)
    hook_data = jsr_target(mem, 0x12af)
    hook_vec = jsr_target(mem, 0x138a)
    assert jsr_target(mem, 0x13e7) == hook_vec
    fr = routine(dis, hook_from)
    i = find(fr, 'LDA', r',Y')
    c['SECTIONFROM'] = addr(fr[i][2])
    assert c['SECTIONFROM'] == 0x5905
    names = ['YAWALO', 'YAWLO', 'YAWAHI', 'YAWHI', 'TSLOPE', 'SLOPE', 'SUBCONFIG']
    j = find(fr, 'TAY', '', i)
    k = j + 1
    for nm in names:
        c[nm] = addr(fr[k][2])
        k += 1
    k = find(fr, 'STA', r'\$', k)
    c['SUBSECTION'] = addr(fr[k][2])
    k = find(fr, 'STA', r'\$', k + 1)
    c['HORIZON'] = addr(fr[k][2])                   # GetSectionAngles immediate
    assert c['HORIZON'] == 0x20c0
    k = find(fr, 'STA', r'\$', k + 1)
    c['SUBSEG'] = addr(fr[k][2])
    k = find(fr, 'JSR', r'\$', k)
    setseg = addr(fr[k][2])
    ss = routine(dis, setseg)
    assert addr(ss[1][2]) == c['SUBSECTION']
    k = find(ss, 'LDA', r',Y')
    c['YAWDLO'] = addr(ss[k][2])
    k = find(ss, 'LDA', r',Y', k + 1)
    c['YAWDHI'] = addr(ss[k][2])
    k = find(ss, 'LDA', r',Y', k + 1)
    c['SLOPED'] = addr(ss[k][2])
    k = find(ss, 'JSR', r'\$', k + 3)
    calc = addr(ss[k][2])
    cs = routine(dis, calc)
    assert addr(cs[0][2]) == c['YAWLO'] and addr(cs[2][2]) == c['YAWHI']
    k = find(cs, 'LDY', r',X')
    c['XCURVE'] = addr(cs[k][2])
    k = find(cs, 'LDA', r',X', k)
    c['ZCURVE'] = addr(cs[k][2])
    k = find(cs, 'LDY', r'\$02')
    c['WIDTH'] = imm(cs[k + 1][2])
    outs = [addr(op) for a, mn, op in cs if mn == 'STA' and ',Y' in op]
    assert outs == [0x5400, 0x5800, 0x5600, 0x5700, 0x5500], outs
    dp = routine(dis, hook_data)
    k = find(dp, 'JSR', r'\$')
    upd = addr(dp[k][2])
    up = routine(dis, upd, 40)
    c['SUBSIZE'] = addr(up[find(up, 'CMP', r',Y')][2])
    c['SUBCOUNT'] = addr(up[find(up, 'CPY', r'\$5')][2])
    assert addr(up[0][2]) == c['SUBSECTION'] and addr(up[1][2]) == c['SUBSEG']
    # moved tables and changed constants (the patched operands)
    w = lambda a: mem[a] | mem[a + 1] << 8
    c['STEERING'] = w(0x4526)
    c['SIGNZ'], c['SIGNY'], c['SIGNX'] = w(0x4d18), w(0x4d20), w(0x4d28)
    c['SIGNDATA'] = w(0x4d2e)
    assert w(0x4d38) == c['SIGNDATA']
    if mem[0x2546] != before[0x2546]:
        c['BRAKE'] = mem[0x2546]
    if mem[0x282b] != before[0x282b]:
        c['HEIGHTCAP'] = mem[0x282b]
    fx = routine(dis, w(0x227c))
    if [m for a, m, o in fx] == ['STA', 'STA', 'RTS']:
        c['FIX'] = 0
    elif any(m == 'CPY' and o == '#$06' for a, m, o in fx):
        c['FIX'] = 2
    else:
        assert [m for a, m, o in fx][:5] == ['STA', 'STA', 'LDA', 'SEC', 'SBC'], fx
        c['FIX'] = 1
    hw = routine(dis, w(0x2286))
    c['ABSWIDTH'] = 1 if hw[0][1] == 'JSR' else 0
    fov = routine(dis, w(0xb468), 50)
    assert fov[0][1] == 'TYA' and fov[-1][1] == 'JMP', fov
    if mem[0x461b] != before[0x461b]:
        assert mem[0x461b] == 0x20
        sj = routine(dis, w(0x461c))
        assert [m for a, m, o in sj] == ['BNE', 'LDA', 'JSR', 'BPL', 'DEC', 'ASL', 'ROL', 'RTS'], sj
        c['SLOPEJUMP'] = 1
    if mem[0x3574] != before[0x3574] or mem[0x35f4] != before[0x35f4]:
        c['HAIRPIN'] = 36                           # objTop/objBottom part 36
        c['HPTOP'], c['HPBOTTOM'] = mem[0x3574], mem[0x35f4]
        c['HPTOP0'], c['HPBOTTOM0'] = before[0x3574], before[0x35f4]
    if mem[0x201c] != before[0x201c]:
        assert mem[0x201c] == 0
        c['NOSKIP'] = 0
    return c


def main():
    for track in EXTRA:
        c = constants(track)
        lines = [f'; {track}: constants of the Z80 track code (src/trackcode.asm), imported',
                 '; from the C64 track code by tools/gen_trackcode.py', '']
        for k, v in c.items():
            if k in ('WIDTH', 'BRAKE', 'HEIGHTCAP', 'NOSKIP', 'SLOPEJUMP', 'FIX', 'ABSWIDTH',
                     'HAIRPIN', 'HPTOP', 'HPBOTTOM', 'HPTOP0', 'HPBOTTOM0'):
                lines.append(f'TC_{k:12s} EQU ${v:02X}')
            elif k == 'HORIZON':
                continue
            else:
                lines.append(f'TC_{k:12s} EQU TRACK + ${v - 0x5300:03X}       ; C64 ${v:04X}')
        srcdata.write(f'trackconst_{srcdata.TRACK_KEYS[track]}.asm', lines)
        print(track, {k: (hex(v)) for k, v in c.items()})


if __name__ == '__main__':
    main()
