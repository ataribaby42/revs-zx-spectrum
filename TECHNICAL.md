# How Revs was converted to the ZX Spectrum 48K

This document describes how this conversion was made:

* the goals;
* the sources it is based on;
* the way the work was organised and verified;
* the architecture of the Spectrum program;
* the performance work;
* the deviations from the original;
* the bugs found on the way;
* the build.

`docs/design.md` is the reference for the details of the current design.

## 1. Goals and starting point

ataribaby had already converted Revs to the Spectrum twice
([revs-zx-spectrum](https://github.com/ataribaby42/revs-zx-spectrum) and
revs-zx-spectrum-c64-rate). Both followed the original closely and played
correctly, but both translated the BBC Micro 6502 code nearly instruction by
instruction. That reached only 3.4–3.8 updates per second (about 925,000
T-states per update). Revs needs about twice that speed to feel like the
original.

This third version started from scratch with these requirements:

* **Speed:** the C64 time step. The C64 version advances the game clock by
  0.13 s per main-loop iteration (the BBC by 0.09 s), so the game needs about
  7.7 updates per second. That is 6.5 TV frames, or about 450,000 T-states,
  per update.
* **Faithful simulation:** the C64 code defines the 0.13 s calibration, so
  the simulation follows the C64 version exactly:
  * the same fixed-point widths;
  * the same rounding;
  * the same update order;
  * the same random number use.
* **A native Z80 design:** the routines are re-expressed with Z80 idioms,
  not translated from 6502 line by line.
* **A Spectrum screen without attribute clash in the 3D view.**
* **Nothing taken on trust:** the earlier versions were used as a feature
  specification only. Every routine was verified independently against the
  original.
* **The look and feel of ataribaby's version:**
  * the repainted cockpit;
  * the menus and the championship screens;
  * the controls, the sounds, the starting lights and the loading screen.

The first milestone was a playable prototype: Novice class, Silverstone, 5
minutes of qualifying and a 5-lap race. It grew into the complete game:
all six tracks, practice, the championship and results on tape.

## 2. Sources

| Source | Used for |
| --- | --- |
| Mark Moxon's annotated BBC Micro source and the deep-dive articles ([revs.bbcelite.com](https://revs.bbcelite.com)) | what the code means: names, comments, algorithms. The variable and routine names of the port are the BBC names, so the Z80 code can be read side by side with the annotations. |
| The C64 Revs+ tape (`assets/c64/Revs+_cleaned.tap`) | the reference behaviour: the 6502 code that the port must match, and the data (track files, projection tables, driver names) |
| ataribaby's ZX versions | the specification of the menus, screens, texts, colours, keys, sounds, cockpit and loading screen artwork |

**Why the C64 code is the reference.** The C64 code is the BBC code with
modifications. It has other constants for the 0.13 s step, logarithmic
projection tables instead of divisions, and the Revs+ additions. The Revs+
installer (in the track selector, copied to `$9C00`) patches the main game:

* the computer-assisted steering (CAS);
* a different steering centring;
* a drift guard in `MovePlayerSegment`.

`tools/c64_image.py` builds the C64 memory image from the parts of the tape
(`assets/c64/*.bin`, extracted once by `tools/c64_extract.py`). It runs the
installer and the track hook, so the reference is the game exactly as a C64
player gets it.

**The C64 map.** The C64 code has no symbols. Its routines and variables were
found by matching them with the BBC routines. The results are in:

* `notes/c64-map.txt`: the BBC routines at their C64 addresses;
* `notes/c64-labels.txt`: the labels that the disassembler and the test
  harness use;
* `notes/bbc-symbols.txt`: the BBC zero page layout.

The one-off analysis tools that produced these files (BBC listing
extractors, a BBC-to-C64 routine matcher and differ) are in the git history
before commit `69f8a12`. The speed-measuring tools are there before
`4c4b6ae`.

**Runtime-generated C64 routines.** Some C64 routines in page 3
(`ShowStartingLights`, `PrintTimer`, `DrawTrackView` and one unknown routine)
are generated at run time and are not in the tape image.
`ShowStartingLights` was reassembled from the fragments left in memory, with
the same layout and constants. The others are display routines, and the
tests replace them with stubs.

## 3. How the work was done

The conversion was written in October 2026 by ataribaby working with
**Claude Code** (Anthropic's Claude Opus 5.5). Claude Code read the
references, wrote the Z80 code, the tools and the tests, and ran them.
ataribaby set the goals and supplied the material, made the design
decisions, played the builds in an emulator and reported what was wrong or
missing.

The working rules were:

1. **No routine without a test against the original.** Each ported routine
   gets a differential test (section 5). That test runs the C64 6502 routine
   and the Z80 routine on the same random states and compares the results
   byte for byte. A routine counts as done only when they agree.
2. **Commit after every verified step.** The history has about 85 small
   commits, each with the build and the tests passing. When an optimisation
   changes code, the same tests confirm that the results are still identical.
3. **The user decides matters of taste.** Examples:
   * The horizontal scale was settled by laying builds at 1.625, 1.75 and
     2.0 pixels per C64 pixel over a C64 screenshot. 1.75 matched best.
   * The cockpit is ataribaby's repainted version, not the original export.
   * The crash crane was removed.
   * The menus are copied exactly from the earlier version.
   * The Kempston option was added on request.
4. **Deviations are explicit.** Where the port intentionally differs from
   the C64, the same change is applied to the C64 reference
   (`APPROVED_PATCHES` in `tools/c64_image.py`). The tests then keep checking
   everything else.
5. **Reviews on request get a test.** When ataribaby asked for a check (the
   wings, the difficulty, the physics and AI, the sound, "nothing overwrites
   anything"), the answer was a new automated test, not a reading of the
   code. Several of these tests found real bugs (section 8).

### Timeline

| When | What |
| --- | --- |
| 12 Oct, 16:30–17:15 | Project skeleton, the two-machine test harness, the track segment buffer, the C64 logarithmic projection and the verges, all verified against the C64. A first track renderer (edges, compositor, view copy). |
| 12 Oct, 17:15–18:35 | The simulation, routine by routine with differential tests: the driving model, player movement, drivers and speeds, race set-up, laps and timers, the AI (`MoveCars`, `ProcessOvertaking`), the car objects, the race logic (lights, signs, contact, crashes, finish). Then the main driving loop and the lockstep test of the whole loop against the C64. |
| 12 Oct, 18:35–21:50 | Rendering and speed: the object renderer, dithered materials, the HUD, beeper sound, tyre animation and steering wheel. The horizontal scale was chosen; the faster `Compose`, `BuildEdges` and car drawing followed, plus a second hot code area and register-based multiplications. Wing mirrors were added. |
| 12 Oct, 21:50–23:40 | The look and feel of ataribaby's version: the controls (clutch, CAS, sound, mirrors, pause), the HUD and notices, the Sinclair joystick, the gear and starter sounds, the starting lights, the CRASHED notice, no crane, the procedural fence. Then the memory was reorganised for the menus. |
| 13 Oct, 00:00–01:50 | The menus, the championship and the tape transfers. The extra tracks: their track code ported from the C64 track files, with patch lists. |
| 13 Oct, 09:40–14:20 | Play-testing and review requests, each answered with a test and a fix (section 8). The game was made to build from `src/` only, moved to z88dk with a BASIC loader assembled from source, and the soak test was added. The Kempston joystick came last. |

## 4. Architecture

### Memory map

| Address | Contents |
| --- | --- |
| `$4000-$5AFF` | Screen. While driving, character rows 2–9 (the "hidden sky", attributes ink = paper) hold 2 KiB of the UI overlay. |
| `$5B00-$5EFF` | The last KiB of the UI overlay while driving. The BASIC area and system variables are dead once the game runs. |
| `$5F00-$5FFF` | Free in every phase. |
| `$6000-$7FFF` | Contended memory: the cockpit bitmap and the cold code (set-up, game flow, HUD, controls), which runs once per session or rarely. |
| `$8000-$BFFF` | Hot code and variables. `ZPAGE` mirrors the BBC zero page `$00-$8F` byte for byte (`src/zp.asm`, generated from the BBC symbols), so routines that clear or reuse ranges of it behave exactly like the original. |
| `$C000-$C7FF` | The track file (the C64 layout), one at a time. |
| `$C800-$F7FF` | Page-aligned tables: segment buffer, verges, objects, cars, the C64 projection tables, the view buffer, edge tables, yaw-to-x conversion, masks, quarter squares, driver times. |
| `$E200-$EDFF` | The view buffer and edge pages while driving. The UI overlay runs here between sessions. |
| `$F800-$FBFF` | Second hot code area (race logic, object tables). |
| `$FC00` | Object line buffers. The stack sits below `$FD60`. |
| `$FD60-$FFF3` | The track code of an extra track (660 bytes at most). |
| `$FFF4-$FFFF` | The interrupt vector. |

The rules behind the layout:

* **Everything executed per frame lives in uncontended memory.**
* **Per-car and per-object arrays are page-aligned**, so H selects the table
  and L the index. The 6502's `X` index usually becomes `C`, and `Y` becomes
  `B`.
* **The interrupt vector uses no table.** I = `$39`, where the ROM holds
  `$FF` bytes, so the IM2 vector is `$FFFF`. The byte there is `JR`, and its
  offset is the ROM's first byte (`$F3`, i.e. -13), which lands on `JP Isr`
  at `$FFF4`. This frees a 257-byte vector table.
* **The UI overlay** (`src/ui.asm`: menus, championship tables, tape
  transfers, up to 3 KiB) shares memory with the view buffer. When driving
  starts, `StoreUI` moves it into the hidden sky and `$5B00`. When driving
  ends, `LoadUI` brings it back, so its variables (the results, the choices,
  the track in memory) survive.

### Main loop and timing

`MainDrivingLoop` follows the C64 `MainDrivingLoop` (`$B202`) call for call.
The C64 display routines are replaced by the Spectrum renderer and HUD.

Each iteration runs, in order:

1. Time and keys.
2. The driving model.
3. The track and the player's movement.
4. The edges, `Compose`, the objects, the mirrors.
5. Contact and crash checks.
6. `FramePace`.

`FramePace` holds an iteration to 6.5 TV frames, so the game runs in C64
real time whenever the frame is fast enough. When an iteration takes longer,
the game slows down rather than skipping.

The 50 Hz interrupt (`src/isr.asm`) does three jobs:

* It copies a finished view buffer to the screen at the start of the next TV
  frame, before the beam reaches the view, so the view never tears.
* It animates the tyre tread.
* It plays the sound.

### Screen

```
y   0..15   two HUD text rows (ROM font, black on white)
y  16..81   static sky band (the hidden sky: data storage while driving)
y  82..161  track view, 80 rows = 80 BBC track lines
y 115..191  cockpit (256 x 77, the user's artwork); its transparent pixels
            show the view, rows 152..161 of the view are hidden
```

The view is monochrome (ink black, paper white), and so is every cell that
contains view pixels, so there is no attribute clash. Materials are dither
patterns:

* sky and white verge: paper;
* road and black verge: solid ink;
* grass: a 25% pattern;
* red kerb: a 50% pattern.

Colour appears only in cells that never show the view: the HUD, the sky
band, the opaque cockpit cells and the starting lights.

**Horizontal scale.** The C64 view is 160 multicolour pixels across, 4 per
yaw unit. The Spectrum draws 1.75 pixels per C64 pixel (the PAL aspect of
C64 pixels): x = 128 + yaw × 7, a field of view of ±18.3 yaw units.

**Vertical scale.** One BBC track line is one Spectrum row. The horizon sits
as far above the cockpit cowl as on the C64.

### The renderer

The renderer has its own Spectrum design. Only the projection and the
choice of what is visible are the original's.

1. **Projection** (`proj.asm`, `proj_code.asm`). This is the C64
   logarithmic projection, ported exactly: a 16-bit value is reduced to an
   8-bit mantissa and an exponent, and the ratio of two values comes from log
   and exponential tables copied from the C64. The yaw and pitch angles are
   the ones the simulation uses too.
2. **Verges** (`verges.asm`). The C64 `GetTrackAndMarkers` fills the verge
   buffer: up to 40 points per side.
3. **Edges** (`render.asm`, `raster.asm`). The four verge edges are
   polylines through the verge points, drawn far to near. Each segment is
   stepped one track line at a time, and its x position is stored per line,
   so nearer segments overwrite farther ones and hide the track behind
   crests. The colour tables are filled with `PUSH`. Line-step code is
   patched only when it changes. A segment whose last part is flat or rising
   is extended to the bottom of the view (`RasterTail`). Lines hidden behind
   the cockpit are not rasterised at all.
4. **Compose** (`compose.asm`). Each track line becomes one 32-byte row of
   the view buffer: grass | verge | road | verge | grass, or sky. Whole bytes
   are written by jumping into an unrolled chain of `ld (hl),b / inc l` that
   returns through `JP (IY)`. Only the boundary bytes are merged, with masks
   from a 256-entry table indexed by x. Unchanged sky rows are neither
   composed nor copied.
5. **Objects** (`objdraw.asm`). Cars, signs and corner markers use the
   original part definitions (scaffolds) and the BBC scaling (sums of
   `scaleUp >> n`), at 13/16 horizontally for the Spectrum scale. Each part
   is drawn into a line buffer as a left edge, a fill and a right edge with
   the material's patterns, clipped against the terrain line, then blitted.
   The scaffold measurements are pre-decoded into pairs of table entries, and
   the rounding and size checks are patched into the code per object.
6. **View copy** (`viewcopy.asm`, generated by `tools/gen_cockpit.py` from
   the cockpit artwork). An unrolled copy of the buffer to the screen. Rows
   behind transparent cockpit pixels get generated mask code that merges
   only the bytes that need it.

**Grass under the tyres.** The original physics reads the grass contacts
from its own screen memory: two bytes of track line 10. The Spectrum screen
holds dithered pixels, so `CheckSurfaces` derives the same answer from the
edge tables, exactly as `Compose` draws that line.

**Wing mirrors** use the BBC logic: the car behind, as a block in one of
three segments per mirror. They are drawn on the real mirror glass of the
cockpit artwork (rows 148–168). While the engine runs, the mirror car
shudders with random pixels (ROM bytes ANDed with the R register).

### The simulation

The simulation is ported routine by routine from the C64 code:

* `physics.asm` and `physics2.asm`: the driving model;
* `player.asm`, `track.asm`, `verges.asm`: the player's controls and
  movement along the track;
* `drivers.asm` and `ai.asm`: the computer drivers;
* `setup.asm`, `laps.asm`, `race.asm`: set-up, laps, timers and the race
  logic;
* `objects.asm`: the car objects.

Conventions:

* **Names:** the BBC names, with the C64 semantics.
* **Physics block access:** `IX` points into the block; `(IX+0)` is the low
  byte and `(IX+16)` the high byte.
* **Object and driver entries:** reached through `IX` and `IY` with the
  `OBJ_INDEX` and `CAR_INDEX` macros.
* **Numbers:** 16-bit quantities are little-endian, processed in register
  pairs. Times are BCD, as in the original.
* **Random numbers:** a 16-bit xorshift (`Random`) replaces the C64's CIA
  timer reads. The tests feed both machines the same byte sequence.

**Multiplication** uses quarter squares: a×b = ⌊(a+b)²/4⌋ − ⌊(a−b)²/4⌋, from
a 512-entry table in four pages. The BBC `Multiply16x16` used by the driving
model is rewritten as `q·S + (q·R + p·S + 128) / 256` with three
quarter-square products in registers. The results are identical, and the
driving model dropped from 44,300 to 37,100 T-states per iteration.
`BuildCarObjects` keeps the car's position in registers as well (28,800 to
23,000 T-states mid-race).

### Extra tracks

Five of the six C64 track files contain code. The Revs+ installer ends by
calling the track hook (`$5A30`). For Silverstone this is an `RTS`. For the
other tracks it runs `ModifyGameCode`, which patches about 42 bytes of the
main game with calls into the track file:

* dynamic segment vectors built from sub-sections;
* the horizon and field of view over crests;
* moved steering and sign tables;
* the slope jump;
* the hairpin sign;
* a different AI brake distance;
* no car height cap on the Nürburgring.

The port keeps that split:

* **The track code.** `src/trackcode.asm` holds Z80 versions of the track
  routines and a patch list (length, address, new bytes, old bytes). It is
  assembled once per track, with that track's constants, in the track's own
  module (`src/track_<track>.asm`), and linked against the main program's
  symbols (`src/tracklink.asm`).
* **The tracks tape.** Each track file (for `$C000`) and its track code (for
  `$FD60`) travel together on the tracks tape.
* **Applying and undoing.** After a load, `TcLoaded` applies the patch list.
  Before another track loads, `TcReset` restores the main program exactly.
  The patched places are marked `@tc…` in the main code.

The largest track code (Nürburgring) uses 658 of its 660 bytes.

`notes/extra-tracks.md` lists every C64 patch. Three patches have no
Spectrum counterpart and were not ported:

* the joystick path;
* the background colour table;
* the off-screen verge flag.

### Sound

All sound is played on the beeper from the interrupt, once per TV frame:

* **Engine:** 1 + revs/32 clicks per frame, more closely spaced as the revs
  rise.
* **Tyres:** random clicks while they squeal.
* **Noise bursts:** for impacts and gear changes.
* **Starter:** sparse pops while T cranks the engine.

Every main-loop iteration refreshes a 12-frame `soundLive` counter, so the
engine and tyres fall silent as soon as the game stands (menus, pits, pause,
crash).

### HUD and notices

The two HUD rows use the ROM font. They show:

* timers in practice and qualifying;
* the position, the laps and the nearest drivers in a race.

Notices cover both rows: the sound, mirrors and joystick notices for half a
second, PAUSED and CRASHED for as long as they last. Afterwards `RedrawHud`
prints the rows again from the game state, so no text buffer is needed.

### Tapes

**The game tape:** ataribaby's BASIC loader, the loading screen and the code.
The loader (`src/loader.asm`) is assembled from source as the two finished
TAP blocks:

* the BASIC line as tokens, with the numbers in their five-byte form;
* the lengths and checksums computed by the assembler.

The line is:

```
10 BORDER 0: PAPER 0: INK 0: CLEAR VAL "24575": BORDER 0:
   LOAD "" SCREEN$: POKE VAL "23739",VAL "111": LOAD "" CODE: CLS:
   RANDOMIZE USR VAL "32768"
```

The POKE redirects the "Bytes:" message of the CODE header to a ROM `RET`,
so it does not print over the picture.

**The tracks tape:** CODE blocks named after each track.

**Results:** a 76-byte record ("RC", version 1, the name, 20 × 3 BCD scores)
saved as `REVSRESULT`. A loaded record is checked before it is used.

**Tape routines:** all transfers call the ROM `LD-BYTES` and `SA-BYTES`, so
BREAK returns to the menus.

## 5. Verification

There are three layers of tests. All of them are in `tests/` and use two
emulators:

* **py65** runs the C64 6502 code;
* **skoolkit** runs the Spectrum build: single routines, or the whole
  machine with contended memory and interrupts (`tools/zx.py`).

### Differential tests (routine level)

`tests/harness.py` loads the C64 image and the built Spectrum snapshot. It
calls a routine on either machine by address or symbol, and maps variables
between them by their BBC names. `tests/state.py` maps the whole game state
(each variable's C64 address, Z80 symbol and length). The tests use it to
write the same random state into both machines, run the C64 routine and the
Z80 routine, and compare every mapped byte.

| Test | Covers |
| --- | --- |
| `test_track.py` | segment buffer, `GetTrackSegment` and friends |
| `test_proj.py` | the logarithmic projection (20,000 cases) |
| `test_verges.py` | `GetTrackAndMarkers` on real track data |
| `test_physics.py`, `test_physparts.py` | `ApplyDrivingModel` (2,000 random states) and each of its parts |
| `test_player.py` | driving keys, movement, `ScaleWingSettings` |
| `test_drivers.py` | driver set-up, speeds, sorting |
| `test_cars.py` | race set-up, car placement, laps, timers, car objects, contact, crashes |
| `test_class.py` | the class drop after qualifying, around the limits of all six tracks |
| `test_fov.py`, `test_trackcode.py` | the extra tracks' field of view and every patch list |

The same tests run on all five extra tracks, using that track's C64 image
on one side and the Z80 track code on the other.

### Lockstep test (whole loop)

`tests/test_lockstep.py` runs the C64 `MainDrivingLoop` and the Z80
`MainDrivingLoop` side by side. Both get the same key presses and random
numbers, and the complete mapped game state is compared after every
iteration.

Options select:

* practice, qualifying or a race;
* when CAS switches on;
* the wing settings and the race class;
* the session length;
* a driver who changes gear at any speed.

Sessions are followed to their natural end on both machines: a retirement
after a crash, the finish of a race, or the end of the qualifying time. At
the end the C64 runs `FinishRace` in its main loop and the Z80 runs it in
the UI.

Results:

* Qualifying of 5, 10 and 20 minutes ends identically on both machines.
* A 10-lap race (22,922 iterations, 51 minutes of race time) finishes
  identically.

**Coverage.** All the tests together execute every branch of the C64
physics and AI code, except three groups:

* the C64 joystick and paddle input;
* code that Revs+ patches out;
* dead code.

### Renderer tests

* `test_compose.py` and `test_objdraw.py` compare `Compose` and the object
  renderer with Python models of the same geometry.
* `test_raster.py` compares the edges of 80 random scenes with golden data,
  checks that no line below the highest road line lacks road, and checks the
  step division (`Div16by8`) against exact division.
* `test_needle.py` compares the rev counter needle at all 152 dial positions
  with golden data.
* `test_compose.py`, `test_raster.py` and `test_needle.py` (and
  `test_cars.py` for `MoveCars` and `ProcessOvertaking`) also hold the
  routines to a time budget (T-states without contention), so a later change
  cannot make them slower unnoticed.
* `test_surfaces.py` checks the grass contacts against the pixels actually
  drawn on track line 10 (1,200 scenes).

### Whole-game tests (in the emulated Spectrum)

| Test | Checks |
| --- | --- |
| `test_loader.py` | the game tape loads through the ROM as on a real Spectrum: black screen, the intact loading screen, the menu |
| `test_wings.py` | the wings entered in THE PITS reach the driving model in every session |
| `test_session.py` | each qualifying length and lap count from the menus gives the C64 values |
| `test_uiswap.py` | every way out of driving brings the UI overlay back byte for byte |
| `test_keys.py` | keyboard, Sinclair and Kempston joystick mappings, the J toggle, the gear and starter sounds |
| `test_sound.py` | the beeper while driving: silence when expected, engine clicks, gear noise, squeal, mute, pause, crash; the border stays black |
| `test_srcdata.py` | the literal data in `src/` is exactly what the import tools make of the originals |

### Soak test

`tests/test_soak.py` plays the whole game with random keys for hours of
emulated time. The play covers:

* the menus and the championship;
* every track, loaded from the tracks tape (the ROM tape routines are
  trapped);
* the pits, Caps Shift + 1/2/3, pause and the toggles;
* Kempston input;
* results saved and loaded.

It checks:

* **Every 2,000 T-states:** the program counter must be at the start of an
  instruction (decoded from the assembler listing), in the track code, or in
  the ROM tape routines, never in data or the screen.
* **Every frame:**
  * the interrupt vector is intact;
  * while driving, the track file, its track code and the stored UI overlay
    are intact;
  * in the menus, the UI code is intact;
  * a stack canary is untouched.
* **At the end:** every byte that ever changed is classified. It must be a
  variable, a buffer, an operand that the code patches itself, or a track
  code patch site. Anything else is reported.

Injected faults (a changed code byte, a jump into the screen, a damaged
track) are detected.

More than 30 runs of 40,000 frames each (over 7 hours of play) found no
problems.
The deepest stack use was 48 of its 208 bytes.

### Mutation checks

New tests were checked by deliberately breaking the code they cover. For
example, six mutations of the Kempston code were all caught by
`test_keys.py`, and a mutated CAS gain was caught by the lockstep test.

## 6. Performance

The figures are TV frames per main-loop iteration, measured in the emulator
with contended memory and `FramePace` disabled. The target is 6.5 frames
(0.13 s).

| Situation | Frames per iteration |
| --- | --- |
| Qualifying, car standing | 5.4 |
| Qualifying, driving (median) | 5.3 |
| Race grid, 19 cars in view | 6.6 |
| Race start, field pulling away | 6.7 on average, up to 7.6 |

When an iteration is faster, `FramePace` waits, and the game runs at the C64
pace. A typical iteration costs about 370,000 T-states. The earlier
instruction-by-instruction port needed about 925,000.

The main techniques:

* **Uncontended memory:** all hot code and tables live there, with a second
  hot code area at `$F800`. Code that runs once per session lives in
  contended memory.
* **Span rendering** instead of pixel plotting: four edge positions per
  line, unrolled byte fills, and masks only at the boundaries.
* **Work avoidance:**
  * unchanged sky rows are neither composed nor copied;
  * lines behind the cockpit are neither rasterised, composed nor copied;
  * mirror rows are redrawn only where the car was or is (about 0.02 frames
    per iteration).
* **Tables:** quarter-square multiplication, the C64's log and exponential
  projection tables, yaw-to-x conversion, and boundary masks by x.
* **Self-modifying code:** line steps, rounding modes, patterns and blit
  sources are written into the code only when they change.
* **Register allocation in the hot routines:** `MultiplyCoords` (44.3k to
  37.1k T-states for the driving model) and `BuildCarObjects` (28.8k to 23.0k
  T-states).
* **Object drawing:** scaffold measurements are pre-decoded (about 600 to
  295 T-states each), there are special cases for one- and two-byte-wide
  parts, and the race start went from 479k to 450k T-states.

All optimisations were made under the differential and lockstep tests, so
the game state stayed bit-exact throughout.

### Free memory

The 48K is nearly full. What remains:

| Area | Free |
| --- | --- |
| cold code | 14 bytes |
| hot code | 55 bytes |
| second hot area | 34 bytes |
| UI overlay | 80 bytes |
| largest track code | 2 bytes |
| `$5F00-$5FFF` | 256 bytes, free in every phase |

The space for the menus and the championship was reserved early, before any
speed optimisation that would have spent memory.

## 7. Deviations from the C64 original

The deliberate deviations are listed here. Where they affect the simulation,
the same change is applied to the C64 reference, so the tests still cover
everything else.

**Changes to the C64 game:**

* **No crane after a crash:** `heightAboveTrack` stays 0, so a Novice race
  restarts on the ground. The C64 reference is patched the same way.
* **`HookFirstSegment`:** the original returned the X of
  `CalcSegmentVector`, so `GetFirstSegment` cleared the flags of the wrong
  segment. The fix is approved, and the reference is patched to match.
* **Lap time tenths** move on every update; the original only prints them
  when a second passes.

**From ataribaby's version:**

* The tyre tread animates at half the original rate.
* The starting lights are three square lamps at the top right.
* The CRASHED notice covers the HUD during the crash pause.
* The gear and starter sounds.
* The controls: X clutch, C (CAS), N, M, H, Caps Shift + 1/2/3, and the
  Sinclair joystick on keys 6–0.
* The menus.

**New in this version:** J switches between the Sinclair and Kempston
joysticks.

**Not ported, because the Spectrum has no counterpart:**

* the C64 joystick and paddle input (replaced by the Sinclair and Kempston
  joysticks, mapped onto the keys);
* the background colour table;
* the off-screen verge flag.

## 8. Bugs found on the way

Most of these were found by the tests.

**During the port:**

* `SortDrivers` never finished a race-time sort with a DNF entry. The 6502's
  decimal `SBC` leaves the binary borrow in the carry, but the Z80 took the
  borrow after `DAA`, which differs for `$C0`.
* The rev counter needle jumped. Positions 128–151 used an 8-bit doubled
  table index and were drawn mirrored.
* The road was missing in front of the car when the nearest verge point was
  beside or behind the camera. Fixed by `RasterTail`. 69 of 300 random scenes
  failed before the fix; none fail now.
* A wing mirror segment match failed because an `ADD` clobbered the zero
  flag of a `CP`.
* A road sign contact threshold was wrong because `A` was clobbered.

**From play-testing and the review requests:**

* **Caps Shift + 1/2/3 reset the computer.** The track code patch routines
  had been inserted between `StopDriving` and `LoadUI`, so `StopDriving` fell
  through into them, the UI overlay was never restored, and the menus ran
  into the view buffer. `test_uiswap.py` now covers every way out of
  driving.
* **The class drop after qualifying compared the minutes only.**
  `ADD HL,BC` between the seconds' `SUB` and the minutes' `SBC` cleared the
  borrow, so any player who qualified last with a 1:xx lap dropped to
  Novice. Found by `test_class.py`.
* **The grass under the tyres did not always match the picture** (a side
  without road, the car sideways). Found by `test_surfaces.py`.
* **The tyre squeal continued** in the menus and through the crash pause.
  Found by `test_sound.py`; fixed with `soundLive`.

**In the tests:**

* The C64 side ran out of random numbers after about 22,000 iterations of a
  20-lap race, while the Z80 wrapped round its table. The C64 side now wraps
  too.

## 9. Build and toolchain

Since the second day, the game builds from `src/` alone:

* **Code:** the Z80 sources.
* **Literal data:**
  * the six C64 track files;
  * the track code constants;
  * the projection, object and text tables;
  * the zero page layout;
  * the computed tables.
* **Code generated from the cockpit artwork:** the mirror glass masks, the
  steering wheel marks and the view copy routine.
* **`src/gfx/`:** the binary graphics (`cockpit.bin`, `gears.bin`,
  `loading.scr`).

Nothing is decoded or converted during a build. `tools/gen_src.py` re-runs
the import tools when the originals or the artwork change, and
`tests/test_srcdata.py` checks that `src/` matches what they produce.

The build uses **z88dk** (`build.bat`):

1. `z88dk-z80asm -b -m -l -mz80 -Isrc -Obuild -orevs.bin @src\revs.lst`
   assembles the module list:
   * the main program (`main.asm`): one block from `$6000`, with its parts
     at fixed addresses in ascending order (`PHASE`, padded with `ds`);
   * the loader;
   * the six track modules, each with one section for the track file and
     one for the track code.
2. `z88dk-appmake +zx` makes the CODE blocks and the snapshot for the tests.
3. `copy /b` joins the blocks into `output/revs.tap` and
   `output/revs_tracks.tap`.

The code was first written for sjasmplus with a Python build script, then
converted to z88dk. The z88dk build was compared with the previous one, and
all tests passed with it, including the lockstep runs on every track and a
track loaded from the new tracks tape. The program now starts with
`jp Entry` at `$6000`, so that a snapshot starts the game.

z80asm specifics used:

* local labels `@name` (full name `Parent@name`);
* `low`/`high` written as `% 256` and `/ 256`, never inside outer
  parentheses (`ld a,(x)` is a memory load);
* `NAME MACRO` … `ENDM`;
* `DEFL` to accumulate checksums;
* `ASSERT` for every address constraint (constant expressions only, no
  forward references);
* `ZPAGE` instead of the reserved name `ZP`.

The tools:

| Tool | Purpose |
| --- | --- |
| `c64_tape.py`, `c64_extract.py`, `c64_image.py` | decode the C64 tape once, build the reference memory image (installer and track hook applied) |
| `dis6502.py`, `c64_trackcode.py`, `bbc_tracks.py` | disassemble C64 code with BBC labels; list a track's patches and code |
| `gen_c64data.py`, `gen_objects.py`, `gen_text.py`, `gen_vars.py`, `gen_trackcode.py` | import data from the C64 and BBC originals into `src/` |
| `gen_tables.py`, `mcscale.py` | computed tables (quarter squares, masks, yaw-to-x at 1.75 px) |
| `gen_cockpit.py` | cockpit bitmap, mirror masks, steering wheel marks, the generated view copy |
| `loading_screen.py` | the loading screen PNG as SCREEN$ |
| `gen_src.py`, `srcdata.py` | run all import tools into `src/` |
| `zx.py` | the headless Spectrum used by the whole-game tests |

## 10. What made it work

* **Choosing the C64 version as the reference.** It defines the timing that
  the Spectrum can reach, and its binary could be run directly as an
  executable specification.
* **Differential testing against the real code.** Comparing against the
  original running in an emulator makes "faithful" a measurable property.
  It caught subtle 6502-to-Z80 differences (decimal arithmetic, borrow and
  flag handling) that reading the code would have missed.
* **Separating what must be exact from what may be redesigned.** The
  simulation is bit-exact. The renderer was free to be completely different,
  as long as what the physics reads from the picture (the grass contacts)
  stays the same.
* **Small verified steps.** A commit after every step kept the game working
  throughout, and made each optimisation a safe, reversible experiment.
