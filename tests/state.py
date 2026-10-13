"""Map of the game state between the C64 image and the Z80 build.

Each entry: (name, C64 address, Z80 symbol, Z80 offset, length). Used to
randomise both machines identically and to compare them after a call.
"""

# Zero page: BBC/C64 $02-$8F live at ZP+offset; C64 $90/$91 = ZP+0/1
ZP_IGNORE = {0x64, 0x69, 0x6b}       # printMode, lineBufferSize, startingStack


def zp_entries():
    out = []
    for off in range(0x90):
        if off in ZP_IGNORE:
            continue
        c64 = 0x90 + off if off < 2 else off
        out.append((f'zp{off:02x}', c64, 'ZP', off, 1))
    return out


BLK62 = [
    ('xPlayerCoordLo', 0x66f1, 'playerCoordX', 0, 1), ('xPlayerCoordHi', 0x66c0, 'playerCoordX', 1, 1),
    ('xPlayerCoordTop', 0x66c3, 'playerCoordX', 2, 1),
    ('yPlayerCoordLo', 0x66f2, 'playerCoordY', 0, 1), ('yPlayerCoordHi', 0x66c1, 'playerCoordY', 1, 1),
    ('yPlayerCoordTop', 0x66c4, 'playerCoordY', 2, 1),
    ('zPlayerCoordLo', 0x66f3, 'playerCoordZ', 0, 1), ('zPlayerCoordHi', 0x66c2, 'playerCoordZ', 1, 1),
    ('zPlayerCoordTop', 0x66c5, 'playerCoordZ', 2, 1),
    ('xRoadSignCoordLo', 0x66c6, 'roadSignCoordX', 0, 1), ('xRoadSignCoordHi', 0x66c9, 'roadSignCoordX', 1, 1),
    ('yRoadSignCoordLo', 0x66c7, 'roadSignCoordY', 0, 1), ('yRoadSignCoordHi', 0x66ca, 'roadSignCoordY', 1, 1),
    ('zRoadSignCoordLo', 0x66c8, 'roadSignCoordZ', 0, 1), ('zRoadSignCoordHi', 0x66cb, 'roadSignCoordZ', 1, 1),
    ('objectPalette', 0x66cf, 'objectPalette', 0, 4), ('mirrorContents', 0x66d3, 'mirrorContents', 0, 6),
    ('markerData', 0x66d9, 'markerData', 0, 3), ('vergeEdgeRight', 0x66dc, 'vergeEdgeRight', 0, 4),
    ('sincos', 0x66e0, 'sinYawAngleLo', 0, 6), ('tyreSqueal', 0x66e6, 'tyreSqueal', 0, 2),
    ('wingSetting', 0x66e8, 'wingSetting', 0, 2), ('wingForce', 0x66ea, 'wingForce', 0, 2),
    ('wingForce95', 0x66ec, 'wingForce95', 0, 2), ('physLo', 0x66ee, 'physLo', 0, 3),
    ('markerListIndex', 0x66f4, 'markerListIndex', 0, 3), ('xMarkerLo', 0x66f7, 'xMarkerLo', 0, 3),
    ('xMarkerHi', 0x66fa, 'xMarkerHi', 0, 3),
    ('physHi', 0x6710, 'physHi', 0, 16), ('physTop', 0x6720, 'physTop', 0, 16),
    ('liftFromTorque', 0x6730, 'liftFromTorque', 0, 1), ('wingBalance', 0x6731, 'wingBalance', 0, 1),
    ('playerSideways', 0x6732, 'playerSideways', 0, 1), ('thisObjectType', 0x6733, 'thisObjectType', 0, 1),
    ('thisDriverNumber', 0x6734, 'thisDriverNumber', 0, 1),
    ('newSectionFetched', 0x6735, 'newSectionFetched', 0, 1),
    ('crashedIntoFence', 0x6736, 'crashedIntoFence', 0, 1), ('updateLapTimes', 0x6738, 'updateLapTimes', 0, 1),
    ('previousSignNumber', 0x6739, 'previousSignNumber', 0, 1), ('tyreTravel', 0x673a, 'tyreTravel', 0, 1),
    ('playerDrift', 0x673b, 'playerDrift', 0, 1), ('horizonTrackWidth', 0x673c, 'horizonTrackWidth', 0, 1),
    ('lowestTrackLine', 0x673d, 'lowestTrackLine', 0, 1), ('updateDriverInfo', 0x673e, 'updateDriverInfo', 0, 1),
    ('zTyreForceBoth', 0x673f, 'zTyreForceBoth', 0, 1),
]

OBJECTS = [
    ('objectStatus', 0x018c, 'OBJ_STATUS', 0, 24), ('objYawAngleLo', 0x8580, 'OBJ_YAWLO', 0, 24),
    ('objYawAngleHi', 0x8598, 'OBJ_YAWHI', 0, 24), ('objectPitchAngle', 0x85b0, 'OBJ_PITCH', 0, 24),
    ('objectSize', 0x85c8, 'OBJ_SIZE', 0, 24), ('objTrackSection', 0x88e8, 'OBJ_SECTION', 0, 24),
    ('objSectionSegmt', 0x0880, 'OBJ_SEGMT', 0, 24), ('objectSegmentLo', 0x08d0, 'OBJ_SEGLO', 0, 24),
    ('objectSegmentHi', 0x08e8, 'OBJ_SEGHI', 0, 24),
]

CARS = [
    ('carStatus', 0x0100, 'CAR_STATUS', 0, 20), ('carSteering', 0x0114, 'CAR_STEERING', 0, 20),
    ('driverSpeed', 0x0128, 'DRIVER_SPEED', 0, 20), ('driversInOrder', 0x013c, 'DRIVERS_IN_ORDER', 0, 20),
    ('carSpeedHi', 0x0150, 'CAR_SPEEDHI', 0, 20), ('carProgress', 0x0164, 'CAR_PROGRESS', 0, 20),
    ('carRacingLine', 0x0178, 'CAR_RACINGLINE', 0, 20), ('carSectionSpeed', 0x01a4, 'CAR_SECTIONSPEED', 0, 20),
    ('carSpeedLo', 0x3850, 'CAR_SPEEDLO', 0, 20), ('driverGridRow', 0x86a0, 'DRIVER_GRIDROW', 0, 20),
    ('driverLapNumber', 0x86b4, 'DRIVER_LAPNUMBER', 0, 20),
    ('totalRaceMinutes', 0x86dc, 'TOTAL_RACE_MINUTES', 0, 20),
]

DRIVERS = [
    ('totalPointsLo', 0x3864, 'TOTAL_POINTS_LO', 0, 20), ('totalPointsHi', 0x39e4, 'TOTAL_POINTS_HI', 0, 20),
    ('totalPointsTop', 0x86f0, 'TOTAL_POINTS_TOP', 0, 20),
    ('bestLapTenths', 0x88a0, 'BEST_LAP_TENTHS', 0, 24), ('bestLapSeconds', 0x88b8, 'BEST_LAP_SECONDS', 0, 24),
    ('bestLapMinutes', 0x88d0, 'BEST_LAP_MINUTES', 0, 24),
    ('totalRaceTenths', 0x0898, 'TOTAL_RACE_TENTHS', 0, 20),
    ('totalRaceSeconds', 0x08ac, 'TOTAL_RACE_SECONDS', 0, 20),
    ('driversInOrder2', 0x86c8, 'DRIVERS_IN_ORDER2', 0, 20),
]

MISC = [
    ('raceClass', 0x84fa, 'raceClass', 0, 1), ('qualifyingTime', 0x84fb, 'qualifyingTime', 0, 1),
    ('baseSpeed', 0x8500, 'baseSpeed', 0, 1), ('frontWingSetting', 0x84fd, 'frontWingSetting', 0, 1),
    ('rearWingSetting', 0x84fe, 'rearWingSetting', 0, 1), ('sectionSteering', 0x8520, 'sectionSteering', 0, 40),
]

SEGMENTS = [
    ('segLo', 0x0900, 'SEG_LO', 0, 256), ('segHi', 0x0a00, 'SEG_HI', 0, 256),
    ('segData', 0x8900, 'SEGDATA', 0, 120),
]


def all_entries(segments=True):
    e = zp_entries() + BLK62 + OBJECTS + CARS + DRIVERS + MISC
    return e + SEGMENTS if segments else e


def z80_addr(z, sym, off):
    return z.sym(sym) + off


def put(c64, z, entry, values):
    name, ca, zs, off, n = entry
    base = z80_addr(z, zs, off)
    for i, v in enumerate(values[:n]):
        c64.mem[ca + i] = v
        z.mem[base + i] = v


def randomise(c64, z, rng, entries):
    for e in entries:
        put(c64, z, e, [rng.randrange(256) for _ in range(e[4])])


def find(name, entries=None):
    for e in entries or all_entries():
        if e[0] == name:
            return e
    raise KeyError(name)


def zp(name):
    """Entry for a BBC zero-page variable by C64 address name (from harness)."""
    raise NotImplementedError


def diff(c64, z, entries, ignore=()):
    errs = []
    for name, ca, zs, off, n in entries:
        if name in ignore:
            continue
        a = list(c64.mem[ca:ca + n])
        base = z80_addr(z, zs, off)
        b = [z.mem[base + i] for i in range(n)]
        if a != b:
            if n == 1:
                errs.append(f'{name}: C64 {a[0]} Z80 {b[0]}')
            else:
                idx = [i for i in range(n) if a[i] != b[i]]
                errs.append(f'{name}[{idx[:6]}]: C64 {[a[i] for i in idx[:6]]} Z80 {[b[i] for i in idx[:6]]}')
    return errs
