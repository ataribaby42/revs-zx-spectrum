# Extra tracks: the track code (C64 Revs+)

The five extra tracks (Brands Hatch, Donington Park, Nurburgring, Oulton
Park, Snetterton) are not data only. Their C64 track file ($5300-$5AFF, the
same layout as the BBC track files, see 1-source-files/main-sources/
revs-<track>.asm in github.com/markmoxon/revs-source-code-bbc-micro)
contains code. The Revs+ installer ends with JMP $5A30 (CallTrackHook): RTS
for Silverstone, JMP $5700 (ModifyGameCode) for the others, which patches
the main game (list: `python tools/c64_trackcode.py "Brands Hatch"
patches`; disassembly with BBC labels: `... code`). BBC background: the
revs.bbcelite.com deep dives "Code hooks in the extra tracks", "Secrets of
the extra tracks" and "Dynamic track generation in the extra tracks".

## Patches (C64 address, routine, effect) -> port

Core: dynamic segment vectors (identical in all five tracks except the
track width constant and table addresses)

* $11FC GetSectionCoords+27: LDA trackSectionFrom,Y -> JSR HookSectionFrom.
  Sets thisVectorNumber, yawAngle, segmentSlope (trackYawAngle/trackSlope
  of the section), subSection = trackSubConfig: bit 7 = config bit 0
  (straight), bits 0-5 = first sub-section; self-modifies $20C0 (#$07 or
  #$87 by config bit 1, horizon); subSectionSegment = 0; facing forwards:
  SetSegmentVector (skips the deltas if bit 7) + CalcSegmentVector.
* $123E GetFirstSegment+35: JSR UpdateVectorNumber -> HookFirstSegment
  (UpdateVectorNumber, UpdateDataPointers, CalcSegmentVector).
* $12AF GetTrackSegment+4: CLC/ADC #3 -> JSR HookDataPointers (if
  thisSectionFlags bit 6: UpdateDataPointers; A = frontSegmentIndex + 3).
* $138B GetTrackSegment+224, $13E8 TurnPlayerAround+7: JSR
  UpdateCurveVector -> HookSegmentVector (only if thisSectionFlags bit 6:
  UpdateVectorNumber, SetSegmentVector, CalcSegmentVector).
* CalcSegmentVector: yaw -> octant / 64-step index into xTrackCurve and
  zTrackCurve, reflect/negate; inner vector (x, z) = curve, y = segmentSlope;
  outer (x, z) = (-(z * w), x * w) / 256 signed, w = track width constant
  ($88 Brands). Written at thisVectorNumber into the segment vector tables
  (same addresses as Silverstone's: x/y/z inner, x/z outer).
* $57B4: PHP / JMP $466B = signed multiply: sign(A) * (|A| * U / 256).

Track data addresses

* $4526 GetSectionSteering+16: trackSteering table moved ($59D0 -> e.g.
  $58A0).
* $4D18-$4D38 BuildRoadSign: z/y/xTrackSignVector and trackSignData moved.

Physics / AI

* $461B elev7+158 (ApplyElevation): ASL A/ROL $77 -> JSR HookSlopeJump
  (all five, the same code): if heightAboveTrack was 0: A =
  MultiplyHeight(playerSpeedHi), negative -> DEC $77; then the ASL/ROL.
* $2546 ProcessOvertaking+336: CMP #$3C -> #$4B (brake within 75).
* $282B BuildCarObjects+87: AND #$1F -> #$FF (Nurburgring: no height cap).
* $201C GetSectionAngles+28: BEQ $202C -> BEQ +0 (Donington, Snetterton:
  do not skip entry sectionListPointer).
* $1578 ProcessDrivingKeys+51: JSR $153A -> HookJoystick (joystick path?
  check; BBC: joystick players only).

Rendering

* $1B0B DrawObject+63: LDX horizonLine -> LDX #n, n written by the hooks
  ($1B0C): the line where objects are cut off (raised horizon).
* $227B GetTrackAndMarkers+89: STA yVergeLeft,Y -> JSR (HookFixHorizon
  area $5772): $1B0C = A, the verge clean-up loop over entries Y-8, then
  $2286: JSR Absolute8Bit/LSR -> JSR $53F0 (U = d, A = d * $CD / 256):
  horizonTrackWidth = 0.8 * difference instead of |difference| / 2.
* $B467 MapSegmentsToLines+9: JSR CheckVergeOnScreen -> JSR $56C4 (field
  of view loop over yVergeRight, writes $1B0C, calls $227E, then
  CheckVergeOnScreen).
* $20C0 (GetSectionAngles gsec11): LDA #$07 / CMP $52 / BCS / STA
  horizonLine, immediate set by HookSectionFrom.
* $2E3E DrawSteepToLeft (Donington, Snetterton): LDA $63C0,Y/BNE ->
  HookBackground (C64 track drawing; our renderer differs: check).
* $3574, $35F4 pixelByte: chicane sign -> hairpin (Brands, Nurburgring,
  Oulton).

## Port status (src/trackcode.asm, sites marked `.tc*` in the main code)

Ported and checked against the C64 with the track hook applied:

* Dynamic segment vectors (HookSectionFrom, HookFirstSegment,
  HookDataPointers, HookSegmentVector): test_track on each track.
* Track tables (steering, signs), brake distance, height cap, no-skip,
  HookSlopeJump: test_physics, test_cars, test_drivers, BuildRoadSign.
* HookFixHorizon / Hook80Percent: a patched `jp` at the end of
  GetTrackAndMarkers (test_verges on each track, incl. horizonTrackWidth).
  The C64 reads $8478+Y beyond the left Hi table for Y >= 40 (vergeDataRight):
  kept. It also reads left entries beyond the left verge list (stale data
  from earlier frames or, early on, the machine's power-on RAM): the
  lockstep test starts both machines with the C64's verge buffer.
* Field of view loop ($56C4, BBC HookFlattenHills): HookFov, called in place
  of BuildEdges in the main loop (the C64 runs it inside MapSegmentsToLines,
  left then right, before any object is drawn): tests/test_fov.py.
* DrawObject cut-off: `ld a, (horizonLine)` -> `ld a, n / nop`, n written by
  both hooks (C64 $1B0B LDX zp -> LDX #n, initial n = $1F).
* Hairpin sign: objPartTab part 36 top/bottom 0/3 -> 4/11.

Not ported (no counterpart in the Spectrum code):

* The end of the field of view hook in Snetterton and Nurburgring (hill4):
  clears the "first verge off-screen" flag of MapSegmentsToLines ($76) when
  heading along the track nose down (Nurburgring: sections 0-5 only). Our
  edge rasteriser has no off-screen verge dropping, it clips every verge.
* HookBackground (Donington, Snetterton): UpdateBackground's background
  colour table; our compositor fills from the edge tables (grass outside the
  verges) and has no such table.
* HookJoystick ($1578): on the C64 joystick path of ProcessDrivingKeys
  (track-section dependent steering scale); the Spectrum reads keys and the
  Sinclair joystick as keys.

tests/test_trackcode.py checks every patch list (old bytes = the main
program, TcLoaded applies, TcReset restores the program exactly).

## Port plan

1. Hook sites in the Z80 code are CALLs (or 16-bit operands) whose target is
   patched when a track is loaded; defaults restore Silverstone.
2. The track code is assembled per track (track table addresses and
   constants as EQUs) and travels with the track on the tracks tape.
3. Verify each step against the C64 with the hooks applied
   (tools/c64_image.py runs them): test_track / test_verges / lockstep on
   each track (scratchpad wrappers lock_track.py, test_on_track.py).

## Original bug, fixed after the faithful port (user's request)

HookFirstSegment (C64/BBC) ends in CalcSegmentVector, which leaves X =
zTrackCurve value (85-120), and GetFirstSegment then clears segmentFlags,X
($8902+X) instead of the front segment's flags: facing backwards at a new
section, a byte of segments 29-39 in the segment buffer is zeroed (or one of
the unused bytes $8978-$897A), and the front segment keeps old flags. It was
ported faithfully first (lockstep against the C64 on all five tracks), then
fixed as an approved deviation: the Z80 HookFirstSegment keeps C, and
tools/c64_image.py sends the C64's JSR through a helper at $02A7 that keeps
X (test_track with the unfixed C64 reference fails: SEGDATA differs).
