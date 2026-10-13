"""Combined C64 Revs+ memory image built from the parts of the tape in
assets/c64 (the main game and the track selector block, extracted once from
the tape by tools/c64_extract.py).

The track selector copies its block $4800-$49FF to $9C00-$9DFF and runs the
Revs+ installer at $9C00 before starting the game ($5A30). The installer
patches the game: the computer assisted steering (CAS) key check ($0E84),
the CAS entry of ProcessDrivingKeys ($154D), the steering centring when no
steering key is held ($15EE) and the drift guard in MovePlayerSegment
($46AA). main_image() applies it by running the installer code itself.
The installer ends with the track hook (CallTrackHook, $5A30): RTS for
Silverstone, JMP $5700 for the five extra tracks, whose code there patches
about 42 bytes of the main game (hooks into the track file, as the BBC
ModifyGameCode); main_image() runs it to its RTS.

Approved deviations of the Spectrum version are applied to the reference
too (APPROVED_PATCHES): no crane after a crash into the fence (the user's
choice; CheckForCrash leaves heightAboveTrack at 0 instead of 127, so a
Novice race restarts on the ground). The extra tracks' HookFirstSegment
(GetFirstSegment facing backwards, $123D) returns the X of CalcSegmentVector
(a zTrackCurve value), and GetFirstSegment then clears segmentFlags,X of
another segment instead of the front one's (an original bug, fixed with the
user's approval): the JSR goes through a helper at $02A7 that keeps X.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets/c64'

# file, tape load group (end address, bytes 5 and 6), address range
PARTS = [('main_0b00.bin', (0x5300, 0x00, 0x00), 0x0b00, 0x5300),
         ('main_6400.bin', (0x9300, 0x00, 0x00), 0x6400, 0x9300),
         ('main_a000.bin', (0xcc00, 0x00, 0x00), 0xa000, 0xcc00),
         ('selector_1400.bin', (0x4c00, 0x00, 0x14), 0x1400, 0x4c00)]
# address: (original bytes, patched bytes)
APPROVED_PATCHES = {0x109d: (b'\x7f', b'\x00')}   # CheckForCrash: LDA #0
# extra tracks: JSR HookFirstSegment -> JSR KEEPX_HELPER (free C64 RAM):
# STX $02FF / JSR HookFirstSegment / LDX $02FF / RTS
KEEPX_HELPER = 0x02a7
KEEPX_CODE = bytes([0x8e, 0xff, 0x02, 0x20, 0x1b, 0x5a, 0xae, 0xff, 0x02, 0x60])
TRACKS = ['Brands Hatch', 'Donington Park', 'Nurburgring', 'Oulton Park', 'Silverstone', 'Snetterton']


def load_parts(main=True):
    """64 KiB with the main game parts (main) or the track selector block."""
    mem = bytearray(65536)
    for name, _, lo, hi in PARTS:
        if name.startswith('main') == main:
            mem[lo:hi] = (ASSETS / name).read_bytes()
    return mem


def main_image(track='Silverstone', revs_plus=True):
    mem = load_parts()
    sel = selector_image()
    start = 0x1800 + 0x800 * TRACKS.index(track)
    mem[0x5300:0x5b00] = sel[start:start + 0x800]
    if revs_plus:
        install_revs_plus(mem, sel)
    for addr, (old, new) in APPROVED_PATCHES.items():
        assert mem[addr:addr + len(old)] == old, hex(addr)
        mem[addr:addr + len(new)] = new
    if revs_plus and mem[0x123d:0x1240] == bytes([0x20, 0x1b, 0x5a]):     # JSR HookFirstSegment
        h = KEEPX_HELPER
        assert not any(mem[h:h + len(KEEPX_CODE)]) and mem[0x2ff] == 0
        mem[h:h + len(KEEPX_CODE)] = KEEPX_CODE
        mem[0x123d:0x1240] = bytes([0x20, h & 255, h >> 8])
    return mem


def install_revs_plus(mem, sel):
    """Copy the installer block and run it (6502) and the track hook it
    jumps to ($5A30) until they return."""
    from py65.devices.mpu6502 import MPU
    mem[0x9c00:0x9e00] = sel[0x4800:0x4a00]
    cpu = MPU(memory=list(mem))
    cpu.pc = 0x9c00
    cpu.sp = 0xfd
    cpu.memory[0x1fe], cpu.memory[0x1ff] = 0xef, 0xff     # RTS -> $FFF0
    for _ in range(200_000):
        if cpu.pc == 0xfff0:
            break
        cpu.step()
    else:
        raise AssertionError('Revs+ installer / track hook did not finish')
    cpu.memory[0x1fe], cpu.memory[0x1ff] = mem[0x1fe], mem[0x1ff]
    mem[:] = bytes(cpu.memory)


def selector_image():
    return load_parts(main=False)
