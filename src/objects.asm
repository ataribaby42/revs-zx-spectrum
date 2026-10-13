; Car objects: positions, angles and object types (C64 versions)
;
; Objects 0-19 are the cars, 20-22 the extra parts of the four-object car
; (the nearest car ahead), 23 the road sign. The 3D coordinates of the car
; being built live in the segment buffer at xCoord2 ($FD), xCoord1 ($FA) and
; xHelmetCoord ($F4).

; CAR_AXIS axis: segment buffer coordinate xCoord2 + axis = inner verge
; coordinate (segment E) + signed vector
; component (BC: xTrackSegmentI + axis page, C = vector number) * D / 256.
; Advances B to the next axis page.

; ---------------------------------------------------------------------------
; MoveAndDrawCars: move the other cars, then build and draw the five cars
; ahead of the player (behind when facing backwards) and the car behind

MoveAndDrawCars:
        ld a, (qualifyingTime)
        or a
        ret m                           ; practice: no other cars
        ld a, (positionBehind)
        add a, DRIVERS_IN_ORDER % 256
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (hl)
        add a, OBJ_STATUS % 256
        ld l, a
        ld h, OBJ_STATUS / 256
        res 7, (hl)
        call MoveCars
        call ProcessOvertaking
        call HideAllCars
        call SetPlayerPositions
        ld a, (currentPosition)
        ld c, a
        ld b, 4
@dcar1:
        ld a, (directionFacing)
        or a
        jp p, @dcar2
        call GetPositionBehind
        jr @dcar3
@dcar2:
        call GetPositionAhead
@dcar3:
        ld a, b
        ld (thisDriverNumber), a
        ld a, c
        ld (thisPosition), a
        call BuildVisibleCar
        ld a, (thisPosition)
        ld c, a
        ld a, (thisDriverNumber)
        ld b, a
        dec b
        jp p, @dcar1
        call DrawCars
        ld a, (positionBehind)
        ld c, a
        jp BuildVisibleCar

; HideAllCars: hide objects 0-22
HideAllCars:
        ld hl, OBJ_STATUS
        ld b, 23
@h1:
        set 7, (hl)
        inc l
        djnz @h1
        ret

; ---------------------------------------------------------------------------
; BuildVisibleCar: C = race position. Builds the object(s) of that car if it
; is within the track segment buffer, otherwise hides it.

BuildVisibleCar:
        ld a, DRIVERS_IN_ORDER % 256
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (hl)
        ld (driverPrinted), a
        ld (colourScheme), a
        ld c, a                         ; C = driver (6502 X)
        ld b, 23
        scf
        call CompareSegments            ; distance from the car to object 23
        jp c, HideObject
        ld hl, directionFacing
        xor (hl)
        jp m, HideObject                ; beyond the front of the buffer
        ld a, (T)
        or a
        jp p, @b1
        neg
@b1:
        ld (T), a
        cp 40
        jp nc, HideObject
        ld b, a                         ; segment buffer index = front - 3 * T
        add a, a
        add a, b
        ld b, a
        ld a, (frontSegmentIndex)
        sub b
        jp p, @b2
        add a, 120
@b2:
        ld e, a                         ; E = segment index (6502 Y)
        ld a, c
        CAR_INDEX
        bit 4, (iy + carStatus)
        jr nz, BuildCarObjects
        ld a, (iy + carSpeedHi)
        cp $48
        jr c, BuildCarObjects
        ld h, segmentSteering / 256      ; fast cars follow the track
        ld a, e
        add a, segmentSteering % 256
        ld l, a
        ld a, (hl)
        ld (iy + carSteering), a
        ; fall through

; BuildCarObjects: E = segment index, C = driver, IY = car. Projects the car
; and, for the nearest car ahead, the three extra four-object car parts.

BuildCarObjects:
        ld h, segmentVector / 256
        ld l, e
        ld a, (hl)
        ld (vectorNumber), a
        ld (@vec1 + 1), a
        ld (@vec2 + 1), a
        ; car position = inner verge + inner segment vector * progress / 256
        ld d, (iy + carProgress)
        ld bc, xTrackSegmentI           ; C = vector number (patched below)
@vec1:
        ld c, 0
        CAR_AXIS 0
        ; CAR_AXIS 1, written out (the AND is a track code site)
        ld a, (bc)
        inc b
        push bc
        push de
        call MulSignedHi                ; (B A)
        pop de
        ld c, a
        ld a, e
        add a, 1
        ld l, a
        ld h, SEG_HI / 256
        ld a, (hl)
@tcHeightCap:                           ; (track code: AND $FF, Nurburgring)
        and $1F
        add a, b
        ld b, a
        dec h
        ld a, (hl)
        add a, c
        ld l, xCoord2 + 1
        ld (hl), a
        inc h
        ld a, b
        adc a, 0
        ld (hl), a
        pop bc
        CAR_AXIS 2
        ; ... + outer segment vector * racing line * 4 / 256 (x and z)
        ld d, (iy + carRacingLine)
@vec2:
        ld l, 0
        ld h, xTrackSegmentO / 256
        ld a, (hl)
        push hl
        CAR_OUTER 0
        pop hl
        inc h
        ld a, (hl)
        CAR_OUTER 2
        ld hl, SEG_LO + xCoord2 + 1     ; raise the car
        ld a, (hl)
        add a, $90
        ld (hl), a
        jr nc, @b8
        inc h
        inc (hl)
@b8:
        ld a, 4
        ld c, xCoord2
        call GetObjectAngles
        ld a, (driverPrinted)
        ld c, a
        ld a, (objectDistanceHi)
        cp 3
        jr nc, @bcar11
        ld a, (thisPosition)
        ld hl, positionAhead
        cp (hl)
        ret nz
        ld a, c                         ; nearest car ahead: four-object car
        add a, OBJ_STATUS % 256
        ld l, a
        ld h, OBJ_STATUS / 256
        bit 7, (hl)
        jr nz, @bcar9
        dec (hl)                        ; type 4 -> 3 (rear wing)
@bcar9:
        ld a, (vectorNumber)
        call GetSegmentVector
        call HalveCoordinate
        ld b, xCoord2
        ld c, xCoord1
        call AddVectors                 ; front tyres: + vector / 2
        call HalveCoordinate
        ld c, xHelmetCoord
        call AddVectors                 ; body and helmet: + vector / 4
        call HalveCoordinate
        ld c, xCoord2
        call AddVectors                 ; rear tyres: + vector / 8
        ld a, 20
        ld (colourScheme), a
        ld a, 2
        ld c, xCoord2
        call GetObjectAngles
        ld a, 21
        ld (colourScheme), a
        ld a, 1
        ld c, xHelmetCoord
        call GetObjectAngles
        ld a, 22
        ld (colourScheme), a
        xor a
        ld c, xCoord1
        call GetObjectAngles
        ld a, (driverPrinted)
        ld c, a
        ret
@bcar11:
        cp 5
        ret c
        ld a, c                         ; far away: type 4 -> 5 (distant car)
        add a, OBJ_STATUS % 256
        ld l, a
        ld h, OBJ_STATUS / 256
        bit 7, (hl)
        ret nz
        inc (hl)
        ret

; MulSignedHi: (B A) = signed A * D / 256 as the C64 computes it (high byte
; of |A| * D, negated, B = sign extension). Preserves D; corrupts C, E, HL.
MulSignedHi:
        or a
        jp p, @pos
        neg
        call HiMul
        neg
        ld b, 0
        ret z
        dec b
        ret
@pos:
        call HiMul
        ld b, 0
        ret

; HiMul: A = high byte of A * D (unsigned, quarter squares as Multiply8x8T).
; Preserves D; corrupts BC, E, HL.
HiMul:
        ld e, a
        add a, d
        ld l, a
        ld a, QSQ_LO / 256
        adc a, 0
        ld h, a
        ld c, (hl)
        inc h
        inc h
        ld b, (hl)                      ; BC = Q[a + d]
        ld a, e
        sub d
        jr nc, @p
        neg
@p:
        ld l, a
        ld h, QSQ_LO / 256
        ld a, c
        sub (hl)
        inc h
        inc h
        ld a, b
        sbc a, (hl)
        ret

; ---------------------------------------------------------------------------
; GetObjectAngles: A = object type, C = segment buffer coordinate index.
; Projects the coordinate into object colourScheme: yaw, pitch, size, type.

GetObjectAngles:
        ld (objectType), a
        call GetObjYawAngle
        ld a, (colourScheme)
        add a, OBJ_YAWLO % 256
        ld l, a
        ld h, OBJ_YAWLO / 256
        ld a, (II)
        ld (hl), a
        ld a, l
        add a, 24
        ld l, a
        ld a, (JJ)
        ld (hl), a
        ld b, $25
        call CheckForContactB
        call GetObjPitchAngle
        ; fall through

; SetObjectDetails: carry set = not visible, else A = pitch angle (LL)
SetObjectDetails:
        jr c, HideObject
        sub 1
        jp m, HideObject
        ld b, a
        ld a, (colourScheme)
        add a, OBJ_PITCH % 256
        ld l, a
        ld h, OBJ_PITCH / 256
        ld (hl), b
        ld a, (scaleDown)               ; size = scaleUp * 2^(scaleDown - 10)
        sub 10
        ld b, a
        ld a, (scaleUp)
        jr z, @sobj3
        jp p, @sobj2
@sobj1:
        srl a
        inc b
        jr nz, @sobj1
        jr @sobj3
@sobj2:
        add a, a
        djnz @sobj2
@sobj3:
        ld b, a
        ld a, (colourScheme)
        add a, OBJ_SIZE % 256
        ld l, a
        ld (hl), b
        ld a, (colourScheme)
        add a, OBJ_STATUS % 256
        ld l, a
        ld a, (hl)
        and $70
        ld b, a
        ld a, (objectType)
        or b
        ld (hl), a
        ret

; HideObject: hide object colourScheme
HideObject:
        ld a, (colourScheme)
        add a, OBJ_STATUS % 256
        ld l, a
        ld h, OBJ_STATUS / 256
        set 7, (hl)
        ret

; CheckForContactB: after GetObjYawAngle, note a possible collision with
; object colourScheme if it is closer than B
CheckForContactB:
        ld a, (Lv)
        ld (objectDistanceHi), a
        or a
        ret nz
        ld a, (K)
        cp b
        jr z, @c1
        ret nc
@c1:
        ld (objectDistanceLo), a
        ld hl, processContact
        dec (hl)
        ld a, (colourScheme)
        ld (collisionDriver), a
        ret

; HalveCoordinate: vecX/Y/Z = vecX/Y/Z / 2 (signed). Preserves BC, DE.
HalveCoordinate:
        ld hl, vecX + 1
        sra (hl)
        dec hl
        rr (hl)
        ld hl, vecY + 1
        sra (hl)
        dec hl
        rr (hl)
        ld hl, vecZ + 1
        sra (hl)
        dec hl
        rr (hl)
        ret


; ---------------------------------------------------------------------------
; DrawCars: draw the cars from the furthest ahead to the nearest

DrawCars:
        ld a, (currentPosition)
        ld c, a
        or a
        jp p, @c2
@c1:
        call DrawCarInPosition
@c2:
        call GetPositionBehind
        ld a, (positionAhead)
        cp c
        jr nz, @c1
        ld c, 22                        ; the four-object car parts
@c3:
        ld a, c
        ld (driverPrinted), a
        call DrawCarOrSign
        ld a, (driverPrinted)
        dec a
        ld c, a
        cp 20
        jr nc, @c3
        ld a, (positionAhead)
        ld c, a
        ; fall through

; DrawCarInPosition: C = race position (preserved)
DrawCarInPosition:
        ld a, c
        ld (driverPrinted), a
        add a, DRIVERS_IN_ORDER % 256
        ld l, a
        ld h, CAR_PAGE / 256
        ld c, (hl)
        call DrawCarOrSign
        ld a, (driverPrinted)
        ld c, a
        ret
