"""Compare GetObjYawAngle / GetObjPitchAngle with the C64 logarithmic projection.
The average time of a yaw and a pitch call must stay within the budget."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import C64, Z80  # noqa: E402

C64_YAW = 0x1CDA
C64_PITCH = 0x1F17
BUDGET = 1_950                          # average T of a yaw plus a pitch call (no contention)


def rand16(rng):
    kind = rng.random()
    if kind < 0.1:
        return rng.randrange(-4, 5) & 0xFFFF
    if kind < 0.4:
        return rng.randrange(-300, 300) & 0xFFFF
    if kind < 0.7:
        return rng.randrange(-4000, 4000) & 0xFFFF
    return rng.randrange(65536)


def run(n, seed=1):
    rng = random.Random(seed)
    c64, z80 = C64(), Z80()
    fails = 0
    total = 0
    for i in range(n):
        x = rng.choice([rng.randrange(0, 118), 0xFA, 0xFD, 0xF4])
        y = 0
        point = [rand16(rng) for _ in range(3)]
        ref = [rand16(rng) for _ in range(3)]
        # make the difference small sometimes
        if rng.random() < 0.5:
            point = [(r + rng.randrange(-3000, 3000)) & 0xFFFF for r in ref]
        pitch = rng.randrange(256)
        for m in (c64, z80):
            lo = m.get('SEG_LO', 256)
            hi = m.get('SEG_HI', 256)
            for a in range(3):
                lo[(x + a) & 255] = point[a] & 255
                hi[(x + a) & 255] = point[a] >> 8
            m.set('SEG_LO', lo)
            m.set('SEG_HI', hi)
            if m is c64:
                rc = m.get('refCoord', 12)
                for a in range(3):
                    rc[y + a] = ref[a] & 255
                    rc[y + 3 + a] = ref[a] >> 8
                m.set('refCoord', rc)
            else:
                for a, nm in enumerate(('playerCoordX', 'playerCoordY', 'playerCoordZ')):
                    m.set(nm, [rng.randrange(256), ref[a] & 255, ref[a] >> 8])
            m.set('playerPitchAngle', pitch)
        c64.call(C64_YAW, x=x, y=y)
        total += z80.call('GetObjYawAngle', c=x)
        names = ['II', 'JJ', 'K', 'L']
        a = [c64.get(k)[0] for k in names]
        b = [z80.get(k)[0] for k in names]
        if a != b:
            fails += 1
            if fails < 10:
                print(f'yaw #{i} x={x} y={y} p={point} r={ref}: C64 {a} Z80 {b}')
            continue
        c64.call(C64_PITCH, x=x, y=y)
        total += z80.call('GetObjPitchAngle', c=x)
        ca, za = c64.carry, z80.carry
        names = ['scaleUp', 'scaleDown']
        a = [ca] + [c64.get(k)[0] for k in names]
        b = [za] + [z80.get(k)[0] for k in names]
        if not ca:
            a.append(c64.get('LL')[0])
            b.append(z80.get('LL')[0])
        if a != b:
            fails += 1
            if fails < 10:
                print(f'pitch #{i} x={x} y={y} p={point} r={ref}: C64 {a} Z80 {b}')
    return fails, total / n


if __name__ == '__main__':
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
    f, avg = run(n)
    print(f'projection: {n} cases, {f} failures, yaw + pitch {avg:.0f} T (budget {BUDGET})')
    sys.exit(1 if f or avg > BUDGET else 0)
