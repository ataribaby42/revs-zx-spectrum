; Driving model, part 2: tyres, grass, wings, engine, elevation

; ---------------------------------------------------------------------------
; ApplyTyreForces: C = 0 front, 1 rear. Sets tyreSqueal bit 7 when skidding.

ApplyTyreForces:
        ld a, (physHi + PH_XVEL)
        ld (T), a
        ld hl, physTop + PH_XVEL
        or (hl)
        push af                         ; Z: xVelocity = 0
        ld a, (hl)
        call Negate16                   ; (A T) = -xVelocity
        ld b, 4                         ; C64: << 4
@t1:
        ld hl, T
        sla (hl)
        rla
        djnz @t1
        ld ix, physHi + PH_XNOSE
        ld b, 0
        add ix, bc
        ld (ix + 16), a                 ; xTyreForceNoseHi[X]
        pop de                          ; E = flags of the zero test
        bit 6, e
        jr nz, @t2
        ld hl, physTop + PH_XVEL
        xor (hl)
        scf
        jp p, @t7                       ; overflow: skidding
@t2:
        ld a, (T)
        ld (ix + 0), a
        call GetTyreForces
        jr nc, @t3
        xor a                           ; front tyres without drive
        ld (physHi + PH_ZNOSE), a
        ld (physTop + PH_ZNOSE), a
        ld a, (physTop + PH_XNOSE)
        call Abs8
        jr @t6
@t3:
        call ApplyLimitThrottle
        ld a, (ix + 18)                 ; zTyreForceNoseHi[X]
        call Abs8
        ld (T), a
        ld a, (ix + 16)                 ; xTyreForceNoseHi[X]
        call Abs8
        ld hl, T
        cp (hl)
        jr c, @t4
        srl (hl)
        jr @t5
@t4:
        srl a
@t5:
        add a, (hl)
@t6:
        ld hl, wingForce
        ld b, 0
        add hl, bc
        cp (hl)
        ccf                             ; C64 carry: A >= wingForce
        jr nz, @t7
        or a                            ; equal: no skid
@t7:
        push af                         ; keep the carry
        ld hl, tyreSqueal
        ld b, 0
        add hl, bc
        pop af
        rr (hl)
        ret

; Abs8: A = |A| (signed)
Abs8:
        or a
        ret p
        neg
        ret

; GetTyreForces: C = 0 front, 1 rear. Returns (A T) = force from the throttle
; or brakes, carry set when the front tyres have no drive force.
GetTyreForces:
        ld a, c
        add a, 2
        ld (G), a
        ld a, (throttleBrakeState)
        cp 1
        jr z, @g1
        ld b, PH_ZVEL                   ; braking
        call Scale16Bit
        ld a, (physTop + PH_ZVEL)
        xor $80
        ld (Hv), a
        ld hl, wingForce
        ld b, 0
        add hl, bc
        ld a, (hl)
        dec c
        jr z, @g2                       ; rear: full wing force
        inc c
        srl a                           ; front: (wing / 2 + wing) / 2
        add a, (hl)
        srl a
        jr @g2b
@g1:
        ld a, c
        cp 1
        jr nz, @g4
        ld a, (gearNumber)
        dec a
        ld (Hv), a
        ld a, (engineTorque)
        jr @g2b
@g2:
        inc c
@g2b:
        ld (U), a
        ld a, (throttleBrake)
        call Multiply8x8
        ld b, a
        ld a, (throttleBrakeState)
        cp 1
        ld a, b
        jr nz, @g3                      ; throttle: halve
        srl a
        ld hl, T
        rr (hl)
@g3:
        or a                            ; clear carry
        ret
@g4:
        scf
        ret

; Scale16Bit: NN (high) / MM (low) = |physics value B| << 4, saturated
Scale16Bit:
        ld hl, physHi
        ld a, l
        add a, b
        ld l, a
        adc a, h
        sub l
        ld h, a
        ld e, (hl)
        ld a, l
        add a, 16
        ld l, a
        adc a, h
        sub l
        ld h, a
        ld a, (hl)
        or a
        jp p, @s1
        ld d, a
        xor a
        sub e
        ld e, a
        ld a, 0
        sbc a, d
@s1:
        ld b, 4                         ; C64: 4
@s2:
        sla e
        rl a                            ; (RL sets S, RLA does not)
        jp m, @s4
        djnz @s2
@s3:
        ld (NN), a
        ld a, e
        ld (MM), a
        ret
@s4:
        ld a, e
        ld (MM), a
        ld a, %01111111
        ld (NN), a
        ret

; ApplyLimitThrottle / ApplyLimitAndSign: (A T) limited to (NN MM) unless
; throttle, signed by H, stored in tyre force G
ApplyLimitThrottle:
        ld b, a
        ld a, (throttleBrakeState)
        cp 1
        ld a, b
        jr z, ApplyLims1
ApplyLimitAndSign:
        ld hl, NN
        cp (hl)
        jr c, ApplyLims1
        ld a, (MM)
        ld (T), a
        ld a, (NN)
ApplyLims1:
        ld b, a
        ld a, (Hv)
        or a
        ld a, b
        call m, Negate16
        ld b, a
        ld a, (G)
        ld hl, physHi + PH_XNOSE
        add a, l
        ld l, a
        adc a, h
        sub l
        ld h, a
        ld a, (T)
        ld (hl), a
        ld de, 16
        add hl, de
        ld (hl), b
        ret

; ApplySkidForces: C = 0 front, 1 rear
ApplySkidForces:
        ld ix, physHi + PH_ZNOSE
        ld b, 0
        add ix, bc
        xor a
        ld (ix + 0), a
        ld (ix + 16), a
        ld b, PH_XVEL
        call Scale16Bit
        ld a, (physTop + PH_XVEL)
        xor $80
        ld (Hv), a
        xor a
        ld (T), a
        ld a, c
        ld (G), a
        call @wing95
        call ApplyLimitAndSign
        call GetTyreForces
        ret c
        ld b, a
        call @wing95
        ld e, a
        ld a, b
        cp e
        jp c, ApplyLimitThrottle
        xor a
        ld (T), a
        ld a, e
        call ApplyLimitThrottle
        ld a, (throttleBrakeState)
        cp 1
        ret nz
        ld a, c
        or a
        ret z
        xor a
        ld (physHi + PH_XREAR), a
        ld (physTop + PH_XREAR), a
        ret
@wing95:
        ld hl, wingForce95
        ld e, c
        ld d, 0
        add hl, de
        ld a, (hl)
        ret

; ---------------------------------------------------------------------------
; ApplyGrassOrTrack (C64: speed cap 76)

wingForceTrack: db 55, 55                       ; C64 values (BBC 53, 53)
wingForceGrass: db 26, 27                       ; C64 values (BBC 25, 26)

ApplyGrassOrTrack:
        xor a
        ld b, a
        ld a, (throttleBrakeState)
        or a
        jr nz, @g1
        ld a, (zTyreForceBoth)
        sra a
        sra a
        sra a
        ld b, a
@g1:
        ld a, b
        ld (Hv), a
        neg
        ld (G), a
        ld a, (playerSpeedHi)
        ld (U), a
        ld c, 0                         ; X
        ld a, (leftSurface)
        ld hl, rightSurface
        and (hl)
        ld (W), a
        ld a, (leftSurface)
        cp $FF
        jr z, @g2
        ld a, (rightSurface)
        cp $FF
        jr nz, @g4
@g2:
        call Random                     ; C64 reads the CIA timer
        call Multiply8x8
        and 7
        ld c, a
        jr nz, @g3
        inc c
@g3:
        ld a, (bumpyGrassHeight)
        or a
        jr nz, @g4
        ld hl, heightAboveTrack
        or (hl)
        jr nz, @g4
        ld a, (playerDrift)
        or a
        jp p, @g4
        push bc
        call ApplyVergeJump
        pop bc
@g4:
        ld a, c
        ld (bumpyGrassHeight), a
        ld c, 1
@g5:
        ld a, (playerSpeedHi)
        cp 76
        jr c, @g6
        ld a, 76
@g6:
        ld (U), a
        ld hl, wingSetting
        ld b, 0
        add hl, bc
        ld a, (hl)
        call Multiply8x8
        ld b, a
        ld a, (physTop + PH_ZVEL)
        or a
        ld a, b
        call m, NegA
        ld hl, wingForceTrack
        ld b, 0
        add hl, bc
        add a, (hl)
        ld b, a
        ld a, 243
        ld (U), a
        ld a, (W)
        cp $FF
        ld a, b
        jr nz, @g7
        ld hl, wingForceGrass
        ld b, 0
        add hl, bc
        ld a, (hl)
@g7:
        ld hl, G
        ld b, 0
        add hl, bc
        add a, (hl)
        ld hl, wingForce
        add hl, bc
        ld (hl), a
        call Multiply8x8
        ld hl, wingForce95
        add hl, bc
        ld (hl), a
        dec c
        jp p, @g5
        ret

NegA:
        neg
        ret

; ApplyWingBalance (C64 version)
ApplyWingBalance:
        ld a, (xPrevVelocityHi)
        call Abs8
        ld (U), a
        ld hl, playerSpeedHi
        cp (hl)
        jr nc, @b1
        ld a, (hl)
@b1:
        ld b, a
        ld a, (bumpyGrassHeight)
        or a
        ld a, b
        jr nz, @b2
        srl a                           ; C64: halve unless on bumpy grass
@b2:
        ld (W), a
        call Multiply8x8
        ld (U), a
        ld a, (xPrevVelocityHi)
        ld b, PH_XPACCEL
        call SubtractCoords
        ld a, (playerSpeedHi)
        ld (U), a
        ld a, (wingBalance)
        call Multiply8x8
        add a, 12                       ; C64: 12
        ld (V), a
        ld a, (W)
        ld (U), a
        call Multiply8x16
        ld a, (physTop + PH_ZVEL)
        ld b, PH_ZPACCEL
        jp SubtractCoords

; ApplyVergeJump / ApplyBounce
ApplyVergeJump:
        ld a, (playerSpeedHi)
ApplyBounce:
        srl a
        ld (yGravityDelta), a
        srl a
        ld (yJumpHeight), a
        ld hl, heightAboveTrack
        inc (hl)
        ld hl, physHi + PH_SPINYAW
        scf
        rr (hl)
        ret

; ---------------------------------------------------------------------------
; Engine

ProcessEngineStart:
        ld a, KEY_T
        call KeyDown
        jr nz, @e2
        ld a, (gearNumber)
        cp 1
        jr z, @e1
        ld a, (playerSpeedHi)
        or a
        jr nz, @e3                      ; bump start in gear
@e1:
        xor a
        jr SetRevsNoTorque
@e2:
        ld a, 7                         ; the starter sound for this step
        ld (starterFrames), a
        call Random
        ld hl, oddsOfEngineStart
        and (hl)
        jr nz, ThrobRevsNoTorque
@e3:
        ld b, a
        ld a, 7
        ld (oddsOfEngineStart), a
        ld a, $FF
        ld (engineStatus), a
        ld a, b
        jr ThrobRevsNoTorque

CalcRevsNoTorqueClutch:
        ld (clutchEngaged), a
CalcRevsNoTorque:
        ld a, (throttleBrakeState)
        cp 1
        ld a, (revCount)
        jr nz, @u1
        add a, 10                       ; C64: 10 (BBC 7)
        ld hl, throttleBrake
        cp (hl)
        jr nc, @u1
        cp 140
        jr c, SetRevsNoTorque
@u1:
        cp 42
        jr c, @u2
        sub 15                          ; C64: 15 (BBC 12)
        jr ThrobRevsNoTorque
@u2:
        ld a, 40
ThrobRevsNoTorque:
        ld b, a
        call Random
        and 7
        add a, b
SetRevsNoTorque:
        ld (revCount), a
        ld (revsOnGearChange), a
ZeroEngineTorque:
        xor a
        jp SetEngineTorque

ApplyEngine:
        ld a, (engineStatus)
        or a
        jr z, ProcessEngineStart
        ld a, (heightAboveTrack)
        or a
        jr nz, CalcRevsNoTorque
        ld a, (gearChangeKey)
        or a
        jp m, CalcRevsNoTorqueClutch
        ld a, (gearNumber)
        cp 1
        jr z, CalcRevsNoTorque
        ld a, (playerSpeedLo)           ; revs from the road speed
        ld e, a
        ld a, (playerSpeedHi)
        sla e
        rl a
        push af                         ; S: speed * 2 >= 128
        jp m, @e1
        sla e
        rla
@e1:
        ld (U), a
        ld a, e
        ld (T), a
        ld a, (gearNumber)
        ld c, a
        ld hl, trackGearRatio
        add a, l
        ld l, a
        ld a, (hl)
        call Multiply8x8
        ld hl, T
        sla (hl)
        rla
        pop de
        bit 7, e
        jr z, @e2
        sla (hl)
        rla
@e2:
        ld b, a
        ld a, (clutchEngaged)
        or a
        ld a, b
        jp p, @e6
        ld a, (throttleBrakeState)
        cp 1
        jr nz, @e4
        ld a, (playerSpeedHi)
        cp 22
        jr nc, @e4
        ld a, (raceStarting)
        or a
        jp p, @e3
        cp 160
        jr nz, @e4
        ld a, (mainLoopCounterLo)       ; C64: modulo 32 window
        and 31
        cp 24
        jr c, @e4
@e3:
        ld a, (revsOnGearChange)
        ld e, a
        ld a, b
        cp e
        jr c, @e5
@e4:
        xor a
        ld (clutchEngaged), a
        ld a, b
        jr @e6
@e5:
        ld a, e
        cp 108
        jr c, @e6
        sub 2
        ld (revsOnGearChange), a
@e6:
        ld (revCount), a
        cp 170
        jr c, @e7
        ld a, 170
@e7:
        cp 3
        jr nc, @e8
        ld hl, engineStatus
        inc (hl)
        jp ZeroEngineTorque
@e8:
        sub 66
        jp m, @e9
        cp 17
        jr nc, @e10
@e9:
        add a, a
        add a, 152
        jr @e13
@e10:
        sub 17
        cp 4
        jr nc, @e11
        cpl
        add a, 187
        jr @e13
@e11:
        sub 4
        cp 5
        jr nc, @e12
        add a, a
        add a, a
        cpl
        add a, 183
        jr @e13
@e12:
        sub 5
        add a, a
        cpl
        add a, 163
@e13:
        ld (U), a
        ld hl, trackGearPower
        ld a, l
        add a, c
        ld l, a
        ld a, (hl)
        call Multiply8x8
SetEngineTorque:
        ld (engineTorque), a
        ld a, (revCount)
        add a, 25
        ld (soundRevTarget), a
        ret

; ---------------------------------------------------------------------------
; ApplyElevation (C64: gravity 6, bounce threshold 7)

ApplyElevation:
        ld a, (heightAboveTrack)
        or a
        jr z, @el1
        ld hl, yJumpHeight
        dec (hl)
        dec (hl)
        jp @el7
@el1:
        ld (yJumpHeight), a
        ld (yGravityDelta), a
        ld a, (liftFromTorque)
        ld b, a                         ; Y
        ld a, (gearNumber)
        or a
        jr z, @el3
        ld a, (throttleBrakeState)
        or a
        jp m, @el3
        jr z, @el2
        ld a, (engineTorque)
        or a
        jr nz, @el4
        jr @el3
@el2:
        ld a, (playerSpeedHi)
        or a
        jr nz, @el5
@el3:
        ld a, b
        or a
        jr z, @el7
        jp p, @el5
        inc b
@el4:
        inc b
        jp m, @el6
        ld a, b
        cp 4
        jr c, @el6
        ld b, 3
        jr @el6
@el5:
        dec b
        jp p, @el6
        ld a, b
        cp $FB
        jr nc, @el6
        ld b, $FB
@el6:
        ld a, b
        ld (liftFromTorque), a
@el7:
        ; heading of the track relative to the player
        ld a, (playerSegmentIndex)
        ld l, a
        ld h, SEGDATA / 256
        ld b, (hl)                      ; Y = segmentVector
        ld a, (playerPitchAngle)
        ld (V), a
        ld l, b
        ld h, xTrackSegmentI / 256
        ld d, (hl)                      ; x vector
        ld h, zTrackSegmentI / 256
        ld e, (hl)                      ; z vector
        ld a, e
        call Abs8
        ld c, a                         ; |z|
        cp 60
        jr c, @el8                      ; |z| < 60: use |z|
        ld a, d
        call Abs8                       ; otherwise |x|
@el8:
        ld (T), a
        srl a
        ld hl, T
        add a, (hl)
        srl a
        srl a
        ld l, a
        ld a, c
        cp 60
        ld a, l
        jr nc, @el9
        xor %00111111
@el9:
        bit 7, e
        jr z, @el10
        xor %10000000
@el10:
        ld l, a
        ld a, d
        xor e
        ld a, l
        call m, NegA
        ld hl, playerYawAngleHi
        sub (hl)
        ld (playerHeading), a
        call Abs8x
        cp 64
        jr c, @el12
        xor %01111111
@el12:
        ld (playerSideways), a
        ; elevation above the track
        xor %00111111
        ld (T), a
        srl a
        ld hl, T
        add a, (hl)
        call MultiplyHeight
        ld hl, bumpyGrassHeight
        add a, (hl)
        ld hl, liftFromTorque
        add a, (hl)
        ld hl, yJumpHeight
        add a, (hl)
        ld hl, playerPitchAngle
        add a, (hl)
        sra a
        ld (playerPitchAngle), a
        ld hl, V
        sub (hl)
        ld (spinPitchAngle), a
        ; height of the car above the track
        xor a
        ld (W), a
        ld a, (yGravityDelta)
        sub 6                           ; C64: 6
        jp po, @el14
        ld a, $C8
@el14:
        ld (yGravityDelta), a
        ld hl, heightAboveTrack
        add a, (hl)
        jr z, @el15
        jp pe, @el17
        jp p, @el18
@el15:
        ld a, (yGravityDelta)
        call Abs8
        cp 7                            ; C64: 7
        jr c, @el16
        call ApplyBounce
        ld a, 1
        jr @el18
@el16:
        xor a
        jr @el18
@el17:
        ld a, 127
@el18:
        ld (heightAboveTrack), a
        ; y coordinate of the player
@tcSlope:                               ; (track code: call HookSlopeJump)
        ld hl, W
        add a, a
        rl (hl)
        add a, a
        rl (hl)
        ld (V), a
        ld a, (currentPlayer)
        add a, CAR_PROGRESS % 256
        ld l, a
        ld h, CAR_PROGRESS / 256
        ld a, (hl)
        call MultiplyHeight
        or a
        jp p, @el19
        ld hl, W
        dec (hl)
@el19:
        ld e, a
        ld a, (playerSegmentIndex)
        inc a                           ; y axis
        ld l, a
        ld h, SEG_LO / 256
        ld a, e
        add a, (hl)                     ; + ySegmentCoordILo
        push af                         ; C1
        add a, 172
        push af                         ; C2
        ld e, a
        ld a, (V)
        add a, e
        ld (playerCoordY + 1), a
        inc h
        ld a, (W)
        adc a, (hl)                     ; + ySegmentCoordIHi + C3
        ld e, a
        pop af
        ld a, e
        adc a, 0                        ; + C2
        ld e, a
        pop af
        ld a, e
        adc a, 0                        ; + C1
        ld (playerCoordY + 2), a
        ; car speed for the AI code
        ld a, (playerSpeedHi)
        ld (U), a
        ld a, 33
        call Multiply8x8
        ld b, a
        ld a, (playerSpeedHi)
        add a, a
        add a, b
        ld b, a
        ld a, (currentPlayer)
        add a, CAR_SPEEDHI % 256
        ld l, a
        ld h, CAR_SPEEDHI / 256
        ld (hl), b
        ret

; Abs8x: |A| as the BBC "BPL / EOR #&FF" (one's complement)
Abs8x:
        or a
        ret p
        cpl
        ret

; MultiplyHeight: A = signed high byte of |yTrackSegmentI[B]| * A, with the
; sign of yTrackSegmentI[B] EOR directionFacing. Flags set from A.
MultiplyHeight:
        ld (U), a
        ld l, b
        ld h, yTrackSegmentI / 256
        ld a, (hl)
        ld e, a
        ld hl, directionFacing
        xor (hl)
        ld d, a                         ; sign
        ld a, e
        call Abs8
        call Multiply8x8
        bit 7, d
        jr z, @m1
        neg
@m1:
        or a
        ret
