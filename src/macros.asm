; Macros (defined before the code that uses them)

; (vars.asm)
; Load IX/IY for object index A (0..23)
OBJ_INDEX MACRO
        add a, OBJ_BIAS
        ld ixl, a
        ld ixh, OBJ_PAGE >> 8
        ENDM

; (vars.asm)
CAR_INDEX MACRO
        add a, OBJ_BIAS
        ld iyl, a
        ld iyh, CAR_PAGE >> 8
        ENDM

; (physics.asm)
PHYS_IX MACRO idx
        ld ix, physHi + idx
        ENDM

; (proj_code.asm)
NEGHL   MACRO
        xor a
        sub l
        ld l, a
        sbc a, a
        sub h
        ld h, a
        ENDM

; (proj_code.asm)
NEGDE   MACRO
        xor a
        sub e
        ld e, a
        sbc a, a
        sub d
        ld d, a
        ENDM

; (objects.asm)
CAR_AXIS MACRO axis
        ld a, (bc)
        inc b
        push bc
        push de
        call MulSignedHi                ; (B A)
        pop de
        ld c, a
        ld a, e
        add a, axis
        ld l, a
        ld h, SEG_HI / 256
        ld a, (hl)
        add a, b
        ld b, a
        dec h
        ld a, (hl)
        add a, c
        ld l, xCoord2 + axis
        ld (hl), a
        inc h
        ld a, b
        adc a, 0
        ld (hl), a
        pop bc
        ENDM

; (objects.asm)
; CAR_OUTER axis: coordinate xCoord2 + axis += 4 * signed A * D / 256
CAR_OUTER MACRO axis
        call MulSignedHi
        sla a
        rl b
        sla a
        rl b
        ld hl, SEG_LO + xCoord2 + axis
        add a, (hl)
        ld (hl), a
        inc h
        ld a, b
        adc a, (hl)
        ld (hl), a
        ENDM
