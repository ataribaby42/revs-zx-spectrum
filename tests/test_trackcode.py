"""The track code of the extra tracks (build/revs_trackcode_<track>.bin): every patch
of its list finds the main program's own bytes ("old") at its address,
TcLoaded writes the new bytes, and TcReset brings back the whole program
exactly (the UI does that before another track loads)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Z80, track_code  # noqa: E402

EXTRA = ['Brands Hatch', 'Donington Park', 'Nurburgring', 'Oulton Park', 'Snetterton']


def patches(mem, start):
    out = []
    p = mem[start] | mem[start + 1] << 8
    while mem[p]:
        n = mem[p]
        assert 1 <= n <= 3, hex(p)
        addr = mem[p + 1] | mem[p + 2] << 8
        new, old = bytes(mem[p + 3:p + 3 + n]), bytes(mem[p + 3 + n:p + 3 + 2 * n])
        out.append((addr, new, old))
        p += 3 + 2 * n
    return out


def check(n, track):
    z = Z80()
    tc = z.sym('TRACKCODE')
    code = track_code(track)
    assert tc + len(code) <= z.sym('TRACKCODE_END'), f'{track}: {len(code)} bytes'
    z.mem[tc:tc + len(code)] = code
    before = bytes(z.mem[0x4000:0x10000])
    pts = patches(z.mem, tc)
    for addr, new, old in pts:
        assert not tc <= addr < tc + len(code), hex(addr)
        have = bytes(z.mem[addr:addr + len(old)])
        assert have == old, f'{track} ${addr:04X}: main {have.hex()} list {old.hex()}'
    z.call('TcLoaded')
    for addr, new, old in pts:
        assert bytes(z.mem[addr:addr + len(new)]) == new, f'{track} ${addr:04X} not patched'
    z.call('TcReset')
    after = bytes(z.mem[0x4000:0x10000])
    skip = {z.sym('tcPatchList'), z.sym('tcPatchList') + 1, z.sym('TcPatch.mode') + 1}
    stack = range(z.sym('TRACKCODE') - 0x20, z.sym('TRACKCODE'))       # the harness's calls
    diff = [a for a in range(0x4000, 0x10000)
            if before[a - 0x4000] != after[a - 0x4000] and a not in skip and a not in stack]
    assert not diff, f'{track}: not restored at ' + ' '.join(f'${a:04X}' for a in diff[:8])
    return len(code), len(pts)


if __name__ == '__main__':
    for n, track in enumerate(EXTRA):
        size, count = check(n, track)
        print(f'{track}: {size} bytes, {count} patches OK')
