; Track segment buffer and movement of objects along the track
;
; Port of the C64 versions of GetSectionCoord(s), GetFirstSegment,
; GetTrackSegment, MoveObjectForward/Back etc. Register conventions:
;   "X" index of the original -> C (or IX/IY for object/driver arrays)
;   "Y" index of the original -> B

; ---------------------------------------------------------------------------
; GetSectionCoord: copy the inner start coordinate of track section B/8 into
; segment buffer entry C (C may be one of the special indices $FA/$FD).
; Preserves B, C.

GetSectionCoord:
        ld h, trackSectionFlag / 256
        ld a, b
        inc a
        ld l, a                         ; xTrackSectionILo + Y
        ld d, SEG_LO / 256
        ld e, c
        ld a, (hl)
        ld (de), a
        inc l
        inc e
        ld a, (hl)
        ld (de), a
        inc l
        inc e
        ld a, (hl)
        ld (de), a
        ld h, trackSectionData / 256     ; xTrackSectionIHi + Y
        dec l
        dec l
        inc d
        dec e
        dec e
        ld a, (hl)
        ld (de), a
        inc l
        inc e
        ld a, (hl)
        ld (de), a
        inc l
        inc e
        ld a, (hl)
        ld (de), a
        ret

; GetSectionCoords: inner and outer start coordinates of section B/8 into
; entry C, sets thisVectorNumber, then CopySectionData.

GetSectionCoords:
        call GetSectionCoord
        ld h, trackSectionFlag / 256
        ld a, b
        add a, 4
        ld l, a                         ; xTrackSectionOLo + Y
        ld d, SEG_LO / 256
        ld a, c
        add a, xSegmentCoordO
        ld e, a
        ld a, (hl)
        ld (de), a                      ; xSegmentCoordOLo
        inc l
        ld a, (hl)
@tcSite:                                ; (track code: call HookSectionFrom)
        ld (thisVectorNumber), a        ; trackSectionFrom
        inc l
        inc e
        inc e
        ld a, (hl)
        ld (de), a                      ; zSegmentCoordOLo
        ld h, trackSectionData / 256
        dec l
        dec l                           ; xTrackSectionOHi + Y
        inc d
        dec e
        dec e
        ld a, (hl)
        ld (de), a
        inc l
        inc l
        inc e
        inc e
        ld a, (hl)
        ld (de), a                      ; zSegmentCoordOHi
        ; fall through

; CopySectionData: ySegmentCoordO[C] = ySegmentCoordI[C]

CopySectionData:
        ld h, SEG_LO / 256
        ld a, c
        inc a
        ld l, a
        ld a, (hl)
        ld e, a
        inc h
        ld a, (hl)
        ld d, a
        ld a, l
        add a, xSegmentCoordO
        ld l, a
        ld (hl), d
        dec h
        ld (hl), e
        ret

; GetPlayerIndex: playerSegmentIndex = frontSegmentIndex - 96 (mod 120)

GetPlayerIndex:
        ld a, (frontSegmentIndex)
        sub 96
        jr nc, @ok
        add a, 120
@ok:
        ld (playerSegmentIndex), a
        ret

; GetFirstSegment: called when the front segment enters a new section.

GetFirstSegment:
        ld a, (frontSegmentIndex)
        ld c, a
        ld a, 6
        ld (newSectionFetched), a
        ld a, (resetSectionList)
        or a
        jr z, @getf1
        ld a, 6
        ld (sectionListValid), a
@getf1:
        ld a, (directionFacing)
        or a
        jp m, @getf2
        ld a, (OBJ_SECTION + 23)
        ld b, a
        call GetSectionCoords
        ld h, trackSectionData / 256
        ld l, b
        ld a, (hl)
        jr @getf3
@getf2:
        ld a, (sectionBehind)
        ld b, a
        call GetSectionCoords
@tcSite:                                ; (track code: HookFirstSegment)
        call UpdateVectorNumber
        ld a, 2
@getf3:
        and 7
        ld (sectionListSize), a
        ld a, (OBJ_SECTION + 23)
        ld l, a
        ld h, trackSectionFlag / 256
        ld a, (hl)
        ld (thisSectionFlags), a
        ld h, SEGDATA / 256
        ld a, c
        add a, 2
        ld l, a
        ld (hl), 0                      ; segmentFlags[X] = 0
        ret

; ShuffleSectionList: move the section entries of both verge lists up by one

ShuffleSectionList:
        ld hl, VERGE_XLO + 44
        call @shuffle
        ld hl, VERGE_XLO + 4
        call @shuffle
        ld a, (sectionListSize)
        neg
        add a, 6
        ld (sectionListStart), a
        jp IncSectionPointers
@shuffle:                               ; entries L-4..L move to L-3..L+1
        ld b, 5
@s1:
        ld a, (hl)                      ; xVergeLo
        inc l
        ld (hl), a
        dec l
        inc h
        ld a, (hl)                      ; xVergeHi
        inc l
        ld (hl), a
        dec l
        ld h, VERGE_Y / 256
        ld a, (hl)
        inc l
        ld (hl), a
        dec l
        ld h, VERGE_XLO / 256
        dec l
        djnz @s1
        ret

; IncSectionPointers / SetSectionPointers

IncSectionPointers:
        ld a, (sectionListValid)
        inc a
        cp 6
        jr c, @i1
        ld a, 6
@i1:
        ld hl, sectionListStart
        cp (hl)
        jr nc, @i2
        ld a, (hl)
@i2:
        ld (sectionListValid), a
        ld a, (sectionListPointer)
        inc a
SetSectionPointers:                     ; in: A = X
        inc a
        ld hl, sectionListValid
        cp (hl)
        jr nc, @secp1
        ld (hl), a
@secp1:
        dec a
        ld hl, sectionListStart
        cp (hl)
        jr nc, @secp2
        ld a, 5
@secp2:
        cp 6
        jr c, @secp3
        ld a, 5
@secp3:
        ld (sectionListPointer), a
        ret

; ---------------------------------------------------------------------------
; MovePlayerForward: move the player one segment along the track and add a new
; front segment to the buffer.

MovePlayerForward:
        or a                            ; CLC
        call MovePlayer
        ; fall through

; GetTrackSegment: add the next segment at the front of the segment buffer

GetTrackSegment:                        ; (track code: call HookDataPointers)
        ld a, (frontSegmentIndex)
        ld (prevSegmentIndex), a
        add a, 3
        cp 120
        jr c, @g1
        xor a
@g1:
        ld (frontSegmentIndex), a
        ld a, (directionFacing)
        or a
        jp m, @gets3
        ld a, (OBJ_SECTION + 23)
        ld hl, trackHalfwaySection
        cp (hl)
        jr nz, @gets2
        ld a, 1
        ld (pastHalfway), a
@gets2:
        ld a, 23
        call MoveObjectForward
        jr nc, @gets4
        call GetFirstSegment
        jp @gets13
@gets3:
        ld a, (OBJ_SECTION + 23)
        ld (sectionBehind), a
        ld a, 23
        call MoveObjectBack
        call c, GetFirstSegment
@gets4:
        ld a, (thisVectorNumber)
        call GetSegmentVector

        ; Part 2: segment flags (corner markers)
        ld a, (frontSegmentIndex)
        ld c, a
        ld a, (thisSectionFlags)
        ld e, a                         ; E = thisSectionFlags
        rra
        ld a, e
        jr c, @f2
        ld b, a
        ld a, (OBJ_SEGMT + 23)
        cp 1
        jr c, @f1
        cp 10
        ld a, b
        jr c, @f2
@f1:
        ld a, b
        and %11111001
@f2:
        ld d, a                         ; D = W
        ld a, c
        rra
        ld b, 1
        jr c, @straightTest             ; odd front index: no markers
        ld a, (OBJ_SECTION + 23)
        ld l, a
        ld h, trackSectionSize / 256
        ld a, l
        add a, trackSectionSize & $FF
        ld l, a
        ld a, (hl)                      ; trackSectionSize
        bit 0, e
        jr z, @straight
        srl a                           ; curve: markers at size/2, size/2+1
        ld b, a
        ld a, (OBJ_SEGMT + 23)
        cp b
        jr z, @f10
        inc b
        cp b
        jr z, @f10
        jr @f8
@straight:
        ld hl, OBJ_SEGMT + 23
        sub (hl)
        srl a
        ld b, a
@straightTest:
        ld a, b
        cp 3
        jr z, @f10
        cp 7
        jr z, @f9
        cp 11
        jr z, @f9
@f8:
        ld a, d
        and %11100111
        ld d, a
@f9:
        ld a, d
        and %11011111
        ld d, a
@f10:
        ld a, d
        and e
        ld h, SEGDATA / 256
        ld l, c
        inc l
        inc l
        ld (hl), a                      ; segmentFlags[X]

        ; Part 3: coordinates of the new segment
        ld a, (prevSegmentIndex)
        ld b, a
        call AddVectors                 ; X = C, Y = B
        call CopySectionData
        ld a, (thisVectorNumber)
        ld l, a
        ld h, xTrackSegmentO / 256
        ld e, (hl)
        call @times4                    ; DE = 4 * signed xTrackSegmentO
        ld h, SEG_LO / 256
        ld l, c
        ld a, (hl)
        add a, e
        ld b, a
        inc h
        ld a, (hl)
        adc a, d
        ld d, a
        ld a, c
        add a, xSegmentCoordO
        ld l, a
        ld (hl), d
        dec h
        ld (hl), b
        ld a, (thisVectorNumber)
        ld l, a
        ld h, zTrackSegmentO / 256
        ld e, (hl)
        call @times4
        ld h, SEG_LO / 256
        ld a, c
        add a, 2
        ld l, a
        ld a, (hl)
        add a, e
        ld b, a
        inc h
        ld a, (hl)
        adc a, d
        ld d, a
        ld a, l
        add a, xSegmentCoordO
        ld l, a
        ld (hl), d
        dec h
        ld (hl), b
@tcSite:                                ; (track code: HookSegmentVector)
        call UpdateCurveVector
@gets13:
        ld a, (frontSegmentIndex)
        ld l, a
        ld h, SEGDATA / 256
        ld a, (thisVectorNumber)
        ld (hl), a                      ; segmentVector[front]
        call GetPlayerIndex
        jp GetSegmentSteering

@times4:                                ; DE = 4 * (signed) E
        ld a, e
        rla
        sbc a, a
        ld d, a
        ex de, hl
        add hl, hl
        add hl, hl
        ex de, hl
        ret

; UpdateCurveVector: next segment vector, curves only
; UpdateVectorNumber: next segment vector in the direction we are facing

UpdateCurveVector:
        ld a, (thisSectionFlags)
        and 1
        ret z
UpdateVectorNumber:
        ld a, (directionFacing)
        or a
        ld a, (thisVectorNumber)
        jp m, @back
        inc a
        ld hl, trackVectorCount
        cp (hl)
        jr nz, @store
        xor a
        jr @store
@back:
        or a
        jr nz, @b1
        ld a, (trackVectorCount)
@b1:
        dec a
@store:
        ld (thisVectorNumber), a
        ret

; ChangeDirection: rebuild the buffer when the car turns round on the track

ChangeDirection:
        ld a, 6
        ld (sectionListValid), a
        ld a, 64
        ld (debugSpinning), a
        call TurnPlayerAround
        xor a
        ld (debugSpinning), a
        ret

; MovePlayerBack: move the player back one segment and rebuild the buffer

MovePlayerBack:
        scf
        call MovePlayer
        ld a, 40
        ld (resetSectionList), a
        call TurnPlayerAround
        ld a, 39
        call TurnPlayerAround
        xor a
        ld (resetSectionList), a
        ret

; TurnPlayerAround: flip directionFacing and fetch A new segments

TurnPlayerAround:
        ld (segmentCounter), a
        ld a, (directionFacing)
        xor $80
        ld (directionFacing), a
@tcSite:                                ; (track code: HookSegmentVector)
        call UpdateCurveVector
@t1:
        call GetTrackSegment
        ld hl, segmentCounter
        dec (hl)
        jr nz, @t1
        ret

; MovePlayer: carry clear = forwards, set = backwards (relative to the facing
; direction)

MovePlayer:
        rra
        ld hl, directionFacing
        xor (hl)
        ld a, (currentPlayer)
        jp m, MoveObjectBack
        ; fall through to MoveObjectForward

; ---------------------------------------------------------------------------
; MoveObjectForward: move object A forward by one segment.
; Returns carry set if the object moved into a new section.
; Preserves BC, DE. Sets IX for object A.

MoveObjectForward:
        OBJ_INDEX
        ld l, (ix + objTrackSection)
        ld h, trackSectionSize / 256
        ld a, l
        add a, trackSectionSize & $FF
        ld l, a
        ld a, (ix + objSectionSegmt)
        inc a
        cp (hl)
        jr c, @fore2
        ld a, (ix + objTrackSection)
        add a, 8
        ld hl, trackSectionCount
        cp (hl)
        jr c, @f1
        xor a
@f1:
        ld (ix + objTrackSection), a
        xor a
        ld (ix + objSectionSegmt), a
        call @incSegment
        scf
        ret
@fore2:
        ld (ix + objSectionSegmt), a
        call @incSegment
        or a
        ret
@incSegment:                            ; objectSegment++, wrap at trackLength
        ld l, (ix + objectSegmentLo)
        ld h, (ix + objectSegmentHi)
        inc hl
        ld (ix + objectSegmentLo), l
        ld (ix + objectSegmentHi), h
        ld a, (trackLength)
        cp l
        ret nz
        ld a, (trackLength + 1)
        cp h
        ret nz
        xor a
        ld (ix + objectSegmentLo), a
        ld (ix + objectSegmentHi), a
        jp UpdateLaps

; MoveObjectBack: move object A back by one segment.
; Returns carry set if the object moved into the previous section.

MoveObjectBack:
        OBJ_INDEX
        ld a, (ix + objSectionSegmt)
        or a
        jr nz, @back2
        ld a, (ix + objTrackSection)
        or a
        jr nz, @back1
        ld a, (trackSectionCount)
@back1:
        sub 8
        ld (ix + objTrackSection), a
        add a, trackSectionSize & $FF
        ld l, a
        ld h, trackSectionSize / 256
        ld a, (hl)
        dec a
        ld (ix + objSectionSegmt), a
        call @decSegment
        scf
        ret
@back2:
        dec a
        ld (ix + objSectionSegmt), a
        call @decSegment
        or a
        ret
@decSegment:
        ld l, (ix + objectSegmentLo)
        ld h, (ix + objectSegmentHi)
@d1:
        ld a, l
        or a
        jr nz, @d2
        dec h
        jp p, @d2
        ld hl, (trackLength)
        ld a, ixl
        sub OBJ_BIAS
        push hl
        ld hl, currentPlayer
        cp (hl)
        pop hl
        jr nz, @d1
        push hl                         ; player wrapped back over the line
        ld h, DRIVER_LAPNUMBER / 256
        add a, DRIVER_LAPNUMBER % 256
        ld l, a
        ld a, (hl)
        or a
        jr z, @d3
        dec (hl)
@d3:
        pop hl
        jr @d1
@d2:
        dec l
        ld (ix + objectSegmentLo), l
        ld (ix + objectSegmentHi), h
        ret

; ---------------------------------------------------------------------------
; GetSegmentVector: fetch segment vector A into vecX/vecY/vecZ (16-bit,
; sign-extended), negated when facing backwards.

GetSegmentVector:
        ld l, a
        ld h, xTrackSegmentI / 256
        ld a, (directionFacing)
        or a
        jr nz, @neg
        ld a, (hl)
        call @sx
        ld (vecX), de
        inc h
        ld a, (hl)
        call @sx
        ld (vecY), de
        inc h
        ld a, (hl)
        call @sx
        ld (vecZ), de
        ret
@neg:
        ld a, (hl)
        call @sxn
        ld (vecX), de
        inc h
        ld a, (hl)
        call @sxn
        ld (vecY), de
        inc h
        ld a, (hl)
        call @sxn
        ld (vecZ), de
        ret
@sx:
        ld e, a
        rla
        sbc a, a
        ld d, a
        ret
@sxn:                                   ; DE = -(signed A)
        call @sx
        xor a
        sub e
        ld e, a
        sbc a, a
        sub d
        ld d, a
        ret

; AddVectors: segment coordinate C = segment coordinate B + vec

AddVectors:
        ld h, SEG_LO / 256
        ld d, h
        ld l, b
        ld e, c
        push bc
        ld bc, (vecX)
        call @add
        ld bc, (vecY)
        call @add
        ld bc, (vecZ)
        call @add
        pop bc
        ret
@add:
        ld a, (hl)
        add a, c
        ld (de), a
        inc h
        inc d
        ld a, (hl)
        adc a, b
        ld (de), a
        dec h
        dec d
        inc l
        inc e
        ret

; ---------------------------------------------------------------------------
; GetSegmentSteering: optimum steering for the new front segment

GetSegmentSteering:
        ld a, (OBJ_SECTION + 23)
        ld b, a                         ; Y
        rrca
        rrca
        rrca
        and $1F
        ld c, a                         ; X
        ld a, (turnCounter)
        or a
        jr nz, @rlin5
        ld a, (thisSectionFlags)
        rra
        jr c, @rlin2
        ld a, b
        add a, trackSectionTurn & $FF
        ld l, a
        ld h, trackSectionTurn / 256
        ld a, (OBJ_SEGMT + 23)
        cp (hl)
        jr nc, @rlin3
@rlin1:
        ld hl, sectionSteering
        ld a, c
        call @index
        or $40
        jr @rlin7
@rlin2:
        ld a, (prevDriverSpeed7)
        or a
        jp m, @rlin4
@rlin3:
        ld a, b
        add a, 8
        ld b, a
        inc c
@rlin4:
        ld l, b
        ld h, trackSectionFlag / 256
        bit 0, (hl)
        jr z, @rlin1
        ld h, trackSectionTurn / 256
        ld a, b
        add a, trackSectionTurn & $FF
        ld l, a
        ld a, (hl)
        ld (turnCounter), a
        or a
        jr z, @rlin1
        inc l
        inc l                           ; trackDriverSpeed
        ld a, (hl)
        ld (prevDriverSpeed7), a
        and $7F
        ld (prevDriverSpeed06), a
        ld hl, sectionSteering
        ld a, c
        call @index
        ld (previousSteering), a
        jr @rlin7
@rlin5:
        dec a
        ld (turnCounter), a
        ld e, a
        rrca
        rrca
        rrca
        and $1F
        ld d, a                         ; T = turnCounter >> 3
        ld a, (prevDriverSpeed06)
        ld b, a
        ld a, e
        sub b
        jr nc, @r6                      ; no borrow: previousSteering
        add a, d
        ld a, 0
        jr c, @rlin7
        ld a, (previousSteering)
        xor $80
        jr @rlin7
@r6:
        ld a, (previousSteering)
@rlin7:
        ld b, a
        ld a, (frontSegmentIndex)
        inc a
        ld l, a
        ld h, SEGDATA / 256
        ld (hl), b                      ; segmentSteering[front]
        ret
@index:                                 ; A = (HL + A)
        add a, l
        ld l, a
        jr nc, @i1
        inc h
@i1:
        ld a, (hl)
        ret
