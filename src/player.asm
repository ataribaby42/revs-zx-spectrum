; Player controls and movement along the track (C64 versions)

; ---------------------------------------------------------------------------
; ProcessDrivingKeys (C64 Revs+ keyboard path: steering rate 4 (fast) or
; 2/0.625; centring as patched by the Revs+ installer)

ProcessDrivingKeys:
        xor a
        ld (V), a
        ld (T), a
        ld (gearChangeKey), a
        ld a, KEY_LEFT
        call KeyDown
        jr z, @k3
        ld a, 2
        ld (V), a
@k3:
        ld a, KEY_RIGHT
        call KeyDown
        jr z, @cas
        ld hl, V
        inc (hl)
@cas:                                   ; C64 Revs+ CAS ($9C9D): forwards with
        ld a, (casOn)                   ; a steering key held
        or a
        jr z, @k4
        ld a, (directionFacing)
        or a
        jp m, @k4                       ; backwards: manual steering
        ld a, (V)
        or a
        jp z, @k7                       ; no key: centring
        cp 3
        jp z, @k13                      ; both keys: no change
        call AssistSteering
        jp @k9
@k4:
        ld a, 4
        ld (U), a
        xor a
        ld (T), a
        ld a, KEY_FASTSTEER
        call KeyDown
        jr nz, @k6
        ld a, (steeringHi)
        cp 3
        jr c, @k5                       ; steeringHi <= 2
        xor a
        ld (U), a
        ld a, $A0
        ld (T), a
        jr @k6
@k5:
        ld a, 2
        ld (U), a
        xor a
        ld (T), a
@k6:
        ld a, (V)
        or a
        jr z, @k7
        cp 3
        jp z, @k13
        ld hl, steeringLo
        xor (hl)
        and 1
        jr z, @k9
        call Negate16U                  ; (A T) = -(U T)
        jr @k8
@k7:                                    ; no key: centre the steering by
        ld a, (physHi + PH_XNOSE)       ; |xTyreForceNose| / 2, at most back
        and $F0                         ; to straight ahead (Revs+ $9D8D)
        ld (T), a
        ld a, (physTop + PH_XNOSE)
        call Abs16
        ld hl, T
        srl a
        rr (hl)
        ld hl, steeringHi
        cp (hl)
        jr c, @k8
        ld a, (steeringLo)
        and $FE
        ld (T), a
        ld a, (hl)
@k8:
        ld (U), a
@k9:
        ld a, (steeringLo)
        ld hl, T
        sub (hl)
        ld (hl), a
        ld a, (steeringHi)
        ld hl, U
        sbc a, (hl)
        cp 200
        jr c, @k11
        call Negate16                   ; past zero: flip the steering sign
        ld (U), a
        ld a, (T)
        xor 1
        ld (T), a
        ld a, (U)
@k11:
        cp 145
        jr c, @k12
        ld a, 145
@k12:
        ld (steeringHi), a
        ld a, (T)
        ld (steeringLo), a
@k13:
        ; throttle and brake
        ld a, (leaveTrackTimer)
        or a
        jr nz, @k19
        ld a, KEY_THROTTLE
        call KeyDown
        jr z, @k17
        ld c, 1
        ld a, $FF
        jr @k20
@k17:
        ld a, KEY_BRAKE
        call KeyDown
        jr z, @k19
        ld c, 0
        ld a, $FA
        jr @k20
@k19:
        ld c, $80
        ld a, (revCount)
        srl a
        srl a
        add a, 5
@k20:
        ld (throttleBrake), a
        ld a, c
        ld (throttleBrakeState), a
        ; gears
        ld a, KEY_GEARDOWN
        call KeyDown
        jr nz, @k23
        ld a, KEY_GEARUP
        call KeyDown
        jr nz, @k24
        xor a
        ld (gearChange), a
        ret
@k23:
        ld b, $FF
        jr @k25
@k24:
        ld b, 1
@k25:
        ld hl, gearChangeKey
        dec (hl)
        ld a, (gearChange)
        or a
        ret nz
        ld a, b
        ld (gearChange), a
        ld hl, gearNumber
        add a, (hl)
        cp $FF
        jr z, @k26
        cp 7
        jr nz, @k27
        ld a, 6
        jr @k27
@k26:
        xor a
@k27:
        cp (hl)                         ; HL = gearNumber
        ld (hl), a
        jp z, PrintGearNumber
        ld a, (noiseFrames)             ; a new gear: a brief rasp (one frame
        or a                            ; of noise, as long as the user's ZX
        jp nz, PrintGearNumber          ; version's two short packets), unless
        ld a, 1                         ; a contact noise is playing
        ld (noiseFrames), a
        jp PrintGearNumber

; ---------------------------------------------------------------------------
; MovePlayerOnTrack (C64): progress and racing line of the player's car

MovePlayerOnTrack:
        ld a, (playerHeading)
        ld b, a
        ld a, (edgeYawAngle)
        sub b
        ld hl, directionFacing
        xor (hl)
        call Abs8
        cp $40
        ccf                             ; 6502 carry: A >= 64
        ld hl, playerPastSegment
        rr (hl)
        jp p, @m1
        xor $7F
        inc a
@m1:
        ld (@save1 + 1), a
        ld b, $BA
        call GetCarInSegment
        ld b, a
        ld c, 0                         ; 6502 carry for the SBC below
        ld a, (edgeSegmentPointer)
        cp 40
        ld a, b
        jr c, @m2
        cpl
        ld c, 1
@m2:
        ld b, a
        ld a, (directionFacing)
        or a
        ld a, b
        jp p, @m3
        ld c, 0
        or a
        jr nz, @m2n
        ld c, 1
@m2n:
        neg
@m3:
        ld (@save2 + 1), a              ; new racing line
        ld b, a
        ld a, (currentPlayer)
        add a, CAR_RACINGLINE % 256
        ld l, a
        ld h, CAR_RACINGLINE / 256
        ld a, c
        xor 1
        rra                             ; Z80 borrow = not 6502 carry
        ld a, b
        sbc a, (hl)
        jr nc, @d1
        cpl
@d1:
        cp $1F                          ; C64: 31
        ccf
        jr nc, @d2
        push de                         ; Revs+ drift guard ($9DA7): only
        ld a, (currentPlayer)           ; from section segment 3 on
        add a, OBJ_SEGMT % 256
        ld e, a
        ld d, OBJ_SEGMT / 256
        ld a, (de)
        pop de
        cp 3
        ccf
@d2:
        ld a, (playerDrift)
        rra
        ld (playerDrift), a
@save2:
        ld (hl), 0                      ; carRacingLine[player] (patched)
@save1:
        ld a, 0                         ; patched
        cpl
        add a, $41
        ld b, $88
        call GetCarInSegment
        add a, a
        add a, a
        ld b, a
        ld a, (playerPastSegment)
        or a
        ld a, b
        jp m, @m4
        cpl
@m4:
        ld b, a
        ld a, (currentPlayer)
        add a, CAR_PROGRESS % 256
        ld l, a
        ld h, CAR_PROGRESS / 256
        ld (hl), b
        ret

; GetCarInSegment: A = edgeDistanceLo * (ScaleCarInSegment(A) * B / 256) / 256
GetCarInSegment:
        call ScaleCarInSegment
        ld (U), a
        ld a, b
        call Multiply8x8
        ld (U), a
        ld a, (edgeDistanceLo)
        jp Multiply8x8

ScaleCarInSegment:
        cp 26
        jr c, @s2
        cp 46
        jr c, @s1
        add a, 190
        ret
@s1:
        add a, a
        add a, a
        add a, 52
        ret
@s2:
        ld (T), a
        add a, a
        ld hl, T
        add a, (hl)
        add a, a
        ret

; ---------------------------------------------------------------------------
; MovePlayerSegment (C64: thresholds 7..9)

MovePlayerSegment:
        ld a, (spinYawAngleTop)
        ld b, a
        ld a, (playerHeading)
        sub b
        jp p, @p1
        cpl
@p1:
        add a, a
        ld c, 0
        cp $80
        jr c, @p1b
        inc c                           ; 6502 carry: A >= 128
@p1b:
        ld b, a
        ld a, (directionFacing)
        xor b
        jp p, @p3
        bit 0, c
        jr z, @p2
        xor $7F
@p2:
        cp $FC
        jr nc, @p3
        jp ChangeDirection
@p3:
        ld a, (edgeSegmentNumber)
        cp 9
        jr nc, @back
        cp 7
        jr z, @f1
        jr nc, @f2
        call MovePlayerForward
@f1:
        call MovePlayerForward
@f2:
        ld a, (playerPastSegment)
        or a
        ret p
        jp MovePlayerForward
@back:
        jr z, @b1
        call MovePlayerBack
@b1:
        ld a, (playerPastSegment)
        or a
        ret m
        jp MovePlayerBack
