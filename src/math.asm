; Arithmetic helpers

; Div16by8: HL = HL / C (unsigned, C < 128), A = remainder. Preserves C, DE.
Div16by8:
        xor a
        REPT 16
        add hl, hl
        rla
        cp c
        jr c, $ + 4
        sub c
        inc l
        ENDR
        ret

; ---------------------------------------------------------------------------
; Multiplication (exact, quarter-square tables). The BBC conventions are kept:
; Multiply8x8: (A T) = A * U, Multiply8x8T: (A T) = T * U. Preserve BC, DE.
        ASSERT U == T + 1               ; (LD DE,(T))

Multiply8x8:
        ld (T), a
Multiply8x8T:
        push de
        push bc
        ld de, (T)                      ; E = T, D = U
        ld a, d
        add a, e
        ld l, a
        ld a, QSQ_LO / 256
        adc a, 0
        ld h, a
        ld c, (hl)
        inc h
        inc h
        ld b, (hl)                      ; BC = Q[a + b]
        ld a, d
        sub e
        jr nc, @p
        neg
@p:
        ld l, a
        ld h, QSQ_LO / 256
        ld a, c
        sub (hl)
        ld (T), a
        inc h
        inc h
        ld a, b
        sbc a, (hl)                     ; A = high byte
        pop bc
        pop de
        ret

; Multiply8x16: (U T) = U * (V T) / 256
Multiply8x16:
        call Multiply8x8T
        ld (W), a
        ld a, (V)
        call Multiply8x8
        ld (U), a
        ld a, (W)
        ld hl, T
        add a, (hl)
        ld (hl), a
        ret nc
        ld hl, U
        inc (hl)
        ret

; GetAngleInRadians: (A T) * 4 -> V, then (U T) = 201 * (V T) / 256
GetAngleInRadians:
        ld hl, T
        sla (hl)
        rla
        sla (hl)
        rla
        ld (V), a
        ld a, 201
        ld (U), a
        jr Multiply8x16

; Negate16: (A T) = -(A T); U = original A (as the BBC Negate16Bit)
Negate16:
        ld (U), a
Negate16U:                              ; (A T) = -(U T)
        ld hl, T
        xor a
        sub (hl)
        ld (hl), a
        ld a, 0
        ld hl, U
        sbc a, (hl)
        ret

; Abs16: if A (the high byte) is negative, negate (A T)
Abs16:
        or a
        ret p
        jp Negate16

; Multiply8x16Signed: (A T) = B * (A T) / 256, keeping the sign of A
Multiply8x16Signed:
        push af
        call Abs16
        ld (V), a
        ld a, b
        ld (U), a
        call Multiply8x16
        ld a, (U)
        pop hl                          ; H = original A (sign)
        bit 7, h
        ret z
        jp Negate16

; MultiplyBy1Point5: (A T) = 1.5 * (U T), signed
MultiplyBy1Point5:
        ld a, (U)
        sra a
        ld d, a                         ; high byte of the halved value
        ld a, (T)
        rra                             ; low byte (carry from SRA)
        ld hl, T
        add a, (hl)
        ld (hl), a
        ld a, (U)
        adc a, d
        ret

; GetRotationMatrix: sin and cos of the yaw angle (A = high, T = low)
GetRotationMatrix:
        ld (J), a
        call GetAngleInRadians
        ld (G), a                       ; A = T after Multiply8x16
        ld a, (U)
        ld (Hv), a
        ld c, 0                         ; X
        ld b, 1                         ; secondAxis
        ld a, (J)
        bit 6, a
        jr z, @r0
        inc c
        dec b
@r0:
        ld a, b
        ld (secondAxis), a
        ld a, (Hv)
@rotm1:
        cp 122
        jr nc, @rotm3
        ; sin for smaller angles: x - x^3 / 6
        ld a, 171
        call Multiply8x8
        call Multiply8x8
        ld (V), a
        call Multiply8x16
        ld a, (G)
        ld hl, T
        sub (hl)
        ld (hl), a
        ld a, (Hv)
        ld hl, U
        sbc a, (hl)
        ld hl, T
        sla (hl)
        rla
        ld hl, sinYawAngleHi
        call @store
        ld a, (T)
        and %11111110
        ld hl, sinYawAngleLo
        call @store
        jr @rotm5
@rotm3:                                 ; bigger angles
        ld a, (G)
        neg
        ld (T), a
        ld a, 201
        jr nz, @r3
        ld hl, Hv                        ; 0 - G sets no borrow when G = 0
        sub (hl)
        jr @r4
@r3:
        ld hl, Hv
        sbc a, (hl)                     ; 201 - H - borrow (borrow set: G <> 0)
@r4:
        ld (U), a
        ld (V), a
        call Multiply8x16
        ld hl, T
        sla (hl)
        ld hl, U
        rl (hl)
        ld a, (T)
        neg
        push af
        and %11111110
        ld hl, sinYawAngleLo
        call @store
        pop af                          ; carry = borrow of 0 - T
        ld a, 0
        ld hl, U
        sbc a, (hl)
        jr c, @rotm4
        ld a, %11111110
        ld hl, sinYawAngleLo
        call @store
        ld a, %11111111
@rotm4:
        ld hl, sinYawAngleHi
        call @store
@rotm5:
        ld a, (secondAxis)
        cp c
        jr z, @rotm6
        ld c, a
        ld a, (G)
        neg
        ld (G), a
        ld a, 201
        jr nz, @r5
        ld hl, Hv
        sub (hl)
        jr @r6
@r5:
        ld hl, Hv
        sbc a, (hl)
@r6:
        ld (Hv), a
        ld (U), a
        jp @rotm1
@rotm6:
        ld a, (J)
        or a
        jp p, @rotm7
        ld hl, sinYawAngleLo
        set 0, (hl)
@rotm7:
        ld a, (J)
        ld b, a
        add a, a
        xor b
        ret p
        ld hl, cosYawAngleLo
        set 0, (hl)
        ret
@store:                                 ; (HL + C) = A
        push af
        ld a, l
        add a, c
        ld l, a
        jr nc, @s1
        inc h
@s1:
        pop af
        ld (hl), a
        ret
