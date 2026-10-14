# Revs for the ZX Spectrum 48K – design

This is a fresh, Spectrum-native conversion of Geoff Crammond's Revs. The goal
is a frame rate comparable to the Commodore 64 version, which advances the game
clock by 0.13 s per main-loop iteration (the BBC Micro uses 0.09 s). The game
timing therefore assumes roughly 7–8 updates per second.

Earlier attempts (github.com/ataribaby42/revs-zx-spectrum and
revs-zx-spectrum-c64-rate) translated the BBC 6502 code nearly instruction by
instruction and reached about 3.4–3.8 updates per second (~925,000 T-states
per update). This version is designed around the Z80 and the Spectrum screen
from the start.

## Reference material

* Mark Moxon's annotated BBC source (github.com/markmoxon/revs-source-code-bbc-micro,
  algorithm documentation) and the revs.bbcelite.com deep-dive articles;
  `assets/bbc` keeps the parts the import tools read (the object scaffold
  table, the assembler listing of the track files).
* The user's earlier ZX versions (github.com/ataribaby42/revs-zx-spectrum
  and revs-zx-spectrum-c64-rate) are only background: nothing builds,
  imports or tests from them.
* `assets/c64` – the C64 Revs+ code the port uses, extracted once from the
  tape `Revs+_cleaned.tap` (`tools/c64_tape.py`, `tools/c64_extract.py`):
  `main_0b00.bin`, `main_6400.bin`, `main_a000.bin` (the main game
  $0B00-$52FF, $6400-$92FF, $A000-$CBFF) and `selector_1400.bin` (the track
  selector block $1400-$4BFF: the six 2 KiB track files from $1800,
  Silverstone the fifth, and the Revs+ installer at $4800).
  `tools/c64_image.py` builds the C64 memory image from them (the track at
  $5300, the installer and the track hook run).
* `notes/c64-map.txt`, `notes/c64-labels.txt`: the BBC routines and
  variables at their C64 addresses (`tools/dis6502.py c64 START END`
  disassembles the C64 image with these labels); `notes/bbc-symbols.txt`:
  the BBC symbols (the zero page layout of `src/zp.asm`).

The C64 code is the BBC code ported with modifications. Simulation semantics
follow the **C64** version (it defines the 0.13 s calibration); the BBC
annotations explain what the code means.

## Build

The game builds from `src/` alone with z88dk, nothing is generated:
`build.bat` (z88dk's bin directory in PATH) runs `z88dk-z80asm` on the
module list `src/revs.lst`, the main program `src/main.asm`, the BASIC
loader `src/loader.asm` and the six track modules `src/track_<track>.asm`,
and links them:

* `build/revs.bin`: the program, one block from LOAD_START ($6000) in
  ascending address order (PHASE: labels are absolute, `ds` pads up to each
  part's address; `jp Entry` at $6000 for a snapshot). Local labels are
  `@name` (`Parent@name`); `low`/`high` are written `% 256` / `/ 256`.
* `build/revs_track_<track>.bin` (the track file, for the track slot) and
  `build/revs_trackcode_<track>.bin` (its track code, for TRACKCODE): two
  sections of each track module. The track code uses the main program's
  symbols listed in `src/tracklink.asm` (GLOBAL; the patched places as
  aliases of their local labels at the end of `main.asm`).
* `build/revs_loader.bin`: the BASIC loader's two tape blocks (header and
  program, with their TAP lengths and checksums, computed by the assembler).

`z88dk-appmake` then makes the other tape blocks: `output/revs.tap` = the
BASIC loader + the loading screen `src/gfx/loading.scr` + the program, `output/revs_tracks.tap` = each track file and track code as CODE
blocks named after the track, and `build/revs.sna` (for the tests).

`src/` holds the code and the data: the six C64 track files
(`trackdata_<track>.asm`), the track code constants
(`trackconst_<track>.asm`), the projection, object and text tables, the zero
page layout and the computed tables as literal data, the mirror glass masks,
the steering wheel marks and the view copy routine generated from the
cockpit (`mirrors.asm`, `wheel.asm`, `viewcopy.asm`), and in `src/gfx` the
binary graphics converted from the artwork in `assets/`: `cockpit.bin` (77
rows x 32 bytes), `gears.bin` (gear glyphs), `loading.scr` (SCREEN$).
`tools/gen_src.py` regenerates all of them (run it after changing the
artwork); `tests/test_srcdata.py` checks that `src/` matches what the import
tools make of the originals.

## Performance budget

3.5 MHz, 69,888 T-states per 50 Hz frame. Target: ≤ 450,000 T-states per game
update (≈ 7.8 updates/s, i.e. 6–7 TV frames per update).

Rough allocation:

| Stage | Budget (T) |
| --- | ---: |
| Physics, AI (20 cars), timers | 90,000 |
| Track projection (sections, ~32 segment points) | 60,000 |
| Object projection (cars, sign, markers) | 30,000 |
| Track rasterisation into the back buffer | 60,000 |
| Objects into the back buffer | 80,000 |
| Present (interrupt-driven copy) | 30,000 |
| HUD, dashboard, mirrors, sound | 30,000 |

Principles:

* All hot code, tables and buffers live in uncontended RAM ($8000-$FFFF).
* Maths uses tables (quarter-square multiplication, logarithms, reciprocal /
  arctangent tables) instead of shift-and-add loops.
* 16-bit quantities are stored little-endian and processed in register pairs.
* Per-car arrays are page-aligned so that `H` selects the table and `L` the
  car index.
* Rendering is span-based: the track is described per screen row by up to four
  verge edge positions, so a row is filled with a few fast byte fills.

## Screen layout and colour

```
y   0..15   two HUD text rows (attributes: own colours)
y  16..81   static sky band (no drawing; may carry its own colour)
y  82..161  track view, 80 rows = BBC track lines 79..0
y 115..191  cockpit (user artwork, 256x77); its transparent pixels in
            rows 119..151 show the track view, rows 152..161 are hidden
```

The track view is monochrome (ink black, paper white) and so are all cells
that contain both view and cockpit pixels; there is no attribute clash in the
view. Materials are dither patterns: sky = paper, road = solid ink,
grass = 25% pattern, white verge = paper, red verge = 50% pattern, black
verge = ink. Colour is used only in cells that are never shared with the view
(HUD, static sky band, fully opaque cockpit cells, starting lights).

Horizontal mapping: the C64 view is 160 multicolour pixels across, 4 per yaw
unit (x = yaw * 4 + 80). The Spectrum draws 1.75 pixels per C64 multicolour
pixel (the PAL aspect of C64 pixels, chosen by comparing with the C64):
x = 128 + yaw * 7, a field of view of +-18.3 yaw units (tools/mcscale.py).
Objects use the same scale: the C64 draws an edge at xPixelCoord + scaffold / 2
multicolour pixels, so a scaffold unit is 0.875 pixels (h13Tab); edges are
two pixels wide (one C64 multicolour pixel).
Vertical: one BBC track line = one Spectrum row. The view starts at row 82
(`VIEW_TOP` in tools/gen_cockpit.py), so the horizon sits about as far above
the cockpit cowl (row 119) as on the C64 (horizon 17 lines above its cowl).

## Rendering

1. Projection produces, for each verge point, a yaw angle (16-bit, as in the
   original, also used by the simulation) and a pitch line (0..79).
2. The four verge edges (left verge start, left track start, right verge start,
   right grass start) are polylines through the segment points. A DDA walks
   each segment and records the x position per row in four 80-byte edge tables
   (plus the colour of the verge mark per row). A segment that spans one line
   stores the clamped x of its two ends, a step over 2 or 4 lines is a shift,
   and a segment with both ends off the screen on the same side gets the
   clamped x (0 or 255) without a division.
3. The row compositor fills each row of the back buffer (32 bytes per row,
   linear layout) from left to right: grass | verge | road | verge | grass, or
   sky above the horizon. Whole bytes are written with unrolled stores; only
   the boundary bytes are masked; a line with road across the whole view is
   one fill. Sky rows and ground rows are separate loops, and sky rows that
   are still sky from the last frame are skipped.
4. Objects (cars, signs, corner markers) are lists of rectangles (scaffolds
   scaled as in the original); they are drawn over the buffer with pattern
   fills, clipped against the terrain line as in the original.
5. Presentation: the buffer is copied to the screen by a generated, unrolled
   routine at the start of a TV frame (interrupt), before the beam reaches
   row 82, so the view never tears. Rows that overlap the cockpit use
   generated mask code (only cockpit bytes with transparency are merged).

The grass contacts that the original physics reads from screen memory are
taken from the edge tables at the corresponding row/x positions, exactly as
Compose draws that row (CheckSurfaces; `tests/test_surfaces.py` compares it
with the drawn pixels). The C64 drawing routine (DrawTrackView) is created at
run time and is not in the tape image; `tests/test_trackview.py` applies its
rule (read from the template it is generated from, $3937) to the dash data
and background colours that the C64's DrawTrack and SetBackground produce,
and compares the colours of the track view with the Spectrum's.

## Simulation

Ported routine by routine from the C64 code (BBC annotations for meaning),
re-expressed with Z80 idioms. Fixed-point widths, rounding and update order are
preserved. Every routine is verified against the C64 6502 code running in
py65 with random inputs (`tests/`).

## Main loop and game flow

`src/ui.asm` (UI overlay) has the menus and the game flow of the user's
version (screens, texts, colours, keys and flow copied from its
`menu_overlay.asm`, `track_menu.asm`, `championship_results.asm`,
`results_tape.asm`; captions in capitals):

* Game tape (`output/revs.tap`, `build.bat`): the user's BASIC loader
  ("REVS", `src/loader.asm`: black border, paper and ink, CLEAR 24575
  (it also clears the screen), LOAD "" SCREEN$,
  POKE 23739,111 so that the CODE header's "Bytes: " message goes to a ROM
  RET instead of over the picture, LOAD "" CODE, CLS, RANDOMIZE USR 32768),
  the loading screen "REVSSCREEN" (the user's `assets/loading/revs.png`,
  encoded by `tools/loading_screen.py` as theirs) and the code "REVSCODE"
  ($6000-). `tests/test_loader.py` loads the tape through the ROM.
* Main menu: 1 PRACTICE, 2 COMPETITION, 3 LOAD RESULTS, 4 SAVE RESULTS,
  5 CLEAR RESULTS, 6 SHOW RESULTS (only once results exist: after a race or
  a successful load).
* Practice: THE PITS (rear and front wing, 0-40; ENTER, Caps Shift + 0
  deletes), SPACE, the track menu, then laps without opponents or time limit
  (BBC: player 0, qualifyingTime = 255).
* Competition (FORMULA 3 CHAMPIONSHIP): class, qualifying 5/10/20 minutes
  ($04/$09/$19), driver name (12 characters, the last one prefilled; Symbol
  Shift + M a full stop), THE PITS, the track menu, qualifying, PLEASE WAIT
  (FinishRace), the class adjustment of BBC MainLoop (a slowest human
  qualifier lowers it by the track's lap times), GRID POSITIONS, 5/10/20
  laps, THE PITS, the race, PLEASE WAIT, points 9/6/4/3/2/1 (POINTS), one
  point for the fastest lap (BEST LAP TIMES), ACCUMULATED POINTS, the menu.
  Tables: 20 rows of the ROM font in colour bands with black gutters.
* Track menu: the six tracks; the track in memory has "* " before its name
  and is used as it is; another one is loaded from the tracks tape
  (`output/revs_tracks.tap`, made by the build from the six C64 track files:
  CODE blocks of 2048 bytes for $C000, matched by the first six characters
  of the name). From the start of the data block until it has loaded without
  error the slot counts as empty, so an interrupted load must be repeated.
  BREAK (Caps Shift + Space) returns to the main menu.
* Results tape: the 76-byte record of the user's version ("RC", version 1,
  name length, name, 20 x 3 BCD scores by driver identity) as CODE
  "REVSRESULT"; a loaded record is checked before it is used.
* Tape transfers call the ROM LD-BYTES / SA-BYTES after their PUSH of
  SA/LD-RET ($0562 / $04C6), so a BREAK returns to the UI.

While driving: Caps Shift + 1 the pits (practice and qualifying, while the
car stands; the car then starts again from its initial place, the session
clock and best lap stay), Caps Shift + 2 ends qualifying or retires from
the race (not in practice; the opponents finish), Caps Shift + 3 a new game
(also during PLEASE WAIT); points and name stay.

`debugStart` (debug.asm, for the test tools) skips the menus: 1 qualifying,
2 a race. `MainDrivingLoop` follows the C64
`MainDrivingLoop` ($B202) call for call; display routines are replaced by the
Spectrum renderer and HUD. `FramePace` keeps an iteration at 6.5 TV frames
(the 0.13 s step) when the frame is fast enough.

The C64 routines in page 3 (ShowStartingLights, PrintTimer, DrawTrackView and
one unknown routine at $0300) are created at run time and are not in the tape
image; ShowStartingLights was reassembled from fragments left in memory (same
layout and constants: $D7, $B6, $A0, AND #$1F, 40).

## Verification

* `tests/test_*.py` compare single routines with the C64 code (py65) on
  random states: track buffer, projection, verges, driving model (and its
  parts), keyboard, player movement, drivers, AI (MoveCars,
  ProcessOvertaking), set-up (ResetVariables, PlaceCarsOnTrack), laps and
  timers, car objects, road sign, contact, crash, finish.
* `tests/test_lockstep.py` runs the whole C64 and Z80 main loops side by side
  with the same keys and random numbers and compares the complete mapped game
  state (`tests/state.py`) after every iteration (qualifying and race,
  hundreds of iterations with crashes and restarts). Display-only scratch
  bytes are excluded; the grass contacts are fed from the C64 to both.
* The extra tracks: the same tests run with another track's C64 image (its
  track hook applied) and, on the Z80, that track plus its track code
  (TcLoaded); `tests/test_fov.py` compares the field of view loop,
  `tests/test_trackcode.py` checks every patch list (old bytes = the main
  program, TcReset restores it exactly).
* `tests/test_objdraw.py`, `test_compose.py`, `test_raster.py` check the
  renderer against Python models / its general path.
* `tests/test_uiswap.py`: StopDriving (every way back from driving: the end
  of a session, Caps Shift + 1/2/3) brings the stored UI overlay back.
* `tests/test_wings.py` plays the game from the main menu in the emulator:
  the wing settings entered in THE PITS (practice, after Caps Shift + 1,
  qualifying, the race) are the C64 rearWingSetting / frontWingSetting in the
  driving loop, scaled as the C64 ScaleWingSettings. `test_lockstep.py` takes
  the wing settings as an argument (`front,rear`).
* `tests/test_class.py`: the race class after qualifying (UiAdjustClass)
  against the C64 MainLoop game6-game10, best laps around the limits of all
  six tracks (a player who qualified last drops to the number of the track's
  two limits, trackLapTimeSec/Min, the best lap beat). `test_lockstep.py`
  takes the race class as an argument and follows a session to its end on
  both machines (a retirement after a crash in an Amateur or Professional
  race, the finish of a race, the end of qualifying time; the C64 then runs
  FinishRace in its main loop, ours in UiFinish). It also takes the number
  of laps / qualifyingTime and a driver who changes gear at any speed.
* C64 coverage: running all the tests above with py65 recording every
  executed instruction leaves no physics or AI branch unexecuted except the
  C64 joystick and paddle input (the Spectrum has the user's Sinclair
  joystick as keys, or Kempston), code that Revs+ patches out, and dead
  code.
* `tests/test_sound.py`: the sound while driving in the emulator (beeper
  toggles per frame): silent menus and engine off, starter pops, engine
  clicks = 1 + revs / 64, never wider apart at higher revs, gear change
  noise, squeal, N mute, silent pause, a silent menu after leaving a squeal,
  a crash: the impact noise and then silence for the CRASHED pause; the
  border black at every port write.
* `tests/test_session.py`: the length of qualifying and the number of laps
  chosen in the menus are the C64 values in the driving loop (each option).
* `tests/test_soak.py [frames] [seed]`: long random play in the emulator
  (menus, all tracks loaded from the tracks tape, sessions, pits, Caps
  Shift + 1/2/3, the toggles, J with Kempston input, results saved and
  loaded): every 2000 T-states PC must be at
  an instruction (or in a runtime-patched area, the track code, the ROM tape
  routines; a jump to $6000 counts as a restart); every frame the IM2 vector,
  while driving the track file, its track code and the stored UI overlay,
  in the menus the UI code must be intact, the stack (a canary down to
  DATA_END) must not overflow; every changed byte must be a variable, a
  buffer, an operand patched at run time (LD (nn),r targets, "patched" in
  the listing build/src/main.lis) or a track code patch site.

## Memory

`src/memmap.asm` is the reference. In short:

* $4000-$5AFF: screen. While driving, character rows 2-9 (pixel rows 16-79,
  the "hidden sky", attributes bright white on white) hold 2 KiB of the UI
  overlay.
* $5B00-$5EFF: the last KiB of the UI overlay while driving (the BASIC area
  and system variables are dead once the game runs; tape transfers will call
  the ROM routines without SA/LD-RET). $5F00-$5FFF: free, kept in every
  phase (for the championship record).
* $6000-$7FFF (contended): cockpit bitmap, screen set-up, cold code (set-up,
  main loop, HUD/text, controls, debug helpers).
* $8000-$BFFF: hot code and variables (`ZP` mirrors the BBC zero page,
  `BLK62` the block that ResetVariables clears).
* $C000-$C7FF: the track, one at a time (Silverstone comes with the game; a
  track loaded from tape replaces it). Only these 2 KiB differ between the
  C64 tracks (their calls into the block, $5A22/$5A25, are common stubs).
* $C800-$F5FF: page-aligned tables (segment buffer, verges, objects, cars,
  projection tables, view buffer, edge tables, x conversion, masks, quarter
  squares); the 24 bytes of masks at $F100 are followed by a third hot code
  area (the sound); $F700 driver times/points; $F800 second hot code area;
  $FC00 object line buffers; stack below $FD60.
* $FD60-$FFF3: the track code of an extra track (below). IM2 without a
  table: I = $39, where the ROM holds $FF bytes, so the vector is $FFFF; it
  holds JR, whose offset is the ROM's first byte ($F3), to JP Isr at $FFF4.
* UI overlay (`src/ui.asm`: menus, game flow, tables, tape transfers):
  assembled for and loaded at $E200-$EDFF (view buffer and edge pages,
  uncontended, unused outside driving), 3 KiB at most. InitDrivingScreen
  stores it (StoreUI) in the hidden sky and at $5B00 and clears the edge
  tables; HeadToTrack loads it back (LoadUI) after the last view copy, so
  the overlay's variables (results record, choices, track in memory) keep
  their values. $E180-$E1FF: the UI keyboard routines (`src/uikeys.asm`).
* Free in every phase: $5F00-$5FFF.

## Extra tracks

The five extra tracks are not data only: their C64 track files hold code
that the installer's track hook patches into the main game (about 42
bytes: calls into the track file, moved tables, changed constants). The
port keeps that split. `src/trackcode.asm` holds Z80 versions of those
routines and a patch list (length, address, new bytes, old bytes); it is
assembled once per track (`src/track_<track>.asm`) with that track's
constants (`src/trackconst_<track>.asm`, imported from the C64 code by
`tools/gen_trackcode.py`) and the main program's symbols, and travels on
the tracks tape right after the track
(Silverstone's block is an empty list). The UI loads it at TRACKCODE after
the track, `TcLoaded` applies the list; `TcReset` restores the main
program before another track loads. The patched places are marked `.tc*`
in the main code:

* dynamic segment vectors (GetSectionCoords, GetFirstSegment,
  GetTrackSegment, TurnPlayerAround): sections built from sub-sections
  with yaw and slope deltas;
* horizon: the end of GetTrackAndMarkers (a `jp` that the track code
  redirects: left verges moved onto the right ones near the horizon,
  horizonTrackWidth = 80% of the verge distance), the field of view loop
  before BuildEdges (verges hidden behind a crest raised to it), the line
  where objects are cut off (DrawObject's `ld a, n`), GetSectionAngles'
  horizon limit and skip;
* the track's steering and sign tables, brake distance of the AI, no
  height cap (Nurburgring), the slope jump in ApplyElevation, the hairpin
  sign.

Not ported, because the Spectrum code has no counterpart: the C64
joystick path (HookJoystick), the background colour table
(HookBackground) and the off-screen verge flag of MapSegmentsToLines.
`notes/extra-tracks.md` lists every patch. Approved fix: the original's
HookFirstSegment made GetFirstSegment clear the flags of a wrong segment;
the Z80 version keeps the front segment index, and the C64 reference is
patched the same way (tools/c64_image.py).

## Controls

As in the user's original ZX version:

| Key | Action |
| --- | --- |
| Q / A | throttle / brake |
| O / P | steer left / right (SPACE: faster manual steering) |
| W / S | gear up / down |
| X | hold the clutch (as a held gear key, without changing gear) |
| T | starter |
| C | C64 Revs+ computer assisted steering (CAS) on/off, indicator on the rev counter |
| N | sound on/off |
| M | cars in the wing mirrors on/off |
| H | pause (press H again to resume) |
| J | joystick: Sinclair joystick 1 or Kempston (notice "Sinclair" / "Kempston") |

Sinclair joystick 1 (keys 6-0) works alongside the keyboard, as in the
user's version: Up / Down throttle / brake, Left / Right steering, Fire with
Up gear up, Fire without Up (centred or with another direction) gear down.
The directions stay active while Fire is held; release Fire before the next
gear change (the original's gear key latch). ReadKeys adds the joystick to
the Q, A, O, P, W and S bits of its key rows.

J switches to a Kempston joystick (port $1F: bits 0 right, 1 left, 2 down,
3 up, 4 fire) and back, with a notice ("Sinclair" / "Kempston") as N and M
show theirs; the choice (joystickType, Sinclair at load) stays for the rest
of the game. The Kempston directions and Fire act exactly as the Sinclair
ones, and keys 6-0 are then plain keys. A port reading with bit 7 set (no
interface: an idle bus gives $FF) adds nothing, so the keyboard alone works
when Kempston is chosen without one.

Sound effects of the user's version: a gear change plays one frame of the
contact noise (as long as the two short packets there); while the starter
cranks (T held, engine off) the beeper gives sparse irregular pops of three
decaying pulses.

On a crash into the fence the HUD rows show CRASHED (centred in row 1, as
the user's version) during the pause; RedrawHud restores them afterwards.
Otherwise the crash follows the C64 (pause, restart), except that there is
no crane: CheckForCrash leaves heightAboveTrack at 0 instead of 127, so a
Novice race restarts on the ground (the user's choice). tools/c64_image.py
applies the same patch to the C64 reference (APPROVED_PATCHES, $109D).

A car pushed off the track by the player (PushCarOffTrack, races only)
brakes to a stop while its racing line moves to the nearer verge (speed /
16 + 4 per iteration, RetiredCar, called from MoveCars for a stopped car
with carStatus bit 0; below speed 32 it keeps its speed until it is at the
verge; at the verge or standing its carSteering is cleared, so the
overtaking steer cannot move it off), and stands there for the rest of the
race. The original left it standing on its racing line (its veer in
carSteering never took effect). The retirement is unchanged (no race time,
last in the results). The C64 reference has the same change: a helper at
$0200 called from MoveCars ($2647), which goes back to $2641 (the speed
kept) for a slow car not yet at the verge.

DrawFence (C64 $3D5C) is procedural as in the original: a diamond mesh that
repeats every 4 track lines (C64 $3D78, 4 mc pixels = 8 pixels here), black
wires over the sky above the horizon and over the grass below it, written
into all rows of the view buffer (objTopRow = 0, so the crash frame's copy
takes them all to the screen and the view is composed again on restart).
The static sky band above the buffer is left alone (kept free for hidden
storage). 59 bytes of code, no picture data.

Starting lights as in the user's version (and the BBC: top right, just above
the horizon): three 8x8 lamps at x = 232-255, y = 88-95 (attribute cells
29-31 of row 11) with white frames (ink) and coloured paper, black (off),
blue, then green, with a black line above, below and left of the group. The
sequence and its timing are the C64's (raceStarting $D7/$B6/$A0, AND #$1F,
40 steps of green at 0.13 s). StartLights draws the lamps into the view
buffer after the objects, so the view copy keeps them on the screen; a colour
change forces a full copy. When the race runs, the lamps are cleared from the
buffer's sky rows and the attributes are restored one iteration later, after
that copy.

The C64 reference is the Revs+ game as patched by its installer: the track
selector copies $4800-$49FF to $9C00 and patches the CAS key check ($0E84),
the CAS entry of ProcessDrivingKeys ($154D), the steering centring ($15EE)
and a drift guard in MovePlayerSegment ($46AA); tools/c64_image.py runs the
installer and the track hook it ends with ($5A30, CallTrackHook: RTS for
Silverstone; the five other tracks jump to their own code at $5700, which
patches about 42 bytes of the main game with hooks into the track file, as
the BBC ModifyGameCode; ported as the track code, see Extra tracks). CAS
works only while a steering key is held and the car faces
forwards: the steering is pulled towards the verge 9 entries ahead on that
side (C64 $9D06-$9D88; SPACE has no effect then). On the C64 the CAS key is
C= + C. The steering wheel mark uses the user's 62 right-hand rim poses,
mirrored for the left (user's choice), clipped to the white cockpit pixels.

## Status (prototype)

Implemented: complete simulation (driving model, AI, overtaking, contact,
crashes, laps, timers), qualifying and race flow, track and object rendering
(cars incl. the four-object car, road signs, corner markers), HUD texts,
starting lights, rev counter, gear, steering mark, tyre animation, beeper
sound, wing mirrors (BBC logic: the car behind as a block in one of three
segments per mirror, shuddering while the engine runs; glass = the white
areas at the screen edges, rows 148-168, from the user's cockpit art).

Measured: about 6.2 TV frames per iteration without cars in view, 7-8.5 with
many cars (race start), i.e. roughly 6-8 updates per second against the
target 7.7.

Also: the user's menus and championship (results to and from tape), all
six tracks (Silverstone in memory, the others with their track code from
the tracks tape).

Not yet: further optimisation of the track renderer.
