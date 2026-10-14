; Projection routines (see proj.asm for the tables and variables)
;
; A 16-bit value is normalised (inline, four times) into a mantissa fraction
; M (the 8 bits after the leading one) and an exponent code e: for H <> 0,
; e = n, the leading zeros of H, and HL is shifted left n + 1 times (a jump
; into a chain of ADD HL,HL); for H = 0, e = 8 + the leading zeros of L and
; M comes from a table.

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
        push bc
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
        ld b, h                         ; B: the sign of dx
        jp p, @x1
        NEGHL
@x1:
        ld (absDx), hl
        ld h, SEG_LO / 256
        ld a, c
        add a, 2
        ld l, a
        ld e, (hl)
        inc h
        ld d, (hl)
projRefZ:
        ld hl, (playerCoordZ + 1)
        ex de, hl
        or a
        sbc hl, de                      ; dz
        ld a, h
        xor b
        rl b
        rra
        ld c, a                         ; C: bit 7 the sign of dx, bit 6 set
        bit 7, h                        ; when the signs differ
        jr z, @z1
        NEGHL
@z1:
        ld (absDz), hl
        ld a, h                         ; normalise |dz|: Mz, ez
        or a
        jp z, @zLow
        ld d, P_EXPC / 256
        ld e, a
        ld a, (de)
        ld b, a
        cpl
        add a, 8
        ld (@zs + 1), a
@zs:
        jr @zc                          ; offset patched: n + 1 shifts follow
@zc:
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, h
@zn:
        ld (@mz + 1), a
        ld a, b
        ld (@ez + 1), a
        ld hl, (absDx)                  ; normalise |dx|: Mx, ex
        ld a, h
        or a
        jp z, @xLow
        ld d, P_EXPC / 256
        ld e, a
        ld a, (de)
        ld b, a
        cpl
        add a, 8
        ld (@xs + 1), a
@xs:
        jr @xc                          ; offset patched
@xc:
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, h
@xn:
        ld l, a                         ; L = Mx
        ld a, b
@ez:
        sub 0                           ; ex - ez (patched)
        add a, a
        add a, a
        ld b, a                         ; II = (ex - ez) * 4
        ld h, P_LOGLO / 256
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
        ld e, (hl)                      ; E = T = 256 * min / max
        ld d, P_ANGHI / 256
        ld a, (de)
        ld h, a
        dec d
        ld a, (de)
        ld l, a                         ; HL = the angle of T
        ld a, b
        or a
        ld a, e
        jp p, @dxBig

        ; |dx| < |dz|: angle measured from straight ahead
        cp $54
        sbc a, a
        ld b, a                         ; B = $FF: T < $54
        bit 6, c
        jr z, @a1
        NEGHL                           ; the signs differ: negative
@a1:
        ld a, c                         ; + $8000 when dz < 0
        add a, a
        xor c
        and $80
        add a, h
        ld h, a
        ld (II), hl                     ; II, JJ
        inc b
        jr nz, @a2
        ld hl, (absDx)                  ; distance = |dz| + |dx| / 8
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld de, (absDz)
        add hl, de
        ld (K), hl
        pop bc
        ret
@a2:
        pop bc
        jp DistDxHalf                   ; |dx| / 2 + |dz| - |dz| / 8

@dxBig:                                 ; |dx| > |dz|: angle measured from the side
        cp $54
        sbc a, a
        ld b, a
        bit 6, c
        jr nz, @b1
        NEGHL                           ; the same signs: negative
@b1:
        ld a, c                         ; + $4000, or $C000 when dx < 0
        and $80
        or $40
        add a, h
        ld h, a
        ld (II), hl
        inc b
        jr nz, @b2
        ld hl, (absDz)                  ; distance = |dx| + |dz| / 8
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld de, (absDx)
        add hl, de
        ld (K), hl
        pop bc
        ret
@b2:
        pop bc
        jp DistDzHalf                   ; |dz| / 2 + |dx| - |dx| / 8

@zLow:                                  ; |dz| < 256
        or l
        jr z, @dzZero
        ld e, l
        ld d, P_EXPC / 256
        ld a, (de)
        or 8
        ld b, a
        dec d                           ; P_MANT
        ld a, (de)
        jp @zn
@xLow:                                  ; |dx| < 256
        or l
        jr z, @dxZero
        ld e, l
        ld d, P_EXPC / 256
        ld a, (de)
        or 8
        ld b, a
        dec d
        ld a, (de)
        jp @xn

@tiny:                                  ; ratio below 1/256: angle 0
        ld a, b
        or a
        jp m, @dxZero
@dzZero:                                ; |dz| = 0: object directly to the side
        call DistDzHalf
        ld a, c
        and $80
        or $40
        jr @angle
@dxZero:                                ; |dx| = 0: straight ahead or behind
        call DistDxHalf
        ld a, c
        add a, a
        xor c
        and $80
        jr @angle
@equal:                                 ; |dx| = |dz|: 45 degrees
        call DistDxHalf
        ld a, c                         ; $20, $60, $A0 or $E0
        and $C0
        add a, $20
@angle:
        ld h, a
        ld l, 0
        ld (II), hl
        pop bc
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
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ex de, hl
        pop hl
        or a
        sbc hl, de
        ld (K), hl
        ret

; ---------------------------------------------------------------------------
; GetObjPitchAngle: pitch angle (LL) and scale (scaleUp/scaleDown) of segment
; buffer entry C relative to the player, using the distance (L,K) from the
; preceding GetObjYawAngle. Returns carry set if the point is not visible,
; otherwise carry clear and the sign flag set from LL. Preserves C.

GetObjPitchAngle:
        push bc
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
        ld c, h                         ; C: the sign of dy
        jp p, @y1
        NEGHL
@y1:
        ld a, l
        and $F8                         ; (the height's low 3 bits are not
        ld l, a                         ; used)
        ld (absDy), hl
        ld hl, (K)                      ; normalise the distance: Md, ed
        ld a, h
        or a
        jp z, @dLow
        ld d, P_EXPC / 256
        ld e, a
        ld a, (de)
        ld b, a
        cpl
        add a, 8
        ld (@ds + 1), a
@ds:
        jr @dc                          ; offset patched: n + 1 shifts follow
@dc:
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, h
@dn:
        ld (@md + 1), a
        ld e, a
        ld a, b
        ld (scaleDown), a
        ld (@ed + 1), a
        ld a, e
        srl a
        ld l, a
        ld h, P_SCALE / 256
        ld a, (hl)
        ld (scaleUp), a
        ld hl, (absDy)                  ; normalise the height: My, ey
        ld a, h
        or a
        jp z, @yLow
        ld d, P_EXPC / 256
        ld e, a
        ld a, (de)
        ld b, a
        cpl
        add a, 8
        ld (@ys + 1), a
@ys:
        jr @yc                          ; offset patched
@yc:
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, h
@yn:
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
        ld a, (hl)                      ; T
        cp $80
        jr nc, @invisible
@t:
        bit 7, c
        jr z, @up
        neg                             ; below: 60 - T, above: 60 + T
@up:
        add a, 60
        ld hl, playerPitchAngle
        sub (hl)
        ld (LL), a
        pop bc
        or a
        ret
@invisible:
        pop bc
        scf
        ret
@zero:
        xor a
        jr @t
@dLow:                                  ; distance < 256
        or l
        jr z, @invisible                ; distance 0
        ld e, l
        ld d, P_EXPC / 256
        ld a, (de)
        or 8
        ld b, a
        dec d                           ; P_MANT
        ld a, (de)
        jp @dn
@yLow:                                  ; height < 256
        or l
        jr z, @zero
        ld e, l
        ld d, P_EXPC / 256
        ld a, (de)
        or 8
        ld b, a
        dec d
        ld a, (de)
        jp @yn
