"""ReadKeys with Sinclair joystick 1 (keys 6-0) or a Kempston joystick (port
$1F, chosen with J) and the gear change / starter sounds, as in the user's
ZX version.

Joystick: Up / Down = Q / A, Left / Right = O / P, Fire with Up = W, Fire
without Up = S; the keyboard keys stay active alongside. With Kempston the
keys 6-0 are plain keys, and a port reading with bit 7 set (no interface)
adds nothing. J toggles the type once per press and shows "Sinclair" or
"Kempston".
"""
import itertools
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).parent.parent / 'tools'))
from harness import Z80
from zx import KEYMAP, Ports

z = Z80()
ports = Ports()
z.sim.set_tracer(ports)

JOY = ['0', '9', '8', '7', '6']              # fire, up, down, right, left
KEMPSTON = ['right', 'left', 'down', 'up', 'fire']   # port $1F bits 0-4


def rows_for(keys):
    rows = [0] * 8
    for k in keys:
        r, b = KEYMAP[k]
        rows[r] |= 1 << b
    return rows


def expected(keys, kempston=None):
    keys = set(keys)
    if kempston is None:
        fire, up, down, right, left = (k in keys for k in JOY)
    else:
        bits = kempston if kempston < 0x80 else 0
        right, left, down, up, fire = (bool(bits & (1 << i)) for i in range(5))
    if up:
        keys.add('Q')
    if down:
        keys.add('A')
    if left:
        keys.add('O')
    if right:
        keys.add('P')
    if fire and up:
        keys.add('W')
    if fire and not up:
        keys.add('S')
    return rows_for(keys)


errors = 0
cases = 0
z.set('joystickType', 0)
for n in range(32):
    joy = [JOY[i] for i in range(5) if n & (1 << i)]
    for extra in ([], ['Q'], ['S', 'O'], ['W', 'A', 'P', 'T', 'SPACE']):
        keys = joy + extra
        ports.keyboard = rows_for(keys)
        ports.kempston = (None, 0x1F, 0x0A)[cases % 3]      # (not read)
        z.call('ReadKeys')
        got = z.get('keyRows', 8)
        cases += 1
        if got != expected(keys):
            errors += 1
            if errors < 10:
                print('ReadKeys', keys, 'got', got, 'expected', expected(keys))
print(f'ReadKeys Sinclair joystick: {errors}/{cases}')

k_errors = 0
k_cases = 0
z.set('joystickType', 1)
for port in list(range(32)) + [0xFF, 0x80, 0x9F, None]:
    for extra in ([], ['Q'], ['S', 'O'], ['W', 'A', 'P', 'T', 'SPACE'], ['9', '0'], JOY + ['A']):
        ports.keyboard = rows_for(extra)
        ports.kempston = port
        z.call('ReadKeys')
        got = z.get('keyRows', 8)
        want = expected(extra, 0xFF if port is None else port)
        k_cases += 1
        if got != want:
            k_errors += 1
            if k_errors < 10:
                bits = [KEMPSTON[i] for i in range(5) if port is not None and port & (1 << i)]
                print('ReadKeys Kempston', port, bits, extra, 'got', got, 'expected', want)
print(f'ReadKeys Kempston joystick: {k_errors}/{k_cases}')
errors += k_errors
ports.kempston = None

# J: one toggle per press, with the notice
HUD = [0x4000 + line * 256 + i for line in range(8) for i in range(64)] + list(range(0x5800, 0x5840))


def hud():
    return [z.mem[a] for a in HUD]


def notice(text):
    z.call('ShowNotice', hl=z.sym(text))
    return hud()


want_k, want_s = notice('noticeKempston'), notice('noticeSinclair')
j_errors = 0
z.set('joystickType', 0)
z.set('keyLatchJ', 0)
for step, (keys, joy, screen) in enumerate((
        (['J'], 1, want_k),             # press: Kempston
        (['J'], 1, None),               # held: no change
        ([], 1, None),                  # released
        (['J', 'Q'], 0, want_s),        # press again: Sinclair
        ([], 0, None),
        (['J'], 1, want_k))):
    z.mem[HUD[0]] ^= 0xFF               # (a notice redraws the HUD rows)
    before = hud()
    ports.keyboard = rows_for(keys)
    z.call('ReadKeys')
    z.call('ControlKeys')
    got = z.get('joystickType')[0]
    shown = hud()
    if got != joy or shown != (screen if screen else before):
        j_errors += 1
        print('J step', step, keys, 'joystickType', got, 'expected', joy,
              'notice', 'ok' if shown == (screen if screen else before) else 'wrong')
z.set('joystickType', 0)
print(f'J toggle: {j_errors} errors')
errors += j_errors

# gear change: a frame of noise on a new gear, none when the gear stays
gear_errors = 0
for gear, key, noise in itertools.product(range(7), ('W', 'S'), (0, 5)):
    z.set('gearNumber', gear)
    z.set('gearChange', 0)
    z.set('noiseFrames', noise)
    z.set('leaveTrackTimer', 0)
    z.set('casOn', 0)
    ports.keyboard = rows_for([key])
    z.call('ReadKeys')
    z.call('ProcessDrivingKeys')
    new = min(6, max(0, gear + (1 if key == 'W' else -1)))
    want = noise if noise or new == gear else 1
    got = z.get('gearNumber')[0], z.get('noiseFrames')[0]
    if got != (new, want):
        gear_errors += 1
        print('gear', gear, key, 'noise', noise, 'got', got, 'expected', (new, want))
print(f'gear change sound: {gear_errors} errors')

# starter: pops only while starterFrames runs, the engine is off and T is held
starter_errors = 0
z.set('soundOn', 1)
z.set('noiseFrames', 0)
z.set('tyreSqueal', [0, 0])
for engine, t_held in ((0, True), (0, False), (0xFF, True)):
    z.set('engineStatus', engine)
    z.set('revCount', 0)
    pops = 0
    for frame in range(64):
        z.set('starterFrames', 7)
        z.set('soundLive', 12)              # (the main loop runs)
        ports.keyboard = rows_for(['T'] if t_held else [])
        ports.beeper = []
        z.call('SoundTick')
        if engine == 0 and ports.beeper:
            pops += 1
            if len(ports.beeper) != 6:
                starter_errors += 1
    want_pops = engine == 0 and t_held
    if want_pops != (pops > 0) or (want_pops and not 4 <= pops <= 16):
        starter_errors += 1
    print(f'starter engine {engine:02x} T {t_held}: {pops} pops in 64 frames')
z.set('engineStatus', 0)
z.set('starterFrames', 0)
ports.keyboard = rows_for(['T'])
ports.beeper = []
for frame in range(64):
    z.set('soundLive', 12)
    z.call('SoundTick')
if ports.beeper:
    starter_errors += 1
    print('starter sound without the simulation cranking')
print(f'starter sound: {starter_errors} errors')

sys.exit(1 if errors or gear_errors or starter_errors else 0)
