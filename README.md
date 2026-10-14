# Revs for the ZX Spectrum 48K

A Spectrum-native conversion of Geoff Crammond's Formula 3 racing simulation
**Revs**. The driving model, the computer drivers and the race rules are the
Commodore 64 Revs+ code ported to the Z80. They are checked byte for byte
against the C64 code running in an emulator. The track renderer, the screen
layout and the memory use were designed for the Spectrum.

The game runs at the C64's pace: one simulation step every 0.13 s (6.5 TV
frames). Earlier ZX conversions of Revs managed 3.4–3.8 updates per second;
this one keeps up with the C64 in qualifying, and in the measured race start
at Silverstone with the whole field in view too (5.7 frames per step on
average, 6.2 at most).

## Features

* The complete C64 Revs+ simulation:
  * the driving model (tyres, grass, wings, engine, gears, slopes and jumps);
  * 19 computer drivers with overtaking;
  * contact, crashes, lap timing and race classes;
  * the Revs+ computer-assisted steering (CAS).
* All six tracks: Silverstone (in memory), plus Brands Hatch, Donington Park,
  Nürburgring, Oulton Park and Snetterton loaded from a second tape. Each
  extra track brings its own code, as on the C64.
* Practice and the Formula 3 championship:
  * the class: Novice, Amateur or Professional;
  * qualifying: 5, 10 or 20 minutes;
  * the race: 5, 10 or 20 laps;
  * grid positions, points, best laps and accumulated points;
  * results saved to and loaded from tape.
* A monochrome 3D view with dithered materials and no attribute clash. It is
  shown through a full-colour cockpit with:
  * wing mirrors;
  * a moving steering wheel;
  * a rev counter;
  * animated tyres;
  * starting lights.
* The HUD: lap times in practice and qualifying, the position and the
  nearest drivers in a race, and the speed in mph.
* Beeper sound: the engine, squealing tyres, impacts, gear changes and the
  starter.
* Keyboard, Sinclair joystick 1 or Kempston joystick.

## Playing

You need a ZX Spectrum 48K, or an emulator set to a 48K machine.

1. Load `output/revs.tap` with `LOAD ""`. The game starts in the main menu
   with Silverstone in memory.
2. To race on another track, choose it in the track menu. When the game asks
   (`REWIND TRACKS TAPE AND PRESS PLAY`), play `output/revs_tracks.tap`. The
   track in memory is marked with `*`, and choosing it again needs no
   loading.
3. `SAVE RESULTS` and `LOAD RESULTS` in the main menu keep the championship
   points on a tape of your own.

Always use the two tapes from the same build: the track code patches
addresses in the main program.

### Driving

| Key | Action |
| --- | --- |
| Q / A | throttle / brake |
| O / P | steer left / right (hold SPACE for faster manual steering) |
| W / S | gear up / down |
| X | hold the clutch |
| T | starter (hold until the engine runs) |
| C | computer-assisted steering (CAS) on/off |
| N | sound on/off |
| M | cars in the wing mirrors on/off |
| H | pause (H again to resume) |
| J | joystick type: Sinclair joystick 1 or Kempston |
| Caps Shift + 1 | the pits: change the wings (practice and qualifying, car stopped) |
| Caps Shift + 2 | end qualifying / retire from the race |
| Caps Shift + 3 | new game (the points and the name stay) |

Joystick controls:

* Up and Down are throttle and brake; Left and Right steer.
* Fire with Up changes up a gear; Fire without Up changes down.
* Sinclair joystick 1 uses keys 6–0. With Kempston selected, those keys are
  plain keys.

### Menus

* Number keys choose the options.
* ENTER confirms a number or a name; Caps Shift + 0 deletes.
* Symbol Shift + M types a full stop in the driver's name.
* SPACE continues from the information screens.
* BREAK (Caps Shift + SPACE) leaves the track menu or a tape transfer.

## Building

The game is built from `src/` alone, with [z88dk](https://z88dk.org/).
Nothing is generated or converted during the build.

1. Put z88dk's `bin` directory in `PATH`.
2. Run `build.bat` in the repository root.

Output:

* `output/revs.tap`: the BASIC loader, the loading screen and the game.
* `output/revs_tracks.tap`: the six tracks with their track code.
* `build/`: the binaries, the map, the listings and `revs.sna` (used by the
  tests).

`build.bat` is a Windows batch file. Its two commands (`z88dk-z80asm` with
the module list `src/revs.lst`, and `z88dk-appmake`) work the same way
elsewhere.

The literal data in `src/` (track files, projection tables, graphics) was
imported from the original games and from the artwork in `assets/`.
`python tools/gen_src.py` imports it again (for example after the artwork
changes). `tests/test_srcdata.py` checks that `src/` matches the originals.

## Testing

The tests need Python 3 with `py65`, `skoolkit` and `Pillow`, and a fresh
build. Tested with Python 3.14, py65 1.2, skoolkit 10.1 and Pillow 12.

```
python tests/test_physics.py          # one routine against the C64 code
python tests/test_lockstep.py 2000 1 race
python tests/test_soak.py 40000 1     # long random play, memory and crash checks
```

Most tests run a Z80 routine and the original C64 6502 routine on the same
random states and compare the results byte for byte. `test_lockstep.py` runs
both complete main loops side by side, whole sessions included. Other tests
play the whole game in an emulated Spectrum. See [TECHNICAL.md](TECHNICAL.md)
for the complete list.

## Repository layout

| Path | Contents |
| --- | --- |
| `src/` | Z80 sources and literal data: everything the build needs |
| `src/gfx/` | binary graphics: cockpit, gear glyphs, loading screen |
| `assets/` | originals the data was imported from: C64 Revs+ tape and extracted code, BBC source excerpts, cockpit and loading screen artwork |
| `tools/` | import tools (C64/BBC data, tables, cockpit code), C64 disassembler, Spectrum emulator harness |
| `tests/` | differential, lockstep and whole-game tests |
| `docs/design.md` | design notes: screen, memory, rendering, game flow |
| `notes/` | C64 memory map and labels, BBC symbols, the extra tracks' code patches |
| `build.bat` | the build |
| `output/` | the two tapes |

## How it was made

The conversion was written in two days in October 2026 by ataribaby,
working with Claude Code (Anthropic's Claude Opus 5.5) as a pair
programmer. Every routine was ported from the C64 code with the annotated
BBC Micro source as a guide, and tested against the original before the next
step. [TECHNICAL.md](TECHNICAL.md) describes the process, the architecture,
the verification and the performance work in detail.

## Credits

* **Revs** was designed and written by Geoff Crammond (BBC Micro, Acornsoft,
  1985). This conversion follows the Commodore 64 **Revs+**.
* Mark Moxon's fully annotated BBC Micro source of Revs
  ([revs.bbcelite.com](https://revs.bbcelite.com),
  [GitHub](https://github.com/markmoxon/revs-source-code-bbc-micro)) made it
  possible to understand the code.
* The cockpit, loading screen, menus, sounds and controls come from
  ataribaby's earlier ZX Spectrum versions
  ([revs-zx-spectrum](https://github.com/ataribaby42/revs-zx-spectrum)).

Revs is the work of its original author and publishers. This is a
non-commercial fan conversion for preservation and study.
