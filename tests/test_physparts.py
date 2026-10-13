"""Run the physics comparison routine by routine to locate differences."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_physics as tp  # noqa: E402

ROUTINES = [
    ('RotateCoordToCar', 0x490B, None), ('ApplySpinYaw', 0x477B, None),
    ('ApplyGrassOrTrack', 0x4C26, None), ('ApplyEngine', 0x4A25, None),
    ('ApplyTyresAndSkids', 0x47CB, 0), ('ApplyTyresAndSkids', 0x47CB, 1),
    ('ApplySteeringSpeed', 0x47F7, None), ('ApplySteeringForce', 0x4817, None),
    ('ScaleTyreForces', 0x484B, None), ('ApplyWingBalance', 0x4CBC, None),
    ('RotateCarToCoord', 0x4913, None), ('UpdateVelocity', 0x4989, None),
    ('ApplyDeltas', 0x4941, None), ('ApplyElevation', 0x453A, None),
]


def run(name, c64addr, x, n=200, seed=1):
    rng = random.Random(seed)
    c64, z = tp.C64R(), tp.Z80()
    fails = 0
    first = None
    for i in range(n):
        tp.set_state(c64, z, rng)
        rnd = [rng.randrange(256) for _ in range(16)]
        c64.rand = list(rnd)
        tp.patch_z80_random(z, rnd)
        c64.call(c64addr, x=x or 0)
        z.call(name, c=x or 0)
        try:
            tp.compare(c64, z, f'{name} case {i}')
        except AssertionError as e:
            fails += 1
            first = first or str(e)
    print(f'{name}({x}): {fails}/{n}')
    if first:
        print('   ', first.replace(chr(10), chr(10) + '    ')[:1500])


if __name__ == '__main__':
    only = sys.argv[1] if len(sys.argv) > 1 else None
    for r in ROUTINES:
        if only and r[0] != only:
            continue
        run(*r)
