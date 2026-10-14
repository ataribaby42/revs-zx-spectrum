; Row compositor: turns the per-line edge tables into the view buffer.
;
; View buffer: VIEW_ROWS rows of 32 bytes, row 0 = track line 79 (top).
; Each row is grass | left verge | road | right verge | grass, or sky above
; the horizon; patterns depend on the parity of the track line. Whole bytes
; are written by jumping into an unrolled fill chain ("ld (hl),b / inc l"
; x 32, returning with JP (IY)); a byte holding a boundary is merged from
; the patterns on either side. A boundary at x = 255 is an edge clamped at the
; right border: its mask (MASKX) is 0, the span left of it fills the row.

; The fill chain and the pattern table lie in one page (IXH and H select it,
; see the end of this file)
COMPOSE_PAGE    EQU ComposeChain / 256 * 256
CP_FILL_END     EQU ComposeChainEnd % 256       ; the JP (IY) after the chain
CP_PATVERGE     EQU cpPatterns % 256    ; verge patterns [colour * 2 + parity]
CP_PATGRASS     EQU CP_PATVERGE + 8     ; grass patterns [parity]
                                        ; (road: PAT_ROAD, both parities)

; Spans: the current span (pattern B) ends at pixel A, the next one has
; pattern C; D = MASKX page. The first span starts at the row start (HL),
; the others after the byte merged last (HL stays on it): the whole bytes
; before the boundary byte are filled, then the boundary byte is merged (or
; the byte merged last is merged again when the boundary lies in it). A
; boundary at a byte start merges the whole byte (mask $FF), which is the
; same as the next span filling it.

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
        cp VIEW_ROWS - HIDDEN_LINES     ; (the bottom rows are behind the
        jr c, @c0                       ; cockpit)
        ld a, VIEW_ROWS - HIDDEN_LINES
@c0:
        ld c, a                         ; C = first ground row
        ld a, (skyClean)                ; start at min(skyClean, sky rows)
        cp c
        jr c, @c1
        ld a, c
@c1:
        ld b, a
        ld l, a                         ; HL = VIEW_BUF + 32 * row
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, VIEW_BUF
        add hl, de
        ld a, c
        sub b                           ; sky rows to write
        jr z, @ground
        exx
        ld b, a                         ; B' = sky rows to write
        exx
        ld b, PAT_SKY
@sky:
        ld ixl, ComposeChain % 256
        ld iy, @s1
        jp (ix)
@s1:
        ld a, l
        or a
        jr nz, @s2
        inc h                           ; the next page
@s2:
        exx
        dec b
        exx
        jr nz, @sky
@ground:
        ld a, c
        cp VIEW_ROWS - HIDDEN_LINES
        ret nc                          ; all sky
        cpl
        add a, VIEW_ROWS                ; track line = 79 - row
        exx
        ld b, a                         ; B' = track line
        exx
        jr @row
@b2r:
        ld a, e
        or a
        jr z, @roadRow                  ; and b1 = 0: road across the row
        ld a, 255
        jr @b2x
@roadRow:
        ld a, (@road + 1)
        ld b, a
@grassRow:
        pop hl                          ; 32 bytes of grass (B), or road
        ld ixl, ComposeChain % 256
        ld iy, @next
        jp (ix)
@row:                                   ; HL = row start, B' = its track line
        exx
        ld a, b
        exx
        push hl
        ld c, a                         ; C = track line
        and 1                           ; parity -> patterns
        add a, CP_PATVERGE - 2
        ld e, a                         ; E = verge patterns - 2 + parity
        add a, CP_PATGRASS - CP_PATVERGE + 2
        ld l, a
        ld h, COMPOSE_PAGE / 256
        ld a, (hl)
        ld (@grass + 1), a
        ld b, a                         ; B = grass
        ld a, c
        add a, EDGE_COLR % 256
        ld l, a
        ld h, EDGE_COLR / 256
        ld a, (hl)                      ; right verge colour ($FF: no road)
        inc a
        jr z, @grassRow
        add a, a
        add a, e
        ld l, a
        ld h, COMPOSE_PAGE / 256
        ld a, (hl)
        ld (@vr + 1), a
        ld a, c
        add a, EDGE_COLL % 256
        ld l, a
        ld h, EDGE_COLL / 256
        ld a, (hl)                      ; left verge colour
        inc a
        jr z, @grassRow
        add a, a
        add a, e
        ld l, a
        ld h, COMPOSE_PAGE / 256
        ld a, (hl)
        ld (@vl + 1), a
        ; boundaries b0 .. b3
        ld l, c
        ld h, EDGE_LOUT / 256
        ld d, (hl)                      ; D = b0
        ld a, c
        add a, EDGE_LIN - EDGE_LOUT
        ld l, a
        ld e, (hl)                      ; E = b1
        add a, EDGE_RIN - EDGE_LIN
        ld l, a
        ld a, (hl)                      ; A = b2
        inc a
        jr z, @b2r                      ; b2 = 255 (clamped at the right)
        dec a
@b2x:
        ld h, EDGE_ROUT / 256
        ld l, c
        ld c, (hl)                      ; C = b3
        cp e                            ; b2 = max(b1, b2)
        jr nc, @o1
        ld a, e
@o1:
        ld (@b2 + 1), a
        cp c                            ; b3 = max(b2, b3)
        jr nc, @o2
        ld a, c
@o2:
        ld (@b3 + 1), a
        ld a, e
        ld (@b1 + 1), a
        cp d                            ; b0 = min(b0, b1)
        jr c, @o3
        ld a, d
@o3:
        pop hl
        ld d, MASKX / 256
@vl:
        ld c, 0                         ; patched: left verge pattern
        ld e, a                         ; SPAN 0: grass | left verge
        rrca
        rrca
        rrca
        and $1F                         ; whole bytes before the boundary
        jr z, @m0
        add a, a                        ; fill them: enter the chain at
        cpl                             ; CP_FILL_END - 2 * count
        add a, CP_FILL_END + 1
        ld ixl, a
        ld iy, @m0
        jp (ix)
@m0:
        ld a, (de)                      ; bits from the boundary on
        ld e, a
        ld a, b
        xor c
        and e
        xor b
        ld (hl), a
        ld b, c
@road:
        ld c, PAT_ROAD                  ; (tests patch it)
@b1:
        ld a, 0                         ; patched: b1
        ld e, a                         ; SPAN 1: left verge | road
        rrca
        rrca
        rrca
        xor l
        and $1F
        xor l                           ; the boundary byte (low address byte)
        sub l                           ; bytes after the one merged last
        jr z, @f1
        dec a
        jr z, @a1
        add a, a                        ; fill those before the boundary:
        cpl                             ; enter the chain at its INC L before
        add a, CP_FILL_END              ; CP_FILL_END - 2 * count
        ld ixl, a
        ld iy, @m1
        jp (ix)
@f1:
        ld b, (hl)                      ; in the byte merged last: merge again
        dec l
@a1:
        inc l
@m1:
        ld a, (de)
        ld e, a
        ld a, b
        xor c
        and e
        xor b
        ld (hl), a
        ld b, c
@vr:
        ld c, 0                         ; patched: right verge pattern
@b2:
        ld a, 0                         ; patched: b2
        ld e, a                         ; SPAN 2: road | right verge
        rrca
        rrca
        rrca
        xor l
        and $1F
        xor l
        sub l
        jr z, @f2
        dec a
        jr z, @a2
        add a, a
        cpl
        add a, CP_FILL_END
        ld ixl, a
        ld iy, @m2
        jp (ix)
@f2:
        ld b, (hl)
        dec l
@a2:
        inc l
@m2:
        ld a, (de)
        ld e, a
        ld a, b
        xor c
        and e
        xor b
        ld (hl), a
        ld b, c
@grass:
        ld c, 0                         ; patched: grass
@b3:
        ld a, 0                         ; patched: b3
        ld e, a                         ; SPAN 3: right verge | grass
        rrca
        rrca
        rrca
        xor l
        and $1F
        xor l
        sub l
        jr z, @f3
        dec a
        jr z, @a3
        add a, a
        cpl
        add a, CP_FILL_END
        ld ixl, a
        ld iy, @m3
        jp (ix)
@f3:
        ld b, (hl)
        dec l
@a3:
        inc l
@m3:
        ld a, (de)
        ld e, a
        ld a, b
        xor c
        and e
        xor b
        ld (hl), a
        ld b, c
        ld a, l                         ; grass to the end of the row
        cpl
        and $1F
        jr z, @end
        add a, a
        cpl
        add a, CP_FILL_END
        ld ixl, a
        ld iy, @next
        jp (ix)
@end:
        inc l
@next:                                  ; HL = the next row's start
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

ComposeChain:
        REPT 32
        ld (hl), b
        inc l
        ENDR
ComposeChainEnd:
        jp (iy)
cpPatterns:
        db %10101010, %01010101         ; colour 0: red (50%)
        db %11111111, %11111111         ; colour 1: black
        db %00000000, %00000000         ; colour 2: white
        db %00000000, %00000000         ; colour 3
        db %10001000, %00100010         ; grass (25%)
        ASSERT ComposeChain / 256 == ($ - 1) / 256

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
