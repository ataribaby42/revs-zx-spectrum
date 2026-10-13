; Driving model (port of the C64 versions of ApplyDrivingModel and its
; subroutines; the C64 differs from the BBC in its constants for the 0.13 s
; step). Physics block access: IX = physHi + index, (IX+0) = low byte,
; (IX+16) = high byte, (IX-3) = 24-bit low byte for indices 0..2.

PH_XSPEED       EQU 0
PH_ZSPEED       EQU 1
PH_SPINYAW      EQU 2
PH_XACCEL       EQU 3                   ; xAcceleration
PH_ZACCEL       EQU 4
PH_SPINDELTA    EQU 5
PH_XPACCEL      EQU 6                   ; xPlayerAccel
PH_ZPACCEL      EQU 7
PH_XVEL         EQU 8
PH_ZVEL         EQU 9
PH_XNOSE        EQU 10                  ; xTyreForceNose
PH_XREAR        EQU 11
PH_ZNOSE        EQU 12
PH_ZREAR        EQU 13
PH_XSTEER       EQU 14                  ; xSteeringForce

; ---------------------------------------------------------------------------
; ScaleWingSettings (C64: scale 148, offset 65)

wingScaleFactor: db 148, 148

ScaleWingSettings:
        ld c, 1
@w1:
        ld hl, frontWingSetting
        ld a, l
        add a, c
        ld l, a
        ld a, (hl)
        add a, a
        add a, a
        ld (U), a
        ld hl, wingScaleFactor
        ld a, l
        add a, c
        ld l, a
        ld a, (hl)
        call Multiply8x8
        add a, 65
        ld hl, wingSetting
        ld b, 0
        add hl, bc
        ld (hl), a
        dec c
        jp p, @w1
        ld a, (rearWingSetting)
        ld b, a
        add a, a
        add a, b
        ld hl, frontWingSetting
        add a, (hl)
        srl a                           ; carry = rounding bit
        adc a, 60
        ld (wingBalance), a
        ret

; ---------------------------------------------------------------------------
; ApplyDrivingModel

ApplyDrivingModel:
        ld a, (playerYawAngleLo)
        ld (T), a
        ld a, (playerYawAngleHi)
        call GetRotationMatrix
        call RotateCoordToCar
        ld hl, (physHi + PH_XVEL)       ; xPrevVelocity = xVelocity
        ld a, l
        ld (xPrevVelocityLo), a
        ld a, (physTop + PH_XVEL)
        ld (xPrevVelocityHi), a
        ld a, (physHi + PH_ZVEL)        ; playerSpeed = |zVelocity|
        ld (T), a
        ld a, (physTop + PH_ZVEL)
        call Abs16
        ld (playerSpeedHi), a
        ld b, a
        ld a, (T)
        ld (playerSpeedLo), a
        inc b
        dec b
        jr nz, @d1
        and %11110000
        ld b, a
@d1:
        ld a, b
        ld (playerMoving), a
        call ApplySpinYaw
        call ApplyGrassOrTrack
        call ApplyEngine
        ld c, 1
        call ApplyTyresAndSkids
        ld a, (xPrevVelocityLo)         ; xVelocity = xPrevVelocity + xSpinVelocity
        ld hl, xSpinVelocityLo
        add a, (hl)
        ld (physHi + PH_XVEL), a
        ld a, (xPrevVelocityHi)
        ld hl, xSpinVelocityHi
        adc a, (hl)
        ld (physTop + PH_XVEL), a
        call ApplySteeringSpeed
        ld c, 0
        call ApplyTyresAndSkids
        call ApplySteeringForce
        call ScaleTyreForces
        ld a, (heightAboveTrack)
        cp 2
        jr c, @d3
        xor a                           ; airborne: no spin or acceleration
        ld (physHi + PH_SPINDELTA), a
        ld (physTop + PH_SPINDELTA), a
        ld (physHi + PH_XPACCEL), a
        ld (physTop + PH_XPACCEL), a
        ld (physHi + PH_ZPACCEL), a
        ld (physTop + PH_ZPACCEL), a
@d3:
        call ApplyWingBalance
        call RotateCarToCoord
        call UpdateVelocity
        call ApplyDeltas
        jp ApplyElevation

; ApplySpinYaw
ApplySpinYaw:
        ld a, (physHi + PH_SPINYAW)
        ld (T), a
        ld b, 88
        ld a, (physTop + PH_SPINYAW)
        call Multiply8x16Signed
        ld (U), a
        ld a, (T)                       ; xVelocity -= (U T)
        ld b, a
        ld a, (physHi + PH_XVEL)
        sub b
        ld (physHi + PH_XVEL), a
        ld a, (U)
        ld b, a
        ld a, (physTop + PH_XVEL)
        sbc a, b
        ld (physTop + PH_XVEL), a
        call MultiplyBy1Point5
        ld (xSpinVelocityHi), a
        ld a, (T)
        ld (xSpinVelocityLo), a
        ret

; ApplyTyresAndSkids: C = 0 front, 1 rear
ApplyTyresAndSkids:
        ld a, (heightAboveTrack)
        cp 2
        ret nc
        call ApplyTyreForces
        ld hl, tyreSqueal
        ld b, 0
        add hl, bc
        ld a, (hl)
        and %11000000
        ret z
        jp ApplySkidForces

; ApplySteeringSpeed / ApplySteeringForce
ApplySteeringSpeed:
        ld a, %10000000
        ld (Hv), a
        ld c, 2
        ld b, PH_ZVEL
        ld a, PH_XSTEER
        call MultiplyCoordsK            ; xSteeringForce = -zVelocity * steering
        ld a, %01000000
        ld (Hv), a
        ld c, 2
        ld b, PH_XVEL
        ld a, PH_ZVEL
        call MultiplyCoordsK            ; zVelocity += xVelocity * steering
        ld c, PH_XVEL
        jp AddSteeringForce

ApplySteeringForce:
        xor a
        ld (Hv), a
        ld c, 2
        ld b, PH_ZNOSE
        ld a, PH_XSTEER
        call MultiplyCoordsK            ; xSteeringForce = zTyreForceNose * steering
        ld a, %11000000
        ld (Hv), a
        ld c, 2
        ld b, PH_XNOSE
        ld a, PH_ZNOSE
        call MultiplyCoordsK            ; zTyreForceNose -= xTyreForceNose * steering
        ld c, PH_XNOSE
        ; fall through

; AddSteeringForce: physics value C += xSteeringForce
AddSteeringForce:
        ld b, c
        ld a, (physHi + PH_XSTEER)
        ld (T), a
        ld a, (physTop + PH_XSTEER)
        ld (U), a
        jp AddCoords

; ScaleTyreForces
ScaleTyreForces:
        ld a, (physHi + PH_XNOSE)
        ld hl, physHi + PH_XREAR
        sub (hl)
        ld (T), a
        ld a, (physTop + PH_XNOSE)
        ld hl, physTop + PH_XREAR
        sbc a, (hl)
        ld b, 78
        call Multiply8x16Signed
        ld (physTop + PH_SPINDELTA), a
        ld a, (T)
        ld (physHi + PH_SPINDELTA), a
        ld b, 2                         ; tyre forces >> 2 (arithmetic)
@f1:
        ld hl, physTop + PH_XNOSE
        ld de, physHi + PH_XNOSE
        ld c, 4
@f2:
        sra (hl)
        ex de, hl
        rr (hl)
        ex de, hl
        inc hl
        inc de
        dec c
        jr nz, @f2
        djnz @f1
        ld ix, physHi + PH_XNOSE + 2    ; z axis first, then x axis
        ld iy, physHi + PH_ZPACCEL
@f4:
        ld a, (ix + 1)                  ; rear tyre force
        ld (T), a
        ld a, (ix + 17)
        ld (U), a
        call MultiplyBy1Point5          ; (A T) = 1.5 * rear
        ld (U), a
        ld a, (T)
        add a, (ix + 0)                 ; + nose tyre force
        ld (T), a
        ld a, (U)
        adc a, (ix + 16)
        ld b, 205
        call Multiply8x16Signed
        ld hl, T
        sla (hl)
        rla
        ld (iy + 16), a
        ld a, (T)
        ld (iy + 0), a
        dec iy
        dec ix
        dec ix
        ld a, iyl
        cp 0 + (physHi + PH_XPACCEL - 1) % 256
        jr nz, @f4
        ld a, (physTop + PH_ZPACCEL)
        ld (zTyreForceBoth), a
        ret

; ---------------------------------------------------------------------------
; MultiplyCoords: physics value K (= A for MultiplyCoordsK) = or += value B
; times rotation entry C (0 sin, 1 cos, 2 steering), Hv: bit 7 negate,
; bit 6 add instead of store.
;
; The product is the BBC Multiply16x16 of (QQ PP) = value B (signed) and
; (SS RR) = the rotation entry (RR bit 0 = its sign): with q.p = |value B|,
; three partial products, PP * RR left out and rounded as on the BBC, give
; exactly  q * SS + (q * RR + p * SS + 128) / 256.

MultiplyCoordsN:                        ; Y = N, H = A
        ld (Hv), a
        ld a, (N)
        ld b, a
        jr MultiplyCoordsC
MultiplyCoordsK:
        ld (K), a
MultiplyCoordsC:
        ld a, b
        add a, physHi % 256
        ld l, a
        ld h, physHi / 256
        ld e, (hl)                      ; E = PP
        add a, 16
        ld l, a
        ld d, (hl)                      ; D = QQ
        ld a, c
        add a, sinYawAngleLo % 256
        ld l, a
        ld h, sinYawAngleLo / 256
        ld c, (hl)                      ; C = RR
        inc l
        inc l
        inc l
        ld b, (hl)                      ; B = SS
        ld a, (Hv)
        bit 7, d
        jr z, @m1
        xor $80                         ; negative value: negate it and the
        ld h, a                         ; result sign
        xor a
        sub e
        ld e, a
        ld a, 0
        sbc a, d
        ld d, a
        ld a, h
@m1:
        bit 0, c
        jr z, @m2
        xor $80
@m2:
        ld (@sign + 1), a               ; result sign (bit 7), add (bit 6)
        ld a, b
        ld (@s1 + 1), a
        ld (@s2 + 1), a
        ld a, d
        ld (@q2 + 1), a
        ld a, c                         ; q * RR + 128
        ex af, af'
        ld a, d
        push de
        call QMul
        ld bc, 128
        add hl, bc
        pop de
        push hl
@s1:
        ld a, 0                         ; + p * SS, then / 256 (17 bits)
        ex af, af'
        ld a, e
        call QMul
        pop bc
        add hl, bc
        ld a, 0
        adc a, a
        ld l, h
        ld h, a
        push hl
@s2:
        ld a, 0                         ; + q * SS
        ex af, af'
@q2:
        ld a, 0
        call QMul
        pop bc
        add hl, bc
@sign:
        ld a, 0                         ; patched: sign and mode
        rla
        jr nc, @m3
        xor a                           ; negative result
        sub l
        ld l, a
        sbc a, a
        sub h
        ld h, a
@m3:
        ex de, hl                       ; DE = result
        ld a, (K)
        add a, physHi % 256
        ld l, a
        ld h, physHi / 256
        ld a, (@sign + 1)
        bit 6, a
        jr nz, @m4
        ld (hl), e                      ; store
        ld a, l
        add a, 16
        ld l, a
        ld (hl), d
        ret
@m4:
        ld a, l                         ; add: BC = high byte (before the
        add a, 16                       ; carry is needed)
        ld c, a
        ld b, h
        ld a, (hl)
        add a, e
        ld (hl), a
        ld a, (bc)
        adc a, d
        ld (bc), a
        ret

        ASSERT physHi / 256 == (physHi + 31) / 256
        ASSERT sinYawAngleLo / 256 == (sinYawAngleLo + 5) / 256

; QMul: HL = A * A' (unsigned, quarter squares as Multiply8x8T).
; Corrupts BC, DE.
QMul:
        ld e, a
        ex af, af'
        ld d, a
        add a, e
        ld l, a
        ld a, QSQ_LO / 256
        adc a, 0
        ld h, a
        ld c, (hl)
        inc h
        inc h
        ld b, (hl)                      ; BC = Q[a + b]
        ld a, e
        sub d
        jr nc, @p
        neg
@p:
        ld l, a
        ld h, QSQ_LO / 256
        ld a, c
        sub (hl)
        ld c, a
        inc h
        inc h
        ld a, b
        sbc a, (hl)
        ld h, a
        ld l, c
        ret

; SubtractCoords: physics value B -= (U T) * sign, where A's sign selects:
; negative A: add, otherwise subtract
SubtractCoords:
        or a
        jp m, AddCoords
        call Negate16U
        ld (U), a
        ; fall through

; AddCoords: physics value B += (U T)
AddCoords:
        ld hl, physHi
        ld a, l
        add a, b
        ld l, a
        adc a, h
        sub l
        ld h, a
        ld de, 16
        ex de, hl
        add hl, de
        ex de, hl                       ; HL = low byte, DE = high byte
        ld a, (T)
        add a, (hl)
        ld (hl), a
        ld a, (U)
        ex de, hl
        adc a, (hl)
        ld (hl), a
        ret

; RotateCoordToCar / RotateCarToCoord / RotateVector
RotateCoordToCar:
        ld b, 0
        ld a, 8
        ld c, %11000000
        jr RotateVector
RotateCarToCoord:
        ld b, 6
        ld a, 3
        ld c, %01000000
RotateVector:
        ld (K), a
        ld a, b
        ld (N), a
        ld a, c
        ld (GG), a
        ld c, 1
        xor a
        call MultiplyCoordsN
        ld c, 0
        ld hl, N
        inc (hl)
        ld a, (GG)
        call MultiplyCoordsN
        ld c, 1
        ld hl, K
        inc (hl)
        xor a
        call MultiplyCoordsN
        ld c, 0
        ld hl, N
        dec (hl)
        ld a, (GG)
        xor %10000000
        jp MultiplyCoordsN

; ApplyDeltas: player coordinates += 2 * speed; yaw += spin
ApplyDeltas:
        ld de, playerCoordZ
        ld ix, physHi + PH_ZSPEED
        call @delta
        ld de, playerCoordX
        ld ix, physHi + PH_XSPEED
        call @delta
        ld a, (playerYawAngleLo)
        ld hl, physHi + PH_SPINYAW
        add a, (hl)
        ld (playerYawAngleLo), a
        ld a, (playerYawAngleHi)
        ld hl, physTop + PH_SPINYAW
        adc a, (hl)
        ld (playerYawAngleHi), a
        ret
@delta:                                 ; (DE) 24-bit += 2 * speed (IX)
        ld c, (ix + 0)
        ld b, (ix + 16)
        ld a, b
        rla
        sbc a, a                        ; sign byte
        sla c
        rl b
        rla                             ; A:B:C = 2 * speed
        ld (@top + 1), a
        ex de, hl
        ld a, (hl)
        adc a, c                        ; carry = sign (as the original ROL V)
        ld (hl), a
        inc hl
        ld a, (hl)
        adc a, b
        ld (hl), a
        inc hl
@top:
        ld a, 0
        adc a, (hl)
        ld (hl), a
        ret

; UpdateVelocity: speeds (24-bit) += acceleration << shift (C64: 4, 4, 6)
UpdateVelocity:
        ld ix, physHi + PH_SPINYAW
        ld c, 6
        call @vel
        ld ix, physHi + PH_ZSPEED
        ld c, 4
        call @vel
        ld ix, physHi + PH_XSPEED
        ld c, 4
@vel:
        ld e, (ix + 3)                  ; acceleration = entry + 3
        ld d, (ix + 19)
        ld a, d
        rla
        sbc a, a
        ld l, a                         ; sign extension
        ld b, c
@v1:
        sla e
        rl d
        rl l
        djnz @v1
        ld a, (ix - 3)
        add a, e
        ld (ix - 3), a
        ld a, (ix + 0)
        adc a, d
        ld (ix + 0), a
        ld a, (ix + 16)
        adc a, l
        ld (ix + 16), a
        ret
