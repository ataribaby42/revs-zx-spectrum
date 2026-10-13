; Static screen set-up (cold code, runs once)

ATTR_HUD        EQU %01111000           ; black ink on bright white paper
ATTR_VIEW       EQU %01111000           ; bright white paper, black ink
ATTR_COCKPIT    EQU %01111000
ATTR_HIDDEN     EQU %01111111           ; bright white ink on white paper

InitScreen:
        ; bitmap: clear
        ld hl, $4000
        ld de, $4001
        ld bc, $1800 - 1
        ld (hl), 0
        ldir
        ; attributes: HUD rows 0-1, the hidden sky (rows 2-9, ink = paper:
        ; it keeps the UI overlay while driving), the view and the cockpit
        ld hl, $5800
        ld bc, HIDDEN_ROW * 32 - 1
        ld a, ATTR_HUD
        call @fill
        ld bc, HIDDEN_ROWS * 32 - 1
        ld a, ATTR_HIDDEN
        call @fill
        ld bc, (24 - HIDDEN_ROW - HIDDEN_ROWS) * 32 - 1
        ld a, ATTR_VIEW
        call @fill
        ; cockpit bitmap rows 115..191
        ld hl, CockpitBitmap
        ld b, 115
@c1:
        push bc
        ld a, b
        call ScreenRowAddr
        ld bc, 32
        ldir
        pop bc
        inc b
        ld a, b
        cp 192
        jr nz, @c1
        ret

@fill:                                  ; A from HL on, BC + 1 bytes; HL = next
        ld (hl), a
        ld d, h
        ld e, l
        inc de
        ldir
        ex de, hl
        ret

CockpitBitmap:
        INCBIN "gfx/cockpit.bin"         ; 77 rows x 32 bytes
