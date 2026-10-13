; Projection routines (see proj.asm for the tables and variables)

; ---------------------------------------------------------------------------
; Normalize: HL = non-zero value. Returns A = mantissa fraction (the 8 bits
; after the leading one) and B = exponent code. Corrupts DE, HL.

Normalize:
        ld a, h
        or a
        jr z, @low
        ld d, P_EXPC / 256
        ld e, a
        ld a, (de)
        ld b, a                         ; n = leading zeros of H
        cpl
        add a, 8                        ; skip 7 - n shifts
        ld (@shift + 1), a
@shift:
        jr @chain                       ; offset patched: n + 1 shifts follow
@chain:
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, h
        ret
@low:
        ld e, l
        ld d, P_EXPC / 256
        ld a, (de)
        or 8
        ld b, a
        dec d                           ; P_MANT
        ld a, (de)
        ret

; ---------------------------------------------------------------------------
; UsePlayerReference / UseSignReference: select the reference point of the
; projection: the player (BBC Y = 0) or the road sign base (BBC Y = 6)

UsePlayerReference:
        ld hl, playerCoordX + 1
        ld de, playerCoordY + 1
        ld bc, playerCoordZ + 1
        jr UseReference
UseSignReference:
        ld hl, roadSignCoordX
        ld de, roadSignCoordY
        ld bc, roadSignCoordZ
UseReference:
        ld (projRefX + 1), hl
        ld (projRefY + 1), de
        ld (projRefZ + 1), bc
        ret

; GetObjYawAngle: yaw angle (JJ,II) and distance (L,K) of segment buffer
; entry C relative to the reference point (normally the player). Preserves C.

GetObjYawAngle:
        ld h, SEG_LO / 256
        ld l, c
        ld e, (hl)
        inc h
        ld d, (hl)
projRefX:
        ld hl, (playerCoordX + 1)       ; reference point (patched by
        ex de, hl                       ; UseSignReference)
        or a
        sbc hl, de                      ; dx
        ld a, h
        ld (signDx), a
        or a
        jp p, @x1
        NEGHL
@x1:
        ld (absDx), hl
        ld a, c
        add a, 2
        ld l, a
        ld h, SEG_LO / 256
        ld e, (hl)
        inc h
        ld d, (hl)
projRefZ:
        ld hl, (playerCoordZ + 1)
        ex de, hl
        or a
        sbc hl, de                      ; dz
        ld a, h
        ld (signDz), a
        or a
        jp p, @z1
        NEGHL
@z1:
        ld (absDz), hl
        ld a, h
        or l
        jp z, @dzZero
        call Normalize                  ; A = Mz, B = ez
        ld (@mz + 1), a
        ld a, b
        ld (@ez + 1), a
        ld hl, (absDx)
        ld a, h
        or l
        jp z, @dxZero
        call Normalize                  ; A = Mx, B = ex
        ld e, a
        ld a, b
@ez:
        sub 0                           ; ex - ez (patched)
        add a, a
        add a, a
        ld b, a                         ; II = (ex - ez) * 4
        ld h, P_LOGLO / 256
        ld l, e
        ld e, (hl)
        inc h
        ld d, (hl)                      ; DE = LOG[Mx]
@mz:
        ld l, 0                         ; Mz (patched)
        dec h
        ld a, e
        sub (hl)
        ld e, a
        inc h
        ld a, d
        sbc a, (hl)
        sub b
        ld d, a                         ; DE = log|dx| - log|dz|
        ld b, a                         ; U: its sign says which delta is larger
        or a
        jp m, @dneg
        NEGDE                           ; D = log(min / max) <= 0
@dneg:
        ld a, d
        add a, $20
        jp m, @tiny
        srl a
        rr e
        srl a
        rr e
        cp 8
        jp nc, @equal
        add a, P_EXPTAB / 256
        ld h, a
        ld l, e
        ld e, (hl)                      ; T = 256 * min / max
        ld d, P_ANGLO / 256
        ld a, (de)
        ld (II), a
        inc d
        ld a, (de)
        ld (JJ), a
        ld a, b
        or a
        jp p, @dxBig

        ; |dx| < |dz|: angle measured from straight ahead
        ld a, e
        cp $54
        jr nc, @a2
        ld hl, (absDx)                  ; distance = |dz| + |dx| / 8
        call Shr3
        ld de, (absDz)
        add hl, de
        ld (K), hl
        jr @a4
@a2:
        call DistDxHalf                 ; |dx| / 2 + |dz| - |dz| / 8
@a4:                                    ; quadrant, angle from ahead
        ld a, (signDx)
        ld hl, signDz
        xor (hl)
        call m, NegateIIJJ
        ld a, (signDz)
        and $80
        ld hl, JJ
        add a, (hl)
        ld (hl), a
        ret

@dxBig:                                 ; |dx| > |dz|: angle measured from the side
        ld a, e
        cp $54
        jr nc, @b2
        ld hl, (absDz)                  ; distance = |dx| + |dz| / 8
        call Shr3
        ld de, (absDx)
        add hl, de
        ld (K), hl
        jr @b4
@b2:
        call DistDzHalf                 ; |dz| / 2 + |dx| - |dx| / 8
@b4:
        ld a, (signDx)
        ld hl, signDz
        xor (hl)
        call p, NegateIIJJ
        ld a, (signDx)
        or a
        ld a, $40
        jp p, @b5
        ld a, $C0
@b5:
        ld hl, JJ
        add a, (hl)
        ld (hl), a
        ret

@tiny:                                  ; ratio below 1/256: angle 0
        xor a
        ld (II), a
        ld (JJ), a
        ld a, b
        or a
        jp m, @dxSmall
        jr @dzSmall

@dzZero:                                ; |dz| = 0: object directly to the side
        xor a
        ld (II), a
        ld (JJ), a
@dzSmall:
        call DistDzHalf
        jr @b4

@dxZero:                                ; |dx| = 0: straight ahead or behind
        xor a
        ld (II), a
        ld (JJ), a
@dxSmall:
        call DistDxHalf
        jr @a4

@equal:                                 ; |dx| = |dz|: 45 degrees
        call DistDxHalf
        xor a
        ld (II), a
        ld a, (signDx)
        or a
        jp p, @e2
        ld a, (signDz)
        or a
        ld a, $A0
        jp m, @e4
        ld a, $E0
        jr @e4
@e2:
        ld a, (signDz)
        or a
        ld a, $60
        jp m, @e4
        ld a, $20
@e4:
        ld (JJ), a
        ret

; (L,K) = |dx| / 2 + |dz| - (|dz| >> 3)
DistDxHalf:
        ld de, (absDx)
        ld hl, (absDz)
        jr DistHalf
; (L,K) = |dz| / 2 + |dx| - (|dx| >> 3)
DistDzHalf:
        ld de, (absDz)
        ld hl, (absDx)
DistHalf:                               ; K = DE/2 + HL - HL>>3
        srl d
        rr e
        push hl
        add hl, de
        ex (sp), hl
        call Shr3
        ex de, hl
        pop hl
        or a
        sbc hl, de
        ld (K), hl
        ret

Shr3:                                   ; HL = HL >> 3 (logical)
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ret

NegateIIJJ:
        ld hl, (II)
        NEGHL
        ld (II), hl
        ret

; ---------------------------------------------------------------------------
; GetObjPitchAngle: pitch angle (LL) and scale (scaleUp/scaleDown) of segment
; buffer entry C relative to the player, using the distance (L,K) from the
; preceding GetObjYawAngle. Returns carry set if the point is not visible,
; otherwise carry clear and the sign flag set from LL. Preserves C.

GetObjPitchAngle:
        ld h, SEG_LO / 256
        ld a, c
        inc a
        ld l, a
        ld e, (hl)
        inc h
        ld d, (hl)
projRefY:
        ld hl, (playerCoordY + 1)
        ex de, hl
        or a
        sbc hl, de                      ; dy
        ld a, h
        ld (signDy), a
        or a
        jp p, @y1
        NEGHL
@y1:
        ld (absDy), hl
        ld hl, (K)
        ld a, h
        or l
        jp z, @invisible                ; distance 0
        call Normalize                  ; distance: A = Md, B = ed
        ld e, a
        ld a, b
        ld (scaleDown), a
        ld (@ed + 1), a
        ld a, e
        ld (@md + 1), a
        scf
        rra                             ; $80 | Md >> 1
        sub $80
        ld l, a
        ld h, P_SCALE / 256
        ld a, (hl)
        ld (scaleUp), a
        ld hl, (absDy)
        ld a, l
        and $F8
        ld l, a
        or h
        jr z, @zero
        call Normalize                  ; height: A = My, B = ey
        ld e, a
        ld a, b
        sub 5
@ed:
        sub 0                           ; ed (patched)
        add a, a
        add a, a
        ld b, a                         ; II = (ey - 5 - ed) * 4
        ld h, P_LOG2LO / 256
        ld l, e
        ld e, (hl)
        inc h
        ld d, (hl)                      ; DE = LOG2[My]
@md:
        ld l, 0                         ; Md (patched)
        ld h, P_LOGLO / 256
        ld a, e
        sub (hl)
        ld e, a
        inc h
        ld a, d
        sbc a, (hl)
        sub b
        jp m, @zero
        cp $20
        jr nc, @invisible
        srl a
        rr e
        srl a
        rr e
        add a, P_EXPTAB / 256
        ld h, a
        ld l, e
        ld a, (hl)
        jr @t
@zero:
        xor a
@t:
        ld (ratioT), a
        cp $80
        jr nc, @invisible
        ld b, a
        ld a, (signDy)
        or a
        jp p, @up
        ld a, 60
        sub b
        jr @p7
@up:
        ld a, b
        add a, 60
@p7:
        ld hl, playerPitchAngle
        sub (hl)
        ld (LL), a
        or a
        ret
@invisible:
        scf
        ret
