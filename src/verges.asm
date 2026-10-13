; Track verges: pitch and yaw angles of the track sections and segments in
; view (C64 versions of GetTrackAndMarkers, GetSectionAngles,
; GetSegmentAngles, GetVergeAndMarkers).
;
; Verge buffer (VERGE_* pages, index 0..39 right verge, 40..79 left verge):
;   0..5    track section list
;   6..21   segment list, inner edge of the verge marks
;   22..37  segment list, outer edge (index + 16)

; C64 segment list step (in segment buffer units of 3). Entry 7 is set each
; frame to 6 or 3 so that the double steps stay aligned to even segments.
segmentStep:            db 0, 39, 18, 9, 6, 6, 6, 6, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3
segmentFlagMask:        db %00101101, %00110011
vergeColour:            db 1, 1, 0, 0, 0, 0, 0, 0       ; C64: 0 red, 1 black, 2 white
vergeScale:             db 5, 5, 3, 4, 3, 4, 4, 4

segDetailsX:            db 0    ; start index for GetSegmentDetails (C64 patches LDX #)
vergeV:                 db 0    ; verge colour scheme of the current segment
vergeWidth:             dw 0    ; (U,T) verge width
vergeSide:              db 0

; ---------------------------------------------------------------------------
; GetTrackAndMarkers: compute the verge buffer for this frame

GetTrackAndMarkers:
        xor a
        ld (horizonLine), a
        call GetSectionAngles
        ld a, (frontSegmentIndex)
        ld b, 6
        bit 0, a
        jr z, @t1
        ld b, 3
        sub 3
        jr nc, @t1
        add a, 120
@t1:
        ld (segDetailsX), a
        ld a, b
        ld (segmentStep + 7), a
        ld a, $FF
        ld (edgeDistanceHi), a
        ld a, 9
        ld (edgeSegmentNumber), a
        xor a
        call GetSegmentDetails
        ld a, 6
        call GetSegmentAngles
        ld a, (segmentListPointer)
        ld (segmentListRight), a
        ld a, $80
        call GetSegmentDetails
        ld a, 46
        call GetSegmentAngles
        ld a, (horizonListIndex)
        cp 40
        jr c, @t2
        sub 40
        ld (horizonListIndex), a
@t2:
        ld (prevHorizonIndex), a
        ld l, a
        ld a, (horizonLine)
        cp 79
        jr c, @t3
        ld a, 78
        ld (horizonLine), a
@t3:
        ld h, VERGE_Y / 256
        ld (hl), a
@tcTail:                                ; (track code: jp HookFixHorizon)
        jp @t3b
@t3b:
        ld b, a
        ld a, l
        add a, 40
        ld l, a
        ld (hl), b
        ld h, VERGE_XHI / 256
        ld b, (hl)                      ; xVergeLeftHi[Y]
        sub 40
        ld l, a
        ld a, (hl)
        sub b
        jp p, @t4
        neg
@t4:
        srl a
        ld (horizonTrackWidth), a
        ret

; GetSegmentDetails: A = 0 for the right verge, $80 for the left verge.
; Returns C = first segment buffer index, sets segmentOffset/Direction.

GetSegmentDetails:
        ld hl, directionFacing
        xor (hl)
        ld a, (segDetailsX)
        ld c, a
        jp p, @d1
        add a, 120
        ld c, a
        ld a, 120
        ld (segmentOffset), a
        ld a, 1
        ld (segmentDirection), a
        ret
@d1:
        xor a
        ld (segmentOffset), a
        ld (segmentDirection), a
        ret

; ---------------------------------------------------------------------------
; SpinTrackSection: apply the spin of the car to verge list entry B

SpinTrackSection:
        ld h, VERGE_DATA / 256
        ld l, b
        ld (hl), 0
        ld h, VERGE_XLO / 256
        ld a, (spinYawAngleHi)
        ld e, a
        ld a, (hl)
        sub e
        ld (hl), a
        inc h
        ld a, (spinYawAngleTop)
        ld e, a
        ld a, (hl)
        sbc a, e
        ld (hl), a
        ld h, VERGE_Y / 256
        ld a, (spinPitchAngle)
        ld e, a
        ld a, (hl)
        sub e
        ld (hl), a
        ld hl, horizonLine
        cp (hl)
        ret c
        ld (hl), a
        ld a, b
        ld (horizonListIndex), a
        ret

; ---------------------------------------------------------------------------
; GetSectionAngles: update one entry of the track section list and spin the
; others.

GetSectionAngles:
        ld a, (newSectionFetched)
        or a
        jr z, @g1
        call ShuffleSectionList
        xor a
        ld (newSectionFetched), a
@g1:
        ld a, (sectionListStart)
        cp 6
        ret z
        ld a, (sectionListValid)
        cp 6
        jr z, @gsec4
        ld b, a
@gsec2:
        ld a, (sectionListPointer)
        cp b
@tcSkip:                                ; (track code: no jump, Donington,
        jr z, @gsec3                    ; Snetterton)
        ld a, b
        add a, 40
        ld c, b
        ld b, a
        call SpinTrackSection
        ld b, c
        call SpinTrackSection
@gsec3:
        inc b
        ld a, b
        cp 6
        jr c, @gsec2
@gsec4:
        ld a, (sectionListPointer)
        neg
        add a, 6
        add a, a
        add a, a
        add a, a
        ld e, a
        ld a, (directionFacing)
        or a
        ld a, (OBJ_SECTION + 23)
        jp p, @gsec5
        add a, 8
        sub e
        jr nc, @gsec6
        ld hl, trackSectionCount
        add a, (hl)
        jr @gsec6
@gsec5:
        add a, e
        ld hl, trackSectionCount
        cp (hl)
        jr c, @gsec6
        sub (hl)
@gsec6:
        ld (thisSectionNumber), a
        ld b, a
        ld a, (sectionListPointer)
@gsec7:
        ld (segmentCounter), a          ; sectionCounter
        ld c, $FD
        call GetSectionCoord
        call GetObjYawAngle
        ld a, (segmentCounter)
        ld l, a
        ld a, (directionFacing)
        or a
        jp p, @g8
        ld a, l
        xor 40
        ld l, a
@g8:
        call StoreVergeYaw
        ld a, (segmentCounter)
        cp 40
        jr nc, @gsec10
        call GetObjPitchAngle
        ld a, (segmentCounter)
        ld l, a
        ld h, VERGE_Y / 256
        ld a, (LL)
        ld (hl), a
        ld b, a
        ld a, l
        add a, 40
        ld l, a
        ld (hl), b
        ld hl, horizonLine
        ld a, b
        cp (hl)
        jr c, @gsec10
        jr nz, @gsec9
        ld a, (horizonListIndex)
        ld e, a
        ld a, (segmentCounter)
        cp e
        jr c, @gsec10
@gsec9:
        ld a, b
        ld (horizonLine), a
        ld a, (segmentCounter)
        ld (horizonListIndex), a
@gsec10:
        ld a, (thisSectionNumber)
        add a, 3
        ld b, a
        ld a, (segmentCounter)
        add a, 40
        cp 60
        jr c, @gsec7
@gsec11:
        ld a, (sectionListPointer)
        dec a
        call SetSectionPointers
@tcHorizon:
        ld a, 7                         ; (track code: $07 or $87, C64 $20C0)
        ld hl, prevHorizonIndex
        cp (hl)
        ret nc
        ld (horizonLine), a
        ret

; StoreVergeYaw: xVerge[L] = (JJ,II) - playerYawAngle. Returns A = high byte.
StoreVergeYaw:
        ld h, VERGE_XLO / 256
        ld a, (playerYawAngleLo)
        ld e, a
        ld a, (II)
        sub e
        ld (hl), a
        inc h
        ld a, (playerYawAngleHi)
        ld e, a
        ld a, (JJ)
        sbc a, e
        ld (hl), a
        ret

; ---------------------------------------------------------------------------
; GetSegmentAngles: A = first verge list index (6 right, 46 left),
; C = first segment buffer index (from GetSegmentDetails)

GetSegmentAngles:
        ld (segmentListPointer), a
        xor a
        ld (segmentCounter), a
@gseg1:
        call GetObjYawAngle
        ld a, (segmentListPointer)
        ld l, a
        call StoreVergeYaw
        ld hl, (edgeDistanceLo)         ; nearest segment so far?
        ld de, (K)
        or a
        sbc hl, de
        jr c, @gseg3
        ld (edgeDistanceLo), de
        ld a, (segmentCounter)
        ld (edgeSegmentNumber), a
        ld a, (segmentListPointer)
        ld (edgeSegmentPointer), a
        ld l, a
        ld h, VERGE_XHI / 256
        ld a, (hl)
        ld (edgeYawAngle), a
@gseg3:
        call GetObjPitchAngle
        jr c, @gseg4
        jp p, @gseg10
@gseg4:
        ld a, (segmentCounter)          ; not visible: try a point a quarter of
        or a                            ; the way back towards the last one
        ret z
        call QuarterPoint
        ld c, $FA
        call GetObjYawAngle
        ld a, (segmentListPointer)
        ld l, a
        call StoreVergeYaw
        call GetObjPitchAngle
        ret c
        ld a, (prevSegmentOffset)
        ld c, a
        ld a, (markersToDraw)
        ld (markerNumber), a
        call GetVergeAndMarkers
        ld a, (markerNumber)
        ld (markersToDraw), a
        ld hl, segmentListPointer
        inc (hl)
        ret
@gseg10:
        call GetVergeAndMarkers
        ld a, (edgeSegmentNumber)
        ld e, a
        ld a, (segmentCounter)
        cp e
        jr z, @gseg13
        jr c, @gseg13
        ld a, (segmentListPointer)
        ld l, a
        ld h, VERGE_XHI / 256
        ld a, (hl)
        or a
        jp p, @s1
        cpl
@s1:
        cp 20
        jr c, @gseg13
        dec l
        ld a, (hl)
        or a
        jp p, @s2
        cpl
@s2:
        cp 20
        jr c, @gseg4
        ld a, (segmentCounter)
        cp 6
        ret nc
@gseg13:
        ld a, c
        ld (prevSegmentOffset), a
        ld hl, segmentListPointer
        inc (hl)
        ld hl, segmentCounter
        inc (hl)
        ld a, (hl)
        cp 18
        ret nc
        ld hl, segmentStep
        add a, l
        ld l, a
        adc a, h
        sub l
        ld h, a
        ld e, (hl)                      ; step T
        ld a, (segmentOffset)
        ld d, a
        ld a, c
        sub d
        cp e
        ld a, c
        jr nc, @g15
        add a, 120
@g15:
        sub e
        ld c, a
        jp @gseg1

; QuarterPoint: xCoord1 = segment[prevSegmentOffset] +
;               (segment[C] - segment[prevSegmentOffset]) / 4   (per axis)
QuarterPoint:
        ld a, (prevSegmentOffset)
        ld b, a
        push bc
        ld a, xCoord1
        ld (@dst + 1), a
        ld e, 3
@q1:
        push de
        ld h, SEG_LO / 256
        ld l, c
        ld e, (hl)
        inc h
        ld d, (hl)                      ; DE = seg[X]
        ld l, b
        ld a, (hl)
        dec h
        ld l, (hl)
        ld h, a                         ; HL = seg[Y]
        push hl
        ex de, hl
        or a
        sbc hl, de                      ; HL = seg[X] - seg[Y]
        sra h
        rr l
        sra h
        rr l
        pop de
        add hl, de                      ; HL = seg[Y] + diff / 4
        ex de, hl
@dst:
        ld l, 0
        ld h, SEG_LO / 256
        ld (hl), e
        inc h
        ld (hl), d
        inc l
        ld a, l
        ld (@dst + 1), a
        inc b
        inc c
        pop de
        dec e
        jr nz, @q1
        pop bc
        ret

; ---------------------------------------------------------------------------
; GetVergeAndMarkers: verge width, corner markers and verge mark colour of
; segment buffer entry C (0..239), stored at verge list segmentListPointer.

GetVergeAndMarkers:
        ld a, c
        cp 120
        jr c, @g1
        sub 120
@g1:
        add a, 2
        ld l, a
        ld h, SEGDATA / 256
        ld b, (hl)                      ; segmentFlags
        ld a, (segmentDirection)
        ld hl, segmentFlagMask
        add a, l
        ld l, a
        adc a, h
        sub l
        ld h, a
        ld a, b
        and (hl)
        ld (W), a
        and 7
        ld e, a
        ld d, 0
        ld hl, vergeColour
        add hl, de
        ld a, (hl)
        ld (vergeV), a
        ld a, (segmentCounter)
        cp 3
        jp c, @gmar9
        ld hl, vergeScale               ; verge width = scaleUp * 2^(scaleDown - vergeScale - 1)
        add hl, de
        ld a, (scaleDown)
        sub (hl)
        dec a
        ld b, a
        ld a, (scaleUp)
        ld l, a
        ld h, 0
        jr z, @g6
        jp p, @g5
@g4:
        srl l
        inc b
        jr nz, @g4
        jr @g6
@g5:
        add hl, hl
        djnz @g5
@g6:
        ld (vergeWidth), hl
        ld a, (segmentDirection)        ; which side of the track
        rrca
        ld hl, directionFacing
        xor (hl)
        ld (vergeSide), a               ; bit 7 set: verge extends to the left
        ld a, (segmentListPointer)
        ld l, a
        ld h, VERGE_XLO / 256
        ld e, (hl)
        inc h
        ld d, (hl)                      ; DE = xVerge[Y]
        add a, 16
        ld l, a
        push hl                         ; &xVergeHi[Y + 16]
        ld hl, (vergeWidth)
        ld a, (vergeSide)
        or a
        jp m, @sub
        add hl, de
        jr @st
@sub:
        ex de, hl
        or a
        sbc hl, de
@st:
        ex de, hl
        pop hl
        ld (hl), d
        dec h
        ld (hl), e
        ; corner markers
        ld a, (W)
        and %00011000
        jr z, @gmar9
        ld a, (markersToDraw)
        cp 3
        jr nc, @gmar9
        ld e, a
        ld d, 0
        ld hl, markerListIndex
        add hl, de
        ld a, (segmentListPointer)
        ld (hl), a
        ld hl, markerData
        add hl, de
        ld a, (W)
        ld (hl), a
        ld hl, (vergeWidth)
        ld a, (vergeSide)
        or a
        jp p, @m1
        NEGHL
@m1:
        ld a, (W)
        rra
        jr nc, @m2
        srl h
        rr l
@m2:
        ex de, hl                       ; DE = marker offset, HL = index
        push bc
        ld bc, xMarkerLo
        add hl, bc
        pop bc
        ld (hl), e
        inc hl
        inc hl
        inc hl
        ld (hl), d
        ld hl, markersToDraw
        inc (hl)
@gmar9:
        ld a, c
        and 2
        ld a, 2
        jr nz, @g10
        ld a, (vergeV)
@g10:
        ld b, a
        ld a, (segmentListPointer)
        ld l, a
        ld h, VERGE_DATA / 256
        ld (hl), b
        ld h, VERGE_Y / 256
        ld a, (LL)
        ld (hl), a
        cp 80
        ret nc
        ld hl, horizonLine
        cp (hl)
        ret c
        ld b, a
        ld a, (segmentCounter)
        cp 8
        ret nc
        ld (hl), b
        ld a, (segmentListPointer)
        ld (horizonListIndex), a
        ret
