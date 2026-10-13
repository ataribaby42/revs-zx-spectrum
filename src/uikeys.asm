; UI keyboard routines, resident at UI_KEYS (free space after the
; projection tables, loaded with the game, kept in every phase)

; UiWaitRelease: until no key is pressed, Caps Shift and Symbol Shift
; excepted (Caps Shift + 0 deletes again while Caps Shift is held)
UiWaitRelease:
        ld a, $81                       ; the rows without the shift keys
        in a, ($FE)
        and 31
        cp 31
        jr nz, UiWaitRelease
        ld a, $FE
        in a, ($FE)
        and %00011110
        cp %00011110
        jr nz, UiWaitRelease
        ld a, $7F
        in a, ($FE)
        and %00011101
        cp %00011101
        jr nz, UiWaitRelease
        ret

; UiKey: the key pressed as a character (letters in capitals), 13 ENTER,
; 8 Caps Shift + 0 (delete), '.' Symbol Shift + M, 0 none
UiKey:
        ld a, $FE
        in a, ($FE)
        bit 0, a
        jr nz, @k1
        ld a, $EF                       ; Caps Shift: only with 0
        in a, ($FE)
        bit 0, a
        ld a, 8
        ret z
        xor a
        ret
@k1:
        ld a, $7F
        in a, ($FE)
        and 6
        ld a, '.'
        ret z
        ld hl, uiKeyChars
        ld d, $FE
@k2:
        ld a, d
        in a, ($FE)
        ld b, 5
@k3:
        rrca
        jr nc, @k4
        inc hl
        djnz @k3
        rlc d
        jr c, @k2
        xor a
        ret
@k4:
        ld a, (hl)
        ret

uiKeyChars:
        db 0, "ZXCV"
        db "ASDFGQWERT1234509876POIUY"
        db 13, "LKJH", ' ', 0, "MNB"
