; Track code of the extra tracks (Brands Hatch, Donington Park, Nurburgring,
; Oulton Park, Snetterton): Z80 versions of the C64 routines in their track
; files (see notes/extra-tracks.md). Assembled once per track at TRACKCODE
; with that track's constants (src/trackconst_<track>.asm: track file
; addresses and the track width), in the track's module
; (src/track_<track>.asm, linked with the main program); it travels with
; the track on the tracks tape. The UI applies the patch list at the start (the
; C64 track hook, ModifyGameCode) and undoes it before another track loads.
;
; Patch list: db length (1-3), dw address, new bytes, old bytes; db 0.
; Main program labels: src/tracklink.asm (GLOBAL).

        ASSERT TC_YAWHI == TC_YAWLO + 1
        ASSERT TC_YAWAHI - TC_YAWALO == TC_YAWALO - TC_TSLOPE
        ASSERT TC_SUBCONFIG - TC_YAWAHI == TC_YAWALO - TC_TSLOPE
        ASSERT TC_YAWDHI == TC_YAWDLO - $100 && TC_SLOPED == TC_YAWDLO + $100

        dw TcPatches

; ---------------------------------------------------------------------------
; Dynamic segment vectors (C64 HookSectionFrom, HookFirstSegment,
; HookDataPointers, HookSegmentVector; the same in all five tracks)

; HookSectionFrom: in GetSectionCoords in place of "ld (thisVectorNumber),
; a". A = trackSectionFrom, B = 8 * section. Starts the section: yaw angle,
; slope and first sub-section (trackSubConfig: bit 0 -> bit 7 = straight,
; bits 2-7 -> sub-section), the horizon limit of GetSectionAngles (bit 1),
; and facing forwards its first vector. Preserves BC, DE, HL.
HookSectionFrom:
        ld (thisVectorNumber), a
        push hl
        push de
        push bc
        ld a, b
        rrca
        rrca
        rrca
        and $1F
        ld c, a
        ld b, 0
        ld hl, TC_TSLOPE
        add hl, bc
        ld de, TC_YAWALO - TC_TSLOPE    ; (tables of 30 sections)
        ld a, (hl)
        ld (TC_SLOPE), a
        add hl, de
        ld a, (hl)
        ld (TC_YAWLO), a
        add hl, de
        ld a, (hl)
        ld (TC_YAWHI), a
        add hl, de
        ld a, (hl)                      ; trackSubConfig
        srl a                           ; LSR A: carry = bit 0
        rra                             ; ROR A: bit 7 = bit 0, carry = bit 1
        ld (TC_SUBSECTION), a
        ld a, $0E
        rra                             ; $07 or $87
        ld (GetSectionAngles_tcHorizon + 1), a
        xor a
        ld (TC_SUBSEG), a
        ld a, (directionFacing)
        or a
        call p, SetSegmentVector
        pop bc
        pop de
        pop hl
        ld a, (thisVectorNumber)
        ret

; HookFirstSegment: in GetFirstSegment in place of "call UpdateVectorNumber"
; (facing backwards). Keeps C = frontSegmentIndex for GetFirstSegment, which
; then clears that segment's flags. (Approved fix: the original leaves the X
; of CalcSegmentVector, a zTrackCurve value, and clears a byte of another
; segment; tools/c64_image.py fixes the C64 reference the same way.)
HookFirstSegment:
        push bc
        call UpdateVectorNumber
        call UpdateDataPointers
        call CalcSegmentVector
        pop bc
        ret

; HookDataPointers: at the start of GetTrackSegment in place of
; "ld a, (frontSegmentIndex)"
HookDataPointers:
        ld a, (thisSectionFlags)
        and $40
        call nz, UpdateDataPointers
        ld a, (frontSegmentIndex)
        ret

; HookSegmentVector: in GetTrackSegment and TurnPlayerAround in place of
; "call UpdateCurveVector": the next vector of a generated section
HookSegmentVector:
        ld a, (thisSectionFlags)
        and $40
        ret z
        call UpdateVectorNumber
        ; fall through

; SetSegmentVector: yaw angle and slope by the sub-section's deltas
; (negated facing backwards; not for a straight sub-section), then the
; vector
SetSegmentVector:
        ld a, (TC_SUBSECTION)
        or a
        jp m, CalcSegmentVector
        ld c, a
        ld b, 0
        ld hl, TC_YAWDLO
        add hl, bc
        ld e, (hl)
        dec h
        ld d, (hl)                      ; DE = trackYawDelta
        inc h
        inc h
        push hl                         ; trackSlopeDelta
        ld a, (directionFacing)
        or a
        jp p, @s1
        xor a                           ; facing backwards: -DE
        sub e
        ld e, a
        sbc a, a
        sub d
        ld d, a
@s1:
        ld hl, (TC_YAWLO)               ; (TC_YAWHI follows)
        add hl, de
        ld (TC_YAWLO), hl
        pop hl
        ld a, (directionFacing)
        or a
        ld a, (hl)
        jp p, @s2
        neg
@s2:
        ld hl, TC_SLOPE
        add a, (hl)
        ld (hl), a
        ; fall through

; CalcSegmentVector: the inner and outer vectors of segment vector
; thisVectorNumber from the yaw angle: an eighth of a circle in xTrackCurve
; and zTrackCurve (64 steps), reflected and negated by octant; outer =
; (-z, x) * TC_WIDTH / 256, inner y = segmentSlope. Returns C = the 6502 X
; (the zTrackCurve value).
CalcSegmentVector:
        ld hl, (TC_YAWLO)               ; H = yawAngleHi, L = yawAngleLo
        ld a, h
        rlca
        rlca
        rlca
        and 7
        ld b, a                         ; B = octant
        sla l
        rl h                            ; H = hi << 1 | lo bit 7
        ld a, h
        and $3F
        bit 0, b
        jr z, @c1
        xor $3F                         ; odd octant: 64 - index
        inc a
@c1:
        ld e, a
        ld d, 0
        ld hl, TC_XCURVE
        add hl, de
        ld a, (hl)                      ; 6502 Y = x curve
        ld hl, TC_ZCURVE
        add hl, de
        ld c, (hl)                      ; 6502 X = z curve
        ld d, a
        ld a, b
        inc a
        and 2
        jr nz, @c2
        ld e, c                         ; V = x, W = z
        jr @c3
@c2:
        ld e, d                         ; V = z, W = x
        ld d, c
@c3:
        ld a, b
        cp 4
        jr c, @c4
        xor a                           ; octants 4-7: V = -V
        sub d
        ld d, a
@c4:
        ld a, b
        cp 6
        jr nc, @c5
        cp 2
        jr c, @c5
        xor a                           ; octants 2-5: W = -W
        sub e
        ld e, a
@c5:
        ld a, (thisVectorNumber)
        ld l, a
        ld h, 0 + (TRACK + $100) / 256       ; xTrackSegmentI (C64 $5400)
        ld (hl), d
        ld a, d
        call @signed
        ld h, 0 + (TRACK + $500) / 256       ; zTrackSegmentO (C64 $5800)
        ld (hl), a
        ld h, 0 + (TRACK + $300) / 256       ; zTrackSegmentI (C64 $5600)
        ld (hl), e
        ld a, e
        call @signed
        neg
        ld h, 0 + (TRACK + $400) / 256       ; xTrackSegmentO (C64 $5700)
        ld (hl), a
        ld a, (TC_SLOPE)
        ld h, 0 + (TRACK + $200) / 256       ; yTrackSegmentI (C64 $5500)
        ld (hl), a
        ret
@signed:                                ; A = sign(A) * |A| * TC_WIDTH / 256
        or a
        push af
        jp p, @g1
        neg
@g1:
        push hl
        ld h, a
        ld a, TC_WIDTH
        ld (U), a
        ld a, h
        call Multiply8x8
        pop hl
        ld b, a
        pop af
        ld a, b
        ret p
        neg
        ret

; UpdateDataPointers: subSection and subSectionSegment one segment on in
; the direction we face
UpdateDataPointers:
        ld a, (TC_SUBSECTION)
        ld e, a                         ; 6502 Y
        ld d, 0
        ld a, (directionFacing)
        or a
        ld a, (TC_SUBSEG)
        jp m, @u1
        inc a
        ld hl, TC_SUBSIZE
        add hl, de
        cp (hl)
        jr c, @u3
        inc e
        ld a, (TC_SUBCOUNT)
        ld b, a
        ld a, e
        cp b
        ld a, 0
        jr c, @u3
        ld e, a
        jr @u3
@u1:
        sub 1
        jr nc, @u3
        ld a, e
        and $7F
        ld e, a
        cp 1
        jr nc, @u2
        ld a, (TC_SUBCOUNT)
        ld e, a
@u2:
        dec e
        ld hl, TC_SUBSIZE
        add hl, de
        ld a, (hl)
        dec a
@u3:
        ld (TC_SUBSEG), a
        ld a, e
        ld (TC_SUBSECTION), a
        ret

; ---------------------------------------------------------------------------
; HookSlopeJump (all five tracks, the same C64 code): in
; ApplyElevation in place of "ld hl, W", before the height above the track
; (A, W = 0) becomes the y offset: on the ground the car rises by
; MultiplyHeight(playerSpeedHi) (speed times the segment's slope)

        IFDEF TC_SLOPEJUMP
HookSlopeJump:
        or a
        jr nz, @j1
        ld a, (playerSpeedHi)
        call MultiplyHeight             ; (B = the segment vector)
        jp p, @j1
        ld hl, W
        dec (hl)
@j1:
        ld hl, W
        ret
        ENDIF

; ---------------------------------------------------------------------------
; Horizon and field of view (C64: the end of GetTrackAndMarkers and
; MapSegmentsToLines in DrawTrack). The line where objects are cut off
; (DrawObject's "ld a, n") follows the raised horizon.

TcObjCutoff     EQU DrawObject_tcCutoff + 1

; HookFixHorizon: GetTrackAndMarkers after yVergeRight[Y] = A (H = high
; VERGE_Y, L = Y = horizonListIndex): objects cut off at A, yVergeLeft[Y] = A;
; Brands Hatch, Oulton Park, Snetterton, Nurburgring: for entries Y-8 a left
; verge to the right of the right one is moved onto it, and yVergeLeft =
; yVergeRight (Nurburgring: and the verge data of entries below 6 cleared);
; then horizonTrackWidth at Y
HookFixHorizon:
        ld (TcObjCutoff), a
        ld b, a
        ld a, l
        add a, 40
        ld l, a
        ld (hl), b
        IF TC_FIX
        sub 40
        ld e, a                         ; E = Y (right), D = Y + 40 (left)
@f1:
        ld a, e
        add a, 40
        ld d, a
        ld h, VERGE_XLO / 256
        ld l, e
        ld c, (hl)
        ld a, c
        ld l, d
        sub (hl)
        inc h                           ; VERGE_XHI
        ld l, e
        ld b, (hl)
        ld a, b
        ld l, d
        sbc a, (hl)
        jp p, @f2
        ld (hl), b                      ; left x = right x
        dec h
        ld (hl), c
@f2:
        ld h, VERGE_Y / 256
        ld l, e
        ld a, (hl)
        ld l, d
        ld (hl), a
        IF TC_FIX == 2
        ld a, e
        cp 6
        jr nc, @f3
        dec h                           ; VERGE_DATA
        ld (hl), 0
        ld l, e
        ld (hl), 0
@f3:
        ENDIF
        inc e
        ld a, e
        cp 9
        jr c, @f1
        ENDIF
        ld a, (horizonListIndex)
        ld e, a
        ; fall through

; HorizonWidth: horizonTrackWidth = 80% of the difference of the C64 bytes
; $8450+Y and $8478+Y of the verge block, Y = E < 80: xVergeRightHi[Y] and
; xVergeRightHi[Y + 40] (Y >= 40: vergeDataRight[Y - 40]); Donington Park:
; of the absolute difference
        ASSERT VERGE_DATA == VERGE_XHI + $100 && VERGE_Y == VERGE_DATA + $100
        ASSERT VERGE_XHI == VERGE_XLO + $100
HorizonWidth:
        ld h, VERGE_XHI / 256
        ld l, e
        ld b, (hl)
        ld a, e
        add a, 40
        cp 80
        jr c, @w1
        sub 80
        inc h
@w1:
        ld l, a
        ld a, b
        sub (hl)
        IF TC_ABSWIDTH
        jp p, @w2
        neg
@w2:
        ENDIF
        ld (U), a
        ld a, $CD
        call Multiply8x8
        ld (horizonTrackWidth), a
        ret

; HookFov: in the main loop before BuildEdges (C64 DrawTrack: the hooked
; MapSegmentsToLines for the left, then the right verge). From the second
; nearest verge towards the horizon, a verge lower than one nearer to us is
; raised to its line (the hill hides the track behind it); at the first one
; objects are cut off there and the horizon width is taken one entry nearer.
; (Snetterton, Nurburgring: the C64 also keeps the first verge visible when
; nose down and heading along the track, which our edge rasteriser never
; drops.)
HookFov:
        ld a, (segmentListPointer)
        call @side
        ld a, (segmentListRight)
        call @side
        jp BuildEdges
@side:                                  ; A = vergeBufferEnd
        dec a
        ld e, a                         ; E = 6502 Y
        and $20
        ld c, a                         ; C = 0: no verge raised yet
        ld d, 0                         ; D = the highest line so far
@s1:
        dec e
        ld a, (horizonLine)
        ld b, a
        ld h, VERGE_Y / 256
        ld l, e
        ld a, (hl)
        cp b
        ret nc                          ; reached the horizon
        cp d
        jr nc, @s2
        ld (hl), d                      ; raise
        ld a, c
        or a
        jr nz, @s1
        ld a, d
        ld (TcObjCutoff), a
        inc e
        call HorizonWidth               ; (preserves C, DE)
        dec e
        ld c, $80
        jr @s1
@s2:
        ld d, a
        jr @s1

; ---------------------------------------------------------------------------
; Patch list (the C64 ModifyGameCode)

TcPatches:
        db 3                            ; GetSectionCoords
        dw GetSectionCoords_tcSite
        db $CD
        dw HookSectionFrom
        db $32
        dw thisVectorNumber
        db 2                            ; GetFirstSegment
        dw GetFirstSegment_tcSite + 1
        dw HookFirstSegment
        dw UpdateVectorNumber
        db 3                            ; GetTrackSegment
        dw GetTrackSegment
        db $CD
        dw HookDataPointers
        db $3A
        dw frontSegmentIndex
        db 2
        dw GetTrackSegment_tcSite + 1
        dw HookSegmentVector
        dw UpdateCurveVector
        db 2                            ; TurnPlayerAround
        dw TurnPlayerAround_tcSite + 1
        dw HookSegmentVector
        dw UpdateCurveVector
        db 1                            ; GetSectionAngles (HookSectionFrom)
        dw GetSectionAngles_tcHorizon + 1
        db $07
        db $07
        ; the track's tables (in other places than Silverstone's)
        db 2                            ; GetSectionSteering
        dw GetSectionSteering_tcSteering + 1
        dw TC_STEERING
        dw trackSteering
        db 2                            ; BuildRoadSign
        dw BuildRoadSign_tcSignZ + 1
        dw TC_SIGNZ
        dw zTrackSignVector
        db 2
        dw BuildRoadSign_tcSignY + 1
        dw TC_SIGNY
        dw yTrackSignVector
        db 2
        dw BuildRoadSign_tcSignX + 1
        dw TC_SIGNX
        dw xTrackSignVector
        db 1
        dw BuildRoadSign_tcSignLo + 1
        db TC_SIGNDATA % 256
        db trackSignData % 256
        db 1
        dw BuildRoadSign_tcSignHi + 1
        db TC_SIGNDATA / 256
        db trackSignData / 256
        ASSERT TC_SIGNDATA / 256 == (TC_SIGNDATA + 15) / 256
        ASSERT TC_STEERING / 256 == (TC_STEERING + 31) / 256
        ASSERT TC_SIGNZ / 256 == (TC_SIGNZ + 15) / 256 && TC_SIGNY / 256 == (TC_SIGNY + 15) / 256
        ASSERT TC_SIGNX / 256 == (TC_SIGNX + 15) / 256
        IFDEF TC_BRAKE                  ; ProcessOvertaking: brake within 75
        db 1
        dw ProcessOvertaking_tcBrake + 1
        db TC_BRAKE
        db 60
        ENDIF
        IFDEF TC_HEIGHTCAP              ; BuildCarObjects: no height cap
        db 1
        dw BuildCarObjects_tcHeightCap + 1
        db TC_HEIGHTCAP
        db $1F
        ENDIF
        db 3                            ; GetTrackAndMarkers: HookFixHorizon
        dw GetTrackAndMarkers_tcTail
        db $C3
        dw HookFixHorizon
        db $C3
        dw GetTrackAndMarkers_t3b
        db 3                            ; DrawObject: cut off at n
        dw DrawObject_tcCutoff
        db $3E, $1F, $00
        db $3A
        dw horizonLine
        db 2                            ; the main loop: HookFov
        dw MainDrivingLoop_tcEdges + 1
        dw HookFov
        dw BuildEdges
        IFDEF TC_SLOPEJUMP
        db 3                            ; ApplyElevation
        dw ApplyElevation_tcSlope
        db $CD
        dw HookSlopeJump
        db $21
        dw W
        ENDIF
        IFDEF TC_HAIRPIN                ; object 10 part 2 (top, bottom):
        db 2                            ; the chicane sign becomes a hairpin
        dw objPartTab + 5 * TC_HAIRPIN + 1
        db TC_HPTOP, TC_HPBOTTOM
        db TC_HPTOP0, TC_HPBOTTOM0
        ENDIF
        IFDEF TC_NOSKIP                 ; GetSectionAngles: no skip of entry
        db 1                            ; sectionListPointer
        dw GetSectionAngles_tcSkip + 1
        db 0
        db GetSectionAngles_gsec3 - GetSectionAngles_tcSkip - 2
        ENDIF
        db 0
TRACKCODE_USED:
        ASSERT TRACKCODE_USED <= TRACKCODE_END
