"""The game tape (output/revs.tap) loaded by the ROM as on a real Spectrum
(skoolkit tap2sna, LOAD "" simulated): the BASIC loader sets black (its
CLEAR clears the screen in black), loads the loading screen, which stays
intact while the CODE header is read (its "Bytes: " message goes nowhere)
and while the code loads, clears the screen in black and starts the game,
which reaches the main menu."""
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from harness import ROOT, z80_symbols  # noqa: E402
from loading_screen import screen_bytes  # noqa: E402
from skoolkit import tap2sna  # noqa: E402
from zx import Machine  # noqa: E402

ENTRY = 0x8000
SNAPSHOT = ROOT / 'build/loaded.z80'


def main():
    screen = screen_bytes()
    code = (ROOT / 'build/revs.bin').read_bytes()
    events = []
    fast_load = tap2sna.LoadTracer.fast_load

    def trace(tracer, sim):
        regs, mem = sim.registers, sim.memory
        flag, ix, length = regs[0], regs[8] << 8 | regs[9], regs[4] << 8 | regs[5]
        if flag == 255 and ix == 0x6000:               # the code block next
            assert bytes(mem[0x4000:0x5B00]) == screen, 'the CODE header printed over the screen'
            events.append('code header')
        if flag == 255 and ix == 0x4000:               # the screen next: CLEAR has
            assert not any(mem[0x5800:0x5AC0]), 'CLEAR clears the screen in black'   # cleared it
            events.append('black')                     # (black on black: the header's
                                                       # "Bytes: " stays invisible)
        done = fast_load(tracer, sim)
        if flag == 255 and ix == 0x4000 and length == 6912:
            assert bytes(mem[0x4000:0x5B00]) == screen
            events.append('screen')
        return done

    tap2sna.LoadTracer.fast_load = trace
    try:
        SNAPSHOT.unlink(missing_ok=True)
        # (relative paths: tap2sna takes 'C:' for a URL scheme)
        tap2sna.main(['--start', str(ENTRY), os.path.relpath(ROOT / 'output/revs.tap'),
                      os.path.relpath(SNAPSHOT)])
    finally:
        tap2sna.LoadTracer.fast_load = fast_load
    assert events == ['black', 'screen', 'code header'], events

    m = Machine(SNAPSHOT)
    assert m.reg[24] == ENTRY
    assert bytes(m.mem[0x6000:0x6000 + len(code)]) == code, 'code'
    assert not any(m.mem[0x4000:0x5800]), 'CLS before USR'
    assert not any(a & 0x38 for a in m.mem[0x5800:0x5B00]), 'black paper'   # (rows 22-23:
    assert not any(m.mem[0x5800:0x5AC0]), 'black ink'                       # BORDCR ink)
    assert m.mem[23624] & 0x38 == 0, 'black border (BORDCR)'
    m.run_until(z80_symbols()['UiMainMenu.m1'])
    print('loader: screen, code header, CLS, USR, main menu OK')


if __name__ == '__main__':
    main()
