"""Long random play in the emulator with memory and crash checks.

The game runs from build/revs.sna (contended memory, interrupts) with random
keys: through the menus, practice and competition sessions on all tracks
(loaded from output/revs_tracks.tap, the ROM tape routines trapped), the
pits, Caps Shift + 1/2/3, pause, the toggles (J with a Kempston joystick),
results saved and loaded. After every TV frame:

* PC is at an instruction of the program, the UI overlay, the track code or
  the ROM tape routines (not in data or the screen: no crash, no reset);
* the IM2 vector (JP Isr at $FFF4) and, while driving, the track file, its
  track code, the stored UI overlay (hidden sky, UI_STORE) are unchanged;
* back in the menus the UI overlay's code is as loaded;
* the stack stays above its limit (a canary below STACK_TOP).

Every byte that changes is recorded; at the end each one must be a variable
or buffer (a db/dw/ds line of the listing, a buffer page), an operand that
the code patches itself ("; patched" in the listing) or a place the track
code patches. Anything else (an instruction overwritten) is reported.

Usage: python tests/test_soak.py [frames] [seed]
Needs build.bat's build (build/revs.sna, build/src/*.lis, the tapes).
"""
import random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from harness import ROOT, z80_symbols  # noqa: E402
from zx import Machine  # noqa: E402
from skoolkit.simutils import PC, SP, A, F, D, E  # noqa: E402

S = z80_symbols()
FRAME = 69888
TRAP = 0x0562                       # LD-BYTES after its SA/LD-RET push
ROM_TAPE = range(0x04C2, 0x0620)    # SA-BYTES, LD-BYTES and their loops
TRACKS = ['brandshatch', 'doningtonpark', 'nurburgring', 'oultonpark', 'silverstone', 'snetterton']
STACK_LIMIT = S['DATA_END']         # the stack must stay above the tables


STARTS = set()                      # the first byte of every instruction
STORES = set()                      # bytes that LD (nn),r instructions write
RUNTIME_CODE = set()                # ds areas that the code fills with instructions


IMM8 = {0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E, 0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE,
        0xD3, 0xDB, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38}
IMM16 = {0x01, 0x11, 0x21, 0x31, 0x22, 0x2A, 0x32, 0x3A, 0xC2, 0xC3, 0xC4, 0xCA, 0xCC, 0xCD, 0xD2, 0xD4,
         0xDA, 0xDC, 0xE2, 0xE4, 0xEA, 0xEC, 0xF2, 0xF4, 0xFA, 0xFC}
INDEXED = {0x34, 0x35, 0x46, 0x4E, 0x56, 0x5E, 0x66, 0x6E, 0x7E, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x77,
           0x86, 0x8E, 0x96, 0x9E, 0xA6, 0xAE, 0xB6, 0xBE}


def ilen(b, i):
    """The length of the Z80 instruction at b[i]."""
    op = b[i]
    if op == 0xCB:
        return 2
    if op == 0xED:
        return 4 if b[i + 1] in (0x43, 0x4B, 0x53, 0x5B, 0x63, 0x6B, 0x73, 0x7B) else 2
    if op in (0xDD, 0xFD):
        op2 = b[i + 1]
        if op2 == 0xCB:
            return 4
        if op2 == 0x36:
            return 4
        if op2 in INDEXED:
            return 3
        return 1 + (3 if op2 in IMM16 else 2 if op2 in IMM8 else 1)
    return 3 if op in IMM16 else 2 if op in IMM8 else 1


def listing(path):
    """{address: (kind, text)} for every byte of a module listing: kind
    'code' (an instruction), 'patched' (an instruction that is patched at
    run time) or 'data' (db/dw/ds). The bytes of a REPT block and a macro
    are on one row (ENDR, the macro's name); a REPT's kind is its body's."""
    rows = []
    body = None
    for line in path.read_text(errors='replace').splitlines():
        m = re.match(r'\s*\d+\s+([0-9a-f]{4})\s+([0-9a-f]*)\s+(.*)$', line)
        if m:
            rows.append([int(m.group(1), 16), len(m.group(2)) // 2, m.group(3), m.group(2), body])
            if m.group(3).split(';')[0].strip().lower() == 'endr':
                body = None
            continue
        m = re.match(r' {10,}([0-9a-f]+)\s*$', line)        # more bytes of the row above
        if m and rows:
            rows[-1][1] += len(m.group(1)) // 2
            rows[-1][3] += m.group(1)
            continue
        m = re.match(r'\s*\d+\s+(.*)$', line)
        if m:
            src = m.group(1).split(';')[0].strip().lower()
            if src.startswith('rept'):
                body = []
            elif body is not None and src:
                body.append(src)
    out = {}
    for i, (addr, n, text, hexb, rept) in enumerate(rows):
        code = text.split(';')[0]
        code = re.sub(r'^\s*@?\w+:', '', code).strip().lower()
        if code == 'endr' and rept is not None:
            code = 'db' if all(re.match(r'(db|dw|ds|defb|defw|defs|defm)\b', s) for s in rept) else 'rept'
        elif not code or code.startswith(('include', 'assert', 'org', 'phase', 'dephase', 'section', 'global',
                                          'if', 'else', 'endif', 'rept', 'endr', 'defc')) \
                or re.match(r'\w+\s+(equ|defl|macro)\b', code) or code == 'endm':
            continue
        if n == 0 and i + 1 < len(rows) and rows[i + 1][0] > addr:
            n = rows[i + 1][0] - addr               # ds lines show no bytes
        kind = 'data' if re.match(r'(db|dw|ds|defb|defw|defs|defm|incbin|binary)\b', code) else \
            'patched' if 'patched' in text.lower() else 'code'
        for a in range(addr, addr + n):
            out[a] = (kind, text.strip())
        if kind == 'data' and 'patched' in text.lower():
            RUNTIME_CODE.update(range(addr, addr + n))      # instructions written at run time
        b = bytes.fromhex(hexb) if len(hexb) % 2 == 0 else b''
        if kind != 'data' and b:
            j = 0
            while j < len(b):
                STARTS.add(addr + j)
                k = ilen(b + b'\0\0\0', j)
                c = b[j:j + k]
                # stores to an absolute address: LD (nn),A / (nn),HL / ED (nn),rr / DD,FD (nn),IX,IY
                if len(c) == 3 and c[0] in (0x32, 0x22):
                    STORES.update(range(c[1] | c[2] << 8, (c[1] | c[2] << 8) + (1 if c[0] == 0x32 else 2)))
                elif len(c) == 4 and (c[0] == 0xED and c[1] in (0x43, 0x53, 0x63, 0x73) or
                                      c[0] in (0xDD, 0xFD) and c[1] == 0x22):
                    STORES.update(range(c[2] | c[3] << 8, (c[2] | c[3] << 8) + 2))
                j += k
    return out



MAIN = listing(ROOT / 'build/src/main.lis')
IMAGE = (ROOT / 'build/revs.bin').read_bytes()
TRACK_FILES = {k: (ROOT / f'build/revs_track_{k}.bin').read_bytes() for k in TRACKS}
TRACK_CODE = {k: (ROOT / f'build/revs_trackcode_{k}.bin').read_bytes() for k in TRACKS}
TC_LIST = {k: listing(ROOT / f'build/src/track_{k}.lis') for k in TRACKS}


def patch_sites():
    """Main program bytes that the track code patch lists change."""
    sites = set()
    tc = S['TRACKCODE']
    for code in TRACK_CODE.values():
        mem = bytearray(65536)
        mem[tc:tc + len(code)] = code
        p = mem[tc] | mem[tc + 1] << 8
        while mem[p]:
            n = mem[p]
            a = mem[p + 1] | mem[p + 2] << 8
            sites.update(range(a, a + n))
            p += 3 + 2 * n
    return sites


SITES = patch_sites()
UI_CODE = [a for a in range(S['UI_RUN'], S['UI_LIMIT']) if MAIN.get(a, ('',))[0] == 'code']
INSTR_STARTS = set(STARTS)          # (main program: listed first)


class Tape:
    """The tracks tape and blocks saved during the run, as LD-BYTES and
    SA-BYTES see them (a loop: after the last block the first one)."""

    def __init__(self, rng):
        data = (ROOT / 'output/revs_tracks.tap').read_bytes()
        self.blocks, i = [], 0
        while i < len(data):
            n = data[i] | data[i + 1] << 8
            self.blocks.append(data[i + 2:i + 2 + n])
            i += 2 + n
        self.pos = 0
        self.rng = rng
        self.loads = self.saves = 0

    def trap(self, m, save_ret, read_ret):
        """LD-BYTES / SA-BYTES; False when not called from UiReadBlock or
        UiWriteBlock (the jump at $6000, i.e. a restart, comes here too)."""
        mem, reg = m.mem, m.reg
        length = reg[D] << 8 | reg[E]
        ix = reg[8] << 8 | reg[9]
        ret = mem[reg[SP]] | mem[(reg[SP] + 1) & 0xFFFF] << 8
        if ret not in (save_ret, read_ret):
            return False
        ok = False
        if ret == save_ret:
            self.saves += 1
            self.blocks.append(bytes([reg[A]]) + bytes(mem[ix:ix + length]) + b'\x00')
            ok = True
        elif self.rng.random() > 0.05:                  # (5 %: a tape error)
            flag = reg[16]
            for _ in range(len(self.blocks)):
                blk = self.blocks[self.pos]
                self.pos = (self.pos + 1) % len(self.blocks)
                if blk[0] == flag:
                    if len(blk) - 2 == length:
                        mem[ix:ix + length] = blk[1:1 + length]
                        ix = (ix + length) & 0xFFFF
                        reg[8], reg[9] = ix >> 8, ix & 255
                        reg[D] = reg[E] = 0
                        ok = True
                        self.loads += 1
                    break
        reg[F] = reg[F] | 1 if ok else reg[F] & 0xFE
        reg[SP] = (reg[SP] + 2) & 0xFFFF
        reg[PC] = ret
        return True


UI_KEYS = ['1', '2', '3', '4', '5', '6', 'ENTER', 'SPACE', '0', '7', '9', 'A', 'X', 'CAPS+0', 'CAPS+SPACE',
           'CAPS+3', 'SYM+M']
DRIVE_KEYS = [('Q',), ('Q', 'O'), ('Q', 'P'), ('A',), ('T',), ('Q', 'W'), ('S',), ('O',), ('P',), ('X',),
              ('CAPS', '1'), ('CAPS', '2'), ('CAPS', '3'), ('H',), ('N',), ('M',), ('C',), ('6',), ('7',),
              ('8',), ('9',), ('0',), ('J',), ()]
DRIVE_W = [40, 8, 8, 4, 6, 6, 2, 2, 2, 1, 0.6, 0.5, 0.3, 0.2, 0.3, 0.3, 0.3, 0.5, 0.5, 0.5, 0.5, 0.5, 0.3, 3]
# the Kempston port (read after J): no interface, up, up + right / left,
# up + fire, fire, down, anything
KEMPSTON = [None, 0x08, 0x09, 0x0A, 0x18, 0x10, 0x04, 'any']
KEMPSTON_W = [2, 6, 2, 2, 1, 1, 1, 1]
UI_W = [3, 3, 1, 0.5, 2, 1, 4, 4, 2, 1, 1, 1, 1, 0.5, 0.2, 0.1, 0.1]

# keys that the UI routine waiting for one usually gets (else any UI key)
UI_POLICY = {
    'UiMainMenu': {'1': 4, '2': 4, '3': 0.5, '4': 0.5, '5': 0.5, '6': 0.5},
    'UiThreeOptions': {'1': 1, '2': 1, '3': 1},
    'UiNumberInput': {'0': 1, '1': 1, '2': 1, '3': 1, '4': 0.5, '5': 0.5, '9': 0.3, 'ENTER': 2, 'CAPS+0': 0.3},
    'UiSpace': {'SPACE': 5, 'CAPS+3': 0.1},
    'UiNameEntry': {'A': 1, 'X': 1, 'R': 1, 'ENTER': 1.5, 'CAPS+0': 0.5, 'SYM+M': 0.2},
    'UiTrackMenu': {'1': 1, '2': 1, '3': 1, '4': 1, '5': 1, '6': 1, 'CAPS+SPACE': 0.2},
    'UiLoadTrack': {'ENTER': 1, 'SPACE': 1, 'CAPS+SPACE': 0.3},
    'UiResultsLoad': {'ENTER': 1, 'SPACE': 1, 'CAPS+SPACE': 0.3},
    'UiResultsSave': {'ENTER': 1, 'SPACE': 1, 'CAPS+SPACE': 0.3},
    'UiTable': {'SPACE': 1}, 'UiShowScores': {'SPACE': 1}, 'UiShowResults': {'SPACE': 1},
}
UI_ROUTINES = sorted((a, n) for n, a in S.items()
                     if n.startswith('Ui') and '.' not in n and S['UI_KEYS'] <= a < S['UI_LIMIT'])


def routine_of(addr):
    name = None
    for a, n in UI_ROUTINES:
        if a > addr:
            break
        name = n
    return name


def routine_waiting(mem, reg):
    """The UI routine waiting for a key (the caller of UiKey / UiWaitRelease)."""
    name = routine_of(reg[PC])
    sp = reg[SP]
    for _ in range(3):
        if name not in ('UiKey', 'UiWaitRelease', None):
            break
        name = routine_of(mem[sp] | mem[(sp + 1) & 0xFFFF] << 8)
        sp += 2
    return name


def ui_key(rng, routine):
    policy = UI_POLICY.get(routine)
    if policy and rng.random() < 0.85:
        return rng.choices(list(policy), list(policy.values()))[0]
    return rng.choices(UI_KEYS, UI_W)[0]


def run(frames, seed):
    rng = random.Random(seed)
    m = Machine(ROOT / 'build/revs.sna')
    mem, reg = m.mem, m.reg
    wb = S['UiWriteBlock']
    mem[wb + 2:wb + 4] = [0x62, 0x05]               # CALL $0562: saves trapped too
    read_ret = 0x6000 + IMAGE.index(b'\xCD\x62\x05', S['UiReadBlock'] - 0x6000) + 3
    harness_bytes = {wb + 2, wb + 3, 0x6000, 0x6001, 0x6002}
    tc_end = S['TRACKCODE'] + max(len(c) for c in TRACK_CODE.values())
    tape = Tape(rng)
    for a in range(STACK_LIMIT, S['STACK_TOP']):     # stack canary
        mem[a] = 0xA5
    prev = bytes(mem)
    written = {}
    problems = []
    keys, hold = (), 0
    driving = False
    stored = None
    track_key = 'silverstone'
    lowest_sp = 0x10000
    counts = {'drive': 0, 'ui': 0, 'kempston': 0}
    driven = set()

    def ui_active():
        a = S['UiNewGame']
        return bytes(mem[a:a + 8]) == IMAGE[a - 0x6000:a - 0x6000 + 8]

    for frame in range(frames):
        if hold == 0:
            if ui_active():
                if keys:                                # a key, then a release
                    keys, hold = (), rng.randrange(5, 30)
                else:
                    k = ui_key(rng, routine_waiting(mem, reg))
                    keys, hold = tuple(k.split('+')), rng.randrange(2, 10)
            else:
                keys, hold = rng.choices(DRIVE_KEYS, DRIVE_W)[0], rng.randrange(1, 60)
                kempston = rng.choices(KEMPSTON, KEMPSTON_W)[0]
                m.ports.kempston = rng.randrange(256) if kempston == 'any' else kempston
        hold -= 1
        m.press(keys)
        if frame == 1:                                  # the program has started: from
            mem[0x6000:0x6003] = [0xC3, 0x62, 0x05]     # now on a jump to $6000 is a restart
        target = ((reg[25] // FRAME) + 1) * FRAME
        while reg[25] < target and not problems:        # PC every 2000 T-states
            m.sim.trace(reg[PC], TRAP, 0, min(target, reg[25] + 2000), 1, None, None, None, None, None)
            pc = reg[PC]
            if pc == TRAP and not tape.trap(m, wb + 4, read_ret):
                problems.append(f'frame {frame}: restart (the jump at $6000)')
            elif not (pc in INSTR_STARTS or pc in RUNTIME_CODE or pc in SITES or pc in ROM_TAPE
                      or S['TRACKCODE'] <= pc < tc_end
                      or pc in (S['IM2_JP'], 0xFFFF)):
                problems.append(f'frame {frame}: PC ${pc:04X} not at an instruction')
        if problems:
            break
        pc, sp = reg[PC], reg[SP]
        lowest_sp = min(lowest_sp, sp) if sp > 0x8000 else lowest_sp
        cur = bytes(mem)
        ui = ui_active()
        counts['ui' if ui else 'drive'] += 1
        counts['kempston'] += not ui and cur[S['joystickType']] == 1
        # IM2 vector
        isr = S['Isr']
        if cur[0xFFF4:0xFFF7] != bytes([0xC3, isr & 255, isr >> 8]):
            problems.append(f'frame {frame}: IM2 JP Isr at $FFF4 overwritten: {cur[0xFFF4:0xFFF7].hex()}')
            break
        # driving: the track, its code and the stored overlay stay
        if not ui:
            if not driving:
                driving = True
                track_key = next((k for k in TRACK_FILES if not track_diff(cur, k)), None)
                if track_key is None:
                    best = min(TRACK_FILES, key=lambda k: len(track_diff(cur, k)))
                    diff = [f'+${a - 0xC000:03X}' for a in track_diff(cur, best)]
                    problems.append(f'frame {frame}: the track slot is {best} but for {len(diff)} bytes: {diff[:12]}')
                    break
                stored = (cur[0x4000 + 2 * 32:0x4800], cur[0x4800:0x5000], cur[0x5B00:0x5F00])
                driven.add(track_key)
            else:
                diff = track_diff(cur, track_key)
                if diff:
                    problems.append(f'frame {frame}: track file overwritten at ${diff[0]:04X} (PC ${pc:04X})')
                    break
                code = TRACK_CODE[track_key]
                tc = S['TRACKCODE']
                bad = [a for a in range(tc, tc + len(code)) if cur[a] != code[a - tc]
                       and TC_LIST[track_key].get(a, ('data',))[0] != 'data']
                if track_key != 'silverstone' and bad:
                    problems.append(f'frame {frame}: track code overwritten at ${bad[0]:04X}')
                    break
                now = (cur[0x4000 + 2 * 32:0x4800], cur[0x4800:0x5000], cur[0x5B00:0x5F00])
                if hidden_changed(stored, now):
                    problems.append(f'frame {frame}: the stored UI overlay changed while driving '
                                    f'(PC ${pc:04X}): {hidden_changed(stored, now)}')
                    break
        else:
            if driving:
                driving = False
            in_ui = S['UI_RUN'] <= pc < S['UI_LIMIT']
            bad = [a for a in UI_CODE if cur[a] != IMAGE[a - 0x6000] and a not in SITES
                   and a not in STORES and a not in harness_bytes] if in_ui else []
            if bad:
                problems.append(f'frame {frame}: UI code differs at ${bad[0]:04X} after loading it')
                break
        # the stack
        low = next((a for a in range(STACK_LIMIT, S['STACK_TOP']) if cur[a] != 0xA5), S['STACK_TOP'])
        if low == STACK_LIMIT:
            problems.append(f'frame {frame}: the stack reached ${STACK_LIMIT:04X}')
            break
        # every changed byte
        for p in range(0x40, 0x100):
            lo = p << 8
            if cur[lo:lo + 256] != prev[lo:lo + 256]:
                for a in range(lo, lo + 256):
                    if cur[a] != prev[a] and a not in written:
                        written[a] = (frame, pc, 'UI' if ui else 'driving')
        prev = cur
    stack_low = next((a for a in range(STACK_LIMIT, S['STACK_TOP']) if mem[a] != 0xA5), S['STACK_TOP'])
    counts.update(loads=tape.loads, saves=tape.saves, tracks=sorted(driven))
    return problems, classify(written, harness_bytes), S['STACK_TOP'] - stack_low, counts


def track_diff(cur, key):
    """Addresses where the track slot differs from track file key. The
    extra tracks' track code keeps variables in it (+$0F8-$0FF) and builds
    the segment vectors in its tables (+$100-$5FF), as on the C64."""
    data = TRACK_FILES[key]
    ranges = [(0, 0x800)] if key == 'silverstone' else [(0, 0xF8), (0x600, 0x800)]
    return [0xC000 + o for lo, hi in ranges for o in range(lo, hi) if cur[0xC000 + o] != data[o]]


def hidden_changed(a, b):
    """Rows 2-7 of the first third (32 bytes each of the 8 pixel lines) and
    rows 8-9 of the second (the hidden sky), and UI_STORE."""
    names = ('hidden sky, first third', 'hidden sky, second third', 'UI_STORE')
    for name, x, y in zip(names, a, b):
        if name.startswith('hidden'):
            third = 0x4000 + 2 * 32 if 'first' in name else 0x4800
            for line in range(8):
                rows = range(2, 8) if 'first' in name else range(0, 2)
                for r in rows:
                    o = line * 256 + r * 32 - (2 * 32 if 'first' in name else 0)
                    if x[o:o + 32] != y[o:o + 32]:
                        return f'{name}, pixel line {line}, row {r}'
        elif x != y:
            return name
    return None


def classify(written, harness_bytes):
    """Changed bytes that are not variables, buffers, patched operands or
    track code patch sites: [(address, text, frame, pc, mode)]."""
    buffers = [(0x4000, 0x6000), (0xC000, 0xD100), (S['VIEW_BUF'], S['UI_LIMIT']), (0xF700, 0xF800),
               (S['OBJ_LINE'], S['OBJ_LINE'] + 64), (STACK_LIMIT, 0x10000)]
    odd = []
    for a, (frame, pc, mode) in sorted(written.items()):
        if any(lo <= a < hi for lo, hi in buffers) or a in harness_bytes or a in SITES:
            continue
        kind, text = MAIN.get(a, ('none', '(not in the listing)'))
        if kind in ('data', 'patched') or a in STORES:  # (self-modifying code)
            continue
        odd.append((a, text, frame, pc, mode))
    return odd


if __name__ == '__main__':
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    problems, odd, stack, counts = run(frames, seed)
    for p in problems:
        print('PROBLEM', p)
    for a, text, frame, pc, mode in odd[:40]:
        print(f'WRITE ${a:04X} {text!r} (frame {frame}, PC ${pc:04X}, {mode})')
    print(f'soak seed {seed}: {frames} frames ({counts["ui"]} in the menus, {counts["drive"]} driving, '
          f'{counts["kempston"]} with Kempston), '
          f'stack {stack} bytes deep, {counts["loads"]} tape loads, {counts["saves"]} saves, '
          f'tracks driven {" ".join(counts["tracks"])}, {len(problems)} problems, {len(odd)} unexpected writes')
    sys.exit(1 if problems or odd else 0)
