; Keyboard and random numbers

; Key codes: half-row index * 8 + bit (see tools/zx.py KEYMAP order)
KEY_CAPS        EQU 0 * 8 + 0
KEY_Z           EQU 0 * 8 + 1
KEY_X           EQU 0 * 8 + 2
KEY_C           EQU 0 * 8 + 3
KEY_A           EQU 1 * 8 + 0
KEY_S           EQU 1 * 8 + 1
KEY_Q           EQU 2 * 8 + 0
KEY_W           EQU 2 * 8 + 1
KEY_T           EQU 2 * 8 + 4
KEY_1           EQU 3 * 8 + 0
KEY_2           EQU 3 * 8 + 1
KEY_3           EQU 3 * 8 + 2
KEY_P           EQU 5 * 8 + 0
KEY_O           EQU 5 * 8 + 1
KEY_J           EQU 6 * 8 + 3
KEY_H           EQU 6 * 8 + 4
KEY_SPACE       EQU 7 * 8 + 0
KEY_M           EQU 7 * 8 + 2
KEY_N           EQU 7 * 8 + 3

; Game controls
KEY_LEFT        EQU KEY_O
KEY_RIGHT       EQU KEY_P
KEY_THROTTLE    EQU KEY_Q
KEY_BRAKE       EQU KEY_A
KEY_GEARUP      EQU KEY_W
KEY_GEARDOWN    EQU KEY_S
KEY_FASTSTEER   EQU KEY_SPACE
KEY_START       EQU KEY_T

keyRows:        ds 8            ; bit set = key pressed (row order $FEFE ... $7FFE)
joystickType:   db 0            ; 0: Sinclair joystick 1, 1: Kempston (J)

; ReadKeys: sample the whole keyboard once per frame, then add the joystick
; (Sinclair joystick 1 = keys 6-0, as in the user's ZX version, or Kempston)
; to the driving keys: Up / Down = Q / A, Left / Right = O / P, Fire with
; Up = W (gear up), Fire without Up = S (gear down); the directions stay
; active while Fire is held
ReadKeys:
        ld hl, keyRows
        ld bc, $FEFE
@r1:
        in a, (c)
        cpl
        and $1F
        ld (hl), a
        inc hl
        rlc b
        jr c, @r1
        ld hl, keyRows + 4
        ld a, (joystickType)
        or a
        jr nz, @kempston
        ld a, (hl)                      ; bits: 0 fire, 1 up, 2 down, 3 right,
        rrca                            ; 4 left
        ld c, a                         ; C bits: 0 up, 1 down, 2 right, 3 left
@r3:                                    ; (carry: Fire)
        sbc a, a
        and 2
        ld b, a                         ; B = 2 with Fire: W or S
        inc hl                          ; row 5: P (bit 0), O (bit 1)
        ld a, c
        rrca
        rrca
        and 3
        or (hl)
        ld (hl), a
        ld a, c
        and 1                           ; Up: Q, with Fire also W (not S)
        jr z, @r2
        or b
        ld b, 0
@r2:
        ld hl, keyRows + 2
        or (hl)
        ld (hl), a
        dec hl                          ; row 1: A (bit 0), S (bit 1)
        ld a, c
        rrca
        and 1
        or b
        or (hl)
        ld (hl), a
        ret
@kempston:                              ; port $1F bits: 0 right, 1 left,
        in a, ($1F)                     ; 2 down, 3 up, 4 fire (keys 6-0 stay
        ld b, a                         ; plain keys)
        rla                             ; bit 7 set: no interface (an idle
        ret c                           ; bus reads $FF)
        ld a, b
        rlca
        rlca
        and $0C
        ld c, a                         ; C bits 2 right, 3 left
        ld a, b
        and 4
        rrca
        or c
        ld c, a                         ; bit 1 down
        bit 3, b
        jr z, @k1
        inc c                           ; bit 0 up
@k1:
        ld a, b
        and $10
        add a, $F0                      ; carry = Fire
        jr @r3

; KeyDown: A = key code. Returns NZ if the key is pressed. Preserves BC, DE.
KeyDown:
        push bc
        ld b, a
        rrca
        rrca
        rrca
        and 7
        ld hl, keyRows
        add a, l
        ld l, a
        adc a, h
        sub l
        ld h, a
        ld a, b
        and 7
        ld b, a
        ld a, (hl)
        inc b
@k1:
        rrca
        djnz @k1                        ; carry = key bit
        pop bc
        sbc a, a                        ; A = $FF if pressed
        or a
        ret

; Random: 8-bit pseudo-random number (16-bit xorshift); replaces the C64
; CIA timer / BBC VIA timer reads. Preserves BC, DE.
randSeed:       dw $A5C3

Random:
        ld hl, (randSeed)
        ld a, h
        rra
        ld a, l
        rra
        xor h
        ld h, a
        ld a, l
        rra
        ld a, h
        rra
        xor l
        ld l, a
        xor h
        ld h, a
        ld (randSeed), hl
        ret
