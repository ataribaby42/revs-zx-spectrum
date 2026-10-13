; Computer-controlled cars (C64 versions)
;
; Per car C: IX = object entry, IY = car entry (OBJ_INDEX / CAR_INDEX).

; ---------------------------------------------------------------------------
; MoveCars: speed, progress and racing line of all non-player cars

MoveCars:
        ld a, (raceStarting)
        or a
        ret m
        ld hl, 0                        ; not a race: NOP / NOP
        ld a, (raceStarted)
        or a
        jp p, @m0
        ld a, (trackRaceSlowdown)
        ld h, a
        ld l, $DE                       ; a race: SBC A, trackRaceSlowdown
@m0:
        ld (@slow), hl
        ld c, 20
        ld a, c
        OBJ_INDEX
        ld a, c
        CAR_INDEX
        jp @mcar20

@mcar1:
        ld a, (iy + carStatus)
        or a
        jp m, @mcar8                    ; car stopped: brake
        ld e, (ix + objTrackSection)
        ld h, trackSectionFlag / 256
        ld l, e
        ld a, (hl)
        or a
        jp p, @mcar2
        ld a, (iy + carSpeedHi)         ; flag bit 7: keep the section speed
        cp (iy + carSectionSpeed)
        jr c, @mcar3
        jp @mcar11
@mcar2:
        srl a
        jr c, @mcar3                    ; flag bit 0: no braking in section
        ld h, trackDriverSpeed / 256
        ld a, e
        add a, trackDriverSpeed % 256
        ld l, a
        ld a, (hl)
        ld (iy + carSectionSpeed), a
        scf
        sbc a, (iy + carSpeedHi)
        jr nc, @mcar3                   ; section speed above car speed
        srl a
        srl a
        or $C0
        ld (T), a                       ; braking distance (negative)
        ld a, e
        add a, trackSectionTurn % 256
        ld l, a
        ld a, (ix + objSectionSegmt)
        sub (hl)
        jr nc, @past                    ; past the turn: keep the speed
        ld hl, T
        cp (hl)
        jr nc, @mcar8                   ; within braking distance: brake
@mcar3:
        ld a, (iy + carSpeedHi)         ; accelerate towards driverSpeed
        cp $57
        jr nc, @m3a
        ld a, $20
@m3a:
        ld (T), a
        ld e, a                         ; E = T
        ld a, (iy + carStatus)
        and $40
        jr z, @mcar5
        ld a, 7                         ; overtaking boost
@mcar5:
        add a, (iy + driverSpeed)
        ccf                             ; Z80 borrow = not 6502 carry
@slow:
        sbc a, 0                        ; patched: SBC A, n in a race, else
                                        ; NOP / NOP
        sub e                           ; - T
        ld h, 0
        jr nc, @accel
        dec h
        jr @accel
@past:
        ld a, (iy + carSpeedHi)
        jr @mcar11
@mcar8:
        ld h, $FE                       ; brake
        ld a, $DC
@accel:
        ld l, a                         ; speed += 4 * (H A)
        add hl, hl
        add hl, hl
        ld a, h
        ld (U), a
        ld a, l
        add a, (iy + carSpeedLo)
        ld (iy + carSpeedLo), a
        ld a, h
        adc a, (iy + carSpeedHi)
        cp $F5
        jr c, @m10
        xor a                           ; below zero: stop
        ld (iy + carSpeedLo), a
@m10:
        ld (iy + carSpeedHi), a
@mcar11:
        ld l, a                         ; progress += 2 * speed, moving 0-2
        ld h, 0                         ; segments
        add hl, hl
        ld e, (iy + carProgress)
        ld d, 0
        add hl, de
        ld (iy + carProgress), l
        ld a, h
        or a
        jp z, @mcar13
        cp 2
        jr nc, @move2
        ld l, (ix + objectSegmentLo)    ; one segment
        ld h, (ix + objectSegmentHi)
        inc hl
        ld (ix + objectSegmentLo), l
        ld (ix + objectSegmentHi), h
        ld de, (trackLength)
        or a
        sbc hl, de
        jr nz, @m1b
        call UpdateLaps
        xor a
        ld (ix + objectSegmentLo), a
        ld (ix + objectSegmentHi), a
@m1b:
        ld e, (ix + objTrackSection)
        ld h, trackSectionSize / 256
        ld a, e
        add a, trackSectionSize % 256
        ld l, a
        ld a, (ix + objSectionSegmt)
        inc a
        cp (hl)
        jr c, @m1c
        ld a, e
        add a, 8
        ld hl, trackSectionCount
        cp (hl)
        jr c, @m1d
        xor a
@m1d:
        ld (ix + objTrackSection), a
        xor a
@m1c:
        ld (ix + objSectionSegmt), a
        jr @mcar13

@move2:                                 ; two segments
        ld l, (ix + objectSegmentLo)
        ld h, (ix + objectSegmentHi)
        ld de, (trackLength)
        inc hl
        ld a, l
        cp e
        jr nz, @m2a
        ld a, h
        cp d
        jr nz, @m2a
        call UpdateLaps
        ld hl, 1
        jr @m2s
@m2a:
        inc hl
        ld a, l
        cp e
        jr nz, @m2s
        ld a, h
        cp d
        jr nz, @m2s
        call UpdateLaps
        ld hl, 0
@m2s:
        ld (ix + objectSegmentLo), l
        ld (ix + objectSegmentHi), h
        ld e, (ix + objTrackSection)
        ld h, trackSectionSize / 256
        ld a, e
        add a, trackSectionSize % 256
        ld l, a
        ld a, (ix + objSectionSegmt)
        add a, 2
        ld (ix + objSectionSegmt), a
        cp (hl)
        jr c, @mcar13
        sub (hl)
        ld (ix + objSectionSegmt), a
        ld a, e
        add a, 8
        ld hl, trackSectionCount
        cp (hl)
        jr c, @m2d
        xor a
@m2d:
        ld (ix + objTrackSection), a

@mcar13:                                ; steer towards the racing line
        ld a, (ix + objectStatus)
        add a, a
        jr c, @mcar20
        jp m, @mcar17
        ld a, (iy + carSteering)
        and $40
        jr z, @mcar17
        ld a, (iy + carRacingLine)
        xor (iy + carSteering)
        jp p, @mcar17
        ld a, (iy + carRacingLine)
        or a
        jp p, @mcar15
        cp $EC
        jr c, @m14
        dec (iy + carRacingLine)
        jr @mcar20
@m14:
        cp $E2
        jr c, @mcar17
        jr @mcar20
@mcar15:
        cp $14
        jr nc, @m16
        inc (iy + carRacingLine)
        jr @mcar20
@m16:
        cp $1E
        jr c, @mcar20
@mcar17:
        ld a, (iy + carSteering)
        and $BF
        jp p, @m18
        xor $7F
        add a, (iy + carRacingLine)
        jr c, @m19
        jr @mcar20
@m18:
        add a, (iy + carRacingLine)
        jr c, @mcar20
@m19:
        ld (iy + carRacingLine), a
@mcar20:
        dec c
        ret m
        dec ixl                         ; IX, IY: the entries of car C
        dec iyl
        ld a, (currentPlayer)
        cp c
        jr z, @mcar20
        jp @mcar1

; ---------------------------------------------------------------------------
; ProcessOvertaking: for each car and the car ahead of it in the race order,
; swap positions when it has passed, otherwise steer to overtake when it is
; faster and close behind. carStatus gets the new overtaking state.
;
; Per position: IY = car X (this car), IX = car Y (the car ahead).

ProcessOvertaking:
        ld ixh, CAR_PAGE / 256
        ld iyh, CAR_PAGE / 256
        ld a, (currentPosition)
        ld c, a
@tact1:
        ld a, c
        ld (W), a
        ld h, CAR_PAGE / 256
        add a, DRIVERS_IN_ORDER % 256
        ld l, a
        ld a, (hl)
        ld (T), a
        ld e, a                         ; E = car X
        dec c                           ; C = the position ahead
        jp p, @pa
        ld c, 19
@pa:
        ld a, DRIVERS_IN_ORDER % 256
        add a, c
        ld l, a
        ld d, (hl)                      ; D = car Y
        ld a, c
        ld (G), a
        ld a, e
        add a, OBJ_BIAS
        ld iyl, a
        ld a, d
        add a, OBJ_BIAS
        ld ixl, a
        xor a
        ld (N), a
        ld (iy + carSteering), a
        ld a, $80
        ld (Hv), a
        ; distance from X to Y in segments (C64: inline CompareCarSegments)
        ld h, OBJ_PAGE / 256
        ld a, OBJ_SEGLO % 256
        add a, e
        ld l, a
        ld c, (hl)
        add a, 24
        ld l, a
        ld b, (hl)                      ; BC = segment of X
        ld a, OBJ_SEGLO % 256
        add a, d
        ld l, a
        ld e, (hl)
        add a, 24
        ld l, a
        ld d, (hl)
        ex de, hl                       ; HL = segment of Y
        ld a, (ix + carProgress)        ; (the borrow of the progress)
        sub (iy + carProgress)
        sbc hl, bc
        jp m, @neg
        ld a, h
        or a
        jr z, @ps
        ld (U), a                       ; Y more than 255 ahead: try behind
        ex de, hl
        ld hl, (trackLength)
        or a
        sbc hl, de
        ld a, l
        ld (T), a
        ld a, h
        or a
        scf
        jr nz, @cmp
        ld hl, Hv
        srl (hl)
@ng:
        ld a, (T)
        cp $80
        ccf
        jr c, @cmp
        neg
        ld (T), a
        or a
        jr @cmp
@ps:
        ld a, l
        ld (T), a
        cp $80
        ccf
        jr @cmp
@neg:
        ld a, h
        ld (U), a
        xor a
        sub l
        ld l, a
        ld a, 0
        sbc a, h
        ld h, a
        ld a, l
        ld (T), a
        ld a, h
        or a
        jr z, @ng
        ld (U), a                       ; Y more than 255 behind: try ahead
        ex de, hl
        ld hl, (trackLength)
        or a
        sbc hl, de
        ld a, l
        ld (T), a
        ld a, h
        or a
        scf
        jr nz, @cmp
        ld hl, Hv
        srl (hl)
        ld a, (T)
        cp $80
        ccf
@cmp:
        jp c, @tact18x                  ; too far apart
        or a
        jp p, @tact5
        cp $F6
        jp c, @tact18x
        ld a, (W)                       ; X has passed Y: swap positions
        ld c, a
        ld a, (G)
        ld b, a
        call SwapDriverPosition         ; C = car now at W, B = car now at G
        ld hl, updateDriverInfo
        scf
        rr (hl)
        ld a, (currentPlayer)
        cp b
        ld a, $99                       ; player moves up (BCD -1)
        jr z, @tact3
        ld a, (currentPlayer)
        cp c
        jr nz, @tact4
        ld a, $01                       ; player moves down
@tact3:
        ld (T), a
        ld h, CAR_PAGE / 256             ; only if on the same lap
        ld a, DRIVER_LAPNUMBER % 256
        add a, c
        ld e, a
        ld a, DRIVER_LAPNUMBER % 256
        add a, b
        ld l, a
        ld a, (hl)
        push hl
        ld hl, Hv
        scf
        rl (hl)
        pop hl
        ccf
        ld l, e
        sbc a, (hl)
        jr nz, @tact4
        ld a, (T)
        ld hl, positionChangeBCD
        add a, (hl)
        daa
        ld (hl), a
@tact4:
        ld e, c
        jp @tact18

@tact5:                                 ; Y is A (0..127) segments ahead
        cp 5
        jp nc, @tact18x
        ld a, (iy + carSpeedLo)
        scf
        sbc a, (ix + carSpeedLo)
        ld a, (iy + carSpeedHi)
        sbc a, (ix + carSpeedHi)
        ccf
        ld hl, V
        rr (hl)
        bit 7, (hl)
        jp z, @tact18x                  ; X not faster than Y
        srl a
        cp 30
        jr c, @t6
        ld a, 30
@t6:
        cp 4
        jr nc, @tact7
        ld a, 4
@tact7:
        ld (SS), a                      ; steering amount
        ld a, (T)
        cp 4
        sbc a, a
        ld b, a                         ; B = $FF if closer than 4 segments
        ld a, (ix + carStatus)
        and $40
        jr z, @tact9
        bit 7, b                        ; Y is overtaking too
        jr z, @tact8
        or $80
@tact8:
        ld (N), a
        ld a, (iy + carRacingLine)
        cp (ix + carRacingLine)
        ccf
        ld hl, T
        rr (hl)
        jr @tact15
@tact9:
        bit 7, b
        jr z, @tact10
        ld a, $40
        ld (N), a
        ld a, (ix + carRacingLine)
        cp (iy + carRacingLine)
        ccf
        ld hl, T
        rr (hl)
        or a
        jp p, @t9a
        neg
@t9a:
        cp 60
        jr c, @tact11
        jr @tact12
@tact10:
        ld hl, V
        srl (hl)
@tact11:
        ld a, (ix + carRacingLine)
        ld (T), a
@tact12:
        ld a, iyl
        sub OBJ_BIAS
        ld l, a
        ld h, OBJ_STATUS / 256
        bit 7, (hl)
        jr z, @tact13
        call Random                     ; X not visible: occasional change
        and $1F
        jr nz, @tact18x
        ld a, (V)
        and $80
        ld hl, N
        or (hl)
        ld (hl), a
        jr @tact18x
@tact13:
        ld a, (ix + carRacingLine)
        sub (iy + carRacingLine)
        jr nc, @tact14
        cpl
@tact14:
        cp 100
        jr nc, @tact18x
        cp 80
        jr nc, @tact16
@tcBrake:                               ; (track code: 75)
        cp 60
        jr nc, @tact15
        ld a, (V)
        and $80
        ld hl, N
        or (hl)
        ld (hl), a
@tact15:
        ld a, (T)
        and $80
        ld hl, SS
        or (hl)
        ld (iy + carSteering), a
@tact16:
        ld hl, N
        set 4, (hl)
@tact18x:
        ld a, iyl
        sub OBJ_BIAS
        ld e, a
@tact18:                                ; E = car X
        ld h, CAR_PAGE / 256
        ld a, CAR_STATUS % 256
        add a, e
        ld l, a
        bit 0, (hl)
        jr nz, @tact19
        ld a, (N)
        ld (hl), a
@tact19:
        ld a, (W)                       ; C = the position behind
        inc a
        cp 20
        jr c, @pb
        xor a
@pb:
        ld c, a
        ld a, (currentPosition)
        cp c
        jp nz, @tact1
        ret

; ---------------------------------------------------------------------------
; CompareSegments: distance in segments from object C to object B.
; Carry in = 6502 carry (set for a plain subtraction).
; Returns carry clear and A = T = signed distance (-127..127) if the objects
; are close, carry set otherwise. BBC rightOfEdge (Hv) bit 7 is set if the
; distance did not wrap over the start line.

CompareSegments:
        push af
        ld h, OBJ_PAGE / 256
        ld a, OBJ_SEGLO % 256
        add a, c
        ld l, a
        ld e, (hl)
        add a, 24
        ld l, a
        ld d, (hl)                      ; DE = segment of object C (B = 6502 Y)
        ld a, OBJ_SEGLO % 256
        add a, b
        ld l, a
        ld a, (hl)
        ld (T), a
        ld a, l
        add a, 24
        ld l, a
        ld h, (hl)
        ld a, (T)
        ld l, a                         ; HL = segment of object B
        pop af
        ccf
        sbc hl, de
        ld b, 0                         ; B bit 7 = sign of the distance
        jp p, @d1
        ld b, $80
        xor a
        sub l
        ld l, a
        sbc a, a
        sub h
        ld h, a
@d1:
        ld (T), hl
        ld a, h
        or a
        scf
        jr z, @d2
        ld a, b                         ; |distance| >= 256: try the other
        xor $80                         ; way round the track
        ld b, a
        ex de, hl
        ld hl, (trackLength)
        sbc hl, de                      ; (carry clear after XOR)
        ld a, l                         ; (U keeps the high byte of the
        ld (T), a                       ; distance, as on the C64)
        ld a, h
        or a
        jr nz, @far
@d2:
        ld hl, Hv
        rr (hl)
        ld a, (T)
        cp $80
        jr nc, @far
        bit 7, b
        jr z, @d3
        neg
        ld (T), a
@d3:
        or a
        ret
@far:
        scf
        ret

; SwapDriverPosition: swap the drivers at positions C and B in driversInOrder.
; Returns C = driver now at position C, B = driver now at position B.

SwapDriverPosition:
        ld h, CAR_PAGE / 256
        ld a, DRIVERS_IN_ORDER % 256
        add a, b
        ld d, a
        ld l, a
        ld b, (hl)                      ; driver at position B
        ld a, DRIVERS_IN_ORDER % 256
        add a, c
        ld l, a
        ld a, (hl)                      ; driver at position C
        ld (T), a
        ld (hl), b
        ld c, b
        ld l, d
        ld (hl), a
        ld b, a
        ret
