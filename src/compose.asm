; Row compositor: turns the per-line edge tables into the view buffer.
;
; View buffer: VIEW_ROWS rows of 32 bytes, row 0 = track line 79 (top).
; Each row is grass | left verge | road | right verge | grass, or sky above
; the horizon; patterns depend on the parity of the track line. Whole bytes
; are written by jumping into an unrolled fill chain ("ld (hl),b / inc l"
; x 32, returning with JP (IY)); a byte holding a boundary is merged from
; the patterns on either side. A boundary at x = 255 is an edge clamped at the
; right border: its mask (MASKX) is 0, the span left of it fills the row.

; Compose page layout (page aligned, see the end of this file)
CP_FILL_END     EQU 64                  ; offset of the JP (IY) after the chain
CP_PATVERGE     EQU $80                 ; verge patterns [colour * 2 + parity]
CP_PATGRASS     EQU $88                 ; grass patterns [parity]
CP_PATROAD      EQU $8A                 ; road patterns [parity]

; SPANn (expanded below for n = 0..3): the current span (pattern B) ends at
; pixel A, the next one has pattern C, HL = next byte to write, C' = the low
; address byte of the row start. Fills the whole bytes before the boundary
; byte, then merges the boundary byte (or re-merges the byte just written
; when the boundary lies in it). A boundary at a byte start merges the whole
; byte (mask $FF), which is the same as the next span filling it.

; Sky rows that are still sky in the buffer from the last frame (skyClean)
; are not written again.
skyClean:       db 0                    ; top rows of VIEW_BUF that hold pure sky
screenSky:      db VIEW_ROWS            ; top view rows on the screen that are sky
objTopRow:      db VIEW_ROWS            ; highest row written by objects

; SkyRows: A = number of sky rows of this frame (lines above horizonLine)
SkyRows:
        ld a, (horizonLine)
        cp VIEW_ROWS
        jr c, @s1
        xor a
        ret
@s1:
        cpl
        add a, VIEW_ROWS                ; 79 - horizonLine
        ret

Compose:
        ld ixh, COMPOSE_PAGE / 256
        call SkyRows
        ld b, a
        ld a, (skyClean)                ; start at min(skyClean, sky rows)
        cp b
        jr c, @c1
        ld a, b
@c1:
        cp VIEW_ROWS - HIDDEN_LINES     ; the bottom rows are behind the cockpit
        ret nc
        ld l, a                         ; HL = VIEW_BUF + 32 * row
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, VIEW_BUF
        add hl, de
        cpl
        add a, VIEW_ROWS                ; track line = 79 - row
        exx
        ld b, a                         ; B' = track line
        exx
@row:                                   ; HL = row start, B' = its track line
        ld a, l
        exx
        ld c, a                         ; C' = row start (low byte)
        ld a, b
        exx
        ld c, a                         ; C = track line
        ld a, (horizonLine)
        cp c
        jr nc, @ground
        ld b, PAT_SKY
        jp @whole
@ground:
        push hl
        ld a, c                         ; parity -> patterns
        and 1
        ld e, a
        add a, CP_PATGRASS
        ld l, a
        ld h, COMPOSE_PAGE / 256
        ld b, (hl)                      ; B = grass
        add a, CP_PATROAD - CP_PATGRASS
        ld l, a
        ld a, (hl)
        ld (@road + 1), a
        ld a, b
        ld (@grass + 1), a
        ld a, c
        add a, EDGE_COLL % 256
        ld d, a                         ; D = low byte of EDGE_COLL + line
        ld l, a
        ld h, EDGE_COLL / 256
        ld a, (hl)                      ; left verge colour
        cp $FF
        jp z, @grassRow
        add a, a
        add a, e
        add a, CP_PATVERGE
        ld l, a
        ld h, COMPOSE_PAGE / 256
        ld a, (hl)
        ld (@vl + 1), a
        ld a, d
        add a, EDGE_COLR - EDGE_COLL
        ld l, a
        ld h, EDGE_COLR / 256
        ld a, (hl)                      ; right verge colour
        cp $FF
        jp z, @grassRow
        add a, a
        add a, e
        add a, CP_PATVERGE
        ld l, a
        ld h, COMPOSE_PAGE / 256
        ld a, (hl)
        ld (@vr + 1), a
        ; boundaries b0 .. b3
        ld a, c
        ld l, a
        ld h, EDGE_LOUT / 256
        ld d, (hl)
        add a, EDGE_LIN - EDGE_LOUT
        ld l, a
        ld e, (hl)
        add a, EDGE_RIN - EDGE_LIN
        ld l, a
        ld a, (hl)
        ld h, EDGE_ROUT / 256
        ld l, c
        ld c, a
        ld a, e                         ; b2 = max(b1, b2)
        cp c
        jr c, @o1
        ld c, e
@o1:
        ld a, (hl)                      ; b3 = max(b2, b3)
        cp c
        jr nc, @o2
        ld a, c
@o2:
        ld (@b3 + 1), a
        ld a, c
        ld (@b2 + 1), a
        ld a, e
        ld (@b1 + 1), a
        ld a, d                         ; b0 = min(b0, b1)
        cp e
        jr c, @o3
        ld a, e
@o3:
        pop hl
@vl:
        ld c, 0                         ; patched: left verge pattern
        ld e, a                         ; SPAN 0
        rrca
        rrca
        rrca
        and $1F
        exx
        add a, c                        ; boundary byte (low address byte)
        exx
        sub l                           ; bytes before it
        jr z, @m0
        jp m, @fix0
        add a, a                        ; fill them: enter the chain at
        cpl                             ; CP_FILL_END - 2 * count
        add a, CP_FILL_END + 1
        ld ixl, a
        ld iy, @m0
        jp (ix)
@fix0:
        dec l                           ; the boundary is in the byte just
        ld b, (hl)                      ; written: merge into that byte
@m0:
        ld d, MASKX / 256
        ld a, (de)                      ; bits from the boundary on
        ld e, a
        ld a, b
        xor c
        and e
        xor b
        ld (hl), a
        inc l
        ld b, c                         ; grass | left verge
@road:
        ld c, 0                         ; patched: road
@b1:
        ld a, 0                         ; patched: b1
        ld e, a                         ; SPAN 1
        rrca
        rrca
        rrca
        and $1F
        exx
        add a, c                        ; boundary byte (low address byte)
        exx
        sub l                           ; bytes before it
        jr z, @m1
        jp m, @fix1
        add a, a                        ; fill them: enter the chain at
        cpl                             ; CP_FILL_END - 2 * count
        add a, CP_FILL_END + 1
        ld ixl, a
        ld iy, @m1
        jp (ix)
@fix1:
        dec l                           ; the boundary is in the byte just
        ld b, (hl)                      ; written: merge into that byte
@m1:
        ld d, MASKX / 256
        ld a, (de)                      ; bits from the boundary on
        ld e, a
        ld a, b
        xor c
        and e
        xor b
        ld (hl), a
        inc l
        ld b, c                         ; left verge | road
@vr:
        ld c, 0                         ; patched: right verge pattern
@b2:
        ld a, 0                         ; patched: b2
        ld e, a                         ; SPAN 2
        rrca
        rrca
        rrca
        and $1F
        exx
        add a, c                        ; boundary byte (low address byte)
        exx
        sub l                           ; bytes before it
        jr z, @m2
        jp m, @fix2
        add a, a                        ; fill them: enter the chain at
        cpl                             ; CP_FILL_END - 2 * count
        add a, CP_FILL_END + 1
        ld ixl, a
        ld iy, @m2
        jp (ix)
@fix2:
        dec l                           ; the boundary is in the byte just
        ld b, (hl)                      ; written: merge into that byte
@m2:
        ld d, MASKX / 256
        ld a, (de)                      ; bits from the boundary on
        ld e, a
        ld a, b
        xor c
        and e
        xor b
        ld (hl), a
        inc l
        ld b, c                         ; road | right verge
@grass:
        ld c, 0                         ; patched: grass
@b3:
        ld a, 0                         ; patched: b3
        ld e, a                         ; SPAN 3
        rrca
        rrca
        rrca
        and $1F
        exx
        add a, c                        ; boundary byte (low address byte)
        exx
        sub l                           ; bytes before it
        jr z, @m3
        jp m, @fix3
        add a, a                        ; fill them: enter the chain at
        cpl                             ; CP_FILL_END - 2 * count
        add a, CP_FILL_END + 1
        ld ixl, a
        ld iy, @m3
        jp (ix)
@fix3:
        dec l                           ; the boundary is in the byte just
        ld b, (hl)                      ; written: merge into that byte
@m3:
        ld d, MASKX / 256
        ld a, (de)                      ; bits from the boundary on
        ld e, a
        ld a, b
        xor c
        and e
        xor b
        ld (hl), a
        inc l
        ld b, c                         ; right verge | grass
        exx                             ; grass to the end of the row
        ld a, c
        exx
        add a, 32
        sub l
        jr z, @next
        add a, a
        cpl
        add a, CP_FILL_END + 1
        ld ixl, a
        ld iy, @next
        jp (ix)
@grassRow:
        pop hl                          ; 32 bytes of grass (B)
@whole:                                 ; 32 bytes of B
        ld ixl, 0
        ld iy, @next
        jp (ix)
@next:                                  ; HL = row start + 32 (low byte)
        ld a, l
        or a
        jr nz, @n1
        inc h                           ; the next page
@n1:
        exx
        dec b
        ld a, b
        exx
        IF HIDDEN_LINES
        cp HIDDEN_LINES
        jp nc, @row
        ELSE
        jp p, @row
        ENDIF
        ret

        ALIGN 256
COMPOSE_PAGE:
        REPT 32
        ld (hl), b
        inc l
        ENDR
        jp (iy)
        ds CP_PATVERGE - CP_FILL_END - 2
        db %10101010, %01010101         ; colour 0: red (50%)
        db %11111111, %11111111         ; colour 1: black
        db %00000000, %00000000         ; colour 2: white
        db %00000000, %00000000         ; colour 3
        db %10001000, %00100010         ; grass (25%)
        db %11111111, %11111111         ; road (black, as on the C64)

; EndView: after the objects have been drawn, work out which rows are sky
; (in the buffer and, after the next copy, on the screen) and where the
; interrupt's view copy has to start
EndView:
        call SkyRows
        ld b, a
        ld a, (objTopRow)
        cp b
        jr c, @e1
        ld a, b
@e1:
        ld (skyClean), a                ; sky rows of this frame's buffer
        ld b, a
        ld a, (screenSky)
        cp b
        jr c, @e2
        ld a, b
@e2:
        ld (viewCopyStart), a           ; rows differing from the screen
        ld a, b
        ld (screenSky), a
        ld a, VIEW_ROWS
        ld (objTopRow), a
        ret
