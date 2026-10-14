; Object drawing: cars, road signs, corner markers (ZX renderer)
;
; Objects are the original 2D part definitions (tools/gen_objects.py): each
; part is a rectangle given by scaffold measurements, drawn as a left edge, a
; fill and a right edge (four-edge parts have two more edges and fills). The
; scaffold is scaled as on the BBC (sums of scaleUp >> n), vertically in track
; lines (one view row each) and horizontally by 13/16: the scaffold counts
; pixels of the 320-wide screen, half an xPixelCoord unit, and the track
; renderer uses 6.5 pixels per yaw unit (4 xPixelCoord units).
;
; Logical colours (objectPalette entries) are pattern numbers: 0 black,
; 1 red, 2 white, 3 green, drawn as dither patterns in the monochrome view.
;
; Each part is built as one pixel row in two line buffers (even and odd track
; lines) and then copied into the rows of the view buffer it covers.

COL_BLACK       EQU 0
COL_RED         EQU 1
COL_WHITE       EQU 2
COL_GREEN       EQU 3

LOD_CAR         EQU 14                  ; standard cars smaller than this are
                                        ; drawn as distant cars (one part)

; Work page (OBJ_LINE, page-aligned)
OBJ_LINE_E      EQU OBJ_LINE + $00      ; line buffer, even track lines (32)
OBJ_LINE_O      EQU OBJ_LINE + $20      ; line buffer, odd track lines (32)
OBJ_XL          EQU OBJ_LINE + $40      ; x of scaffold index 0-15, low bytes
OBJ_XH          EQU OBJ_LINE + $50      ; high bytes
OBJ_Y           EQU OBJ_LINE + $60      ; track line of scaffold index 0-15
OBJ_PAT         EQU OBJ_LINE + $70      ; patterns of logical colours 0-3 [even, odd]
EDGEMASK        EQU OBJ_LINE + $78      ; masks of two pixels from x & 7 (main.asm)
RMASK           EQU OBJ_LINE + $80      ; $FF >> n: pixels n..7 (main.asm)
LMASK           EQU OBJ_LINE + $88      ; $FF << (7 - n): pixels 0..n (main.asm)

        ALIGN 8
objPatterns:                            ; [colour][track line parity]
        db %11111111, %11111111         ; black
        db %10101010, %01010101         ; red
        db %00000000, %00000000         ; white
        db %10001000, %00100010         ; green

colourPalette:  db COL_BLACK, COL_RED, COL_WHITE, COL_GREEN

objX:           dw 0                    ; screen x of the object centre (signed)
objNumber:      db 0
partIndex:      db 0
leftHalf:       db 0                    ; $FF if the object centre is left of
                                        ; the screen centre
partXR:         dw 0
partLeft:       db 0
partRight:      db 0
fillRow0:       db 0
fillRows:       db 0


; ---------------------------------------------------------------------------
; DrawCarOrSign: C = object number (0-23). Draws it if it is visible and
; within the field of view.

DrawCarOrSign:
        ld a, c
        add a, OBJ_STATUS % 256
        ld l, a
        ld h, OBJ_STATUS / 256
        ld a, (hl)
        or a
        ret m
        and $0F
        ld (objectType), a
        ld a, l
        add a, 24
        ld l, a
        ld e, (hl)                      ; objYawAngleLo
        add a, 24
        ld l, a
        ld d, (hl)                      ; objYawAngleHi
        ld hl, (playerYawAngleLo)
        ex de, hl
        or a
        sbc hl, de                      ; yaw relative to the player
        ld a, h
        add a, $20                      ; visible if -$20 <= yaw < $20
        cp $40
        ret nc
        ld e, l
        ld l, h                         ; x = 128 + yaw * 6.5
        ld h, XH_LO / 256
        ld a, (hl)
        inc h
        ld b, (hl)
        ld h, XL_TAB / 256
        ld l, e
        add a, (hl)
        ld l, a
        ld a, b
        adc a, 0
        ld h, a
        ld de, 128
        add hl, de
        ld (objX), hl
        ld a, c
        add a, OBJ_PITCH % 256
        ld l, a
        ld h, OBJ_PITCH / 256
        ld a, (hl)
        ld (yPixelCoord), a
        ld a, l
        add a, 24
        ld l, a                         ; objectSize
        ld a, (hl)
        ld (scaleUp), a
        ; fall through

; DrawObject: draw object C of type objectType at (objX, yPixelCoord) with
; size scaleUp
DrawObject:
        ld a, c
        ld (objNumber), a
        ld hl, colourPalette
        ld de, objectPalette
        ld bc, 4
        ldir
        ld a, COL_WHITE                 ; (DrawCornerMarkers changes colour 2)
        ld (colourPalette + 2), a
        ld a, (objNumber)
        cp 23
        jr z, @d3
        cp 20
        jr c, @d2
        ld a, (positionAhead)           ; four-object car: the car ahead
        add a, DRIVERS_IN_ORDER % 256
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (hl)
@d2:
        and 3                           ; car colour = driver number mod 4
        ld e, a
        ld d, 0
        ld hl, colourPalette
        add hl, de
        ld a, (hl)
        ld (objectPalette + 1), a
@d3:
        ld b, 0                         ; beyond the horizon: clip the object
        ld a, (scaleUp)                 ; at the horizon line
        ld hl, horizonTrackWidth
        cp (hl)
        jr nc, @d4
@tcCutoff:                              ; (track code: ld a, n / nop, n set by
        ld a, (horizonLine)             ; the hooks: C64 $1B0B-$1B0C)
        ld b, a
@d4:
        ld a, b
        ld (lowestTrackLine), a
        ld a, (scaleUp)
        or a
        ret z
        ld hl, objectPalette            ; patterns of the logical colours
        ld de, OBJ_PAT
        ld b, objPatterns / 256
        REPT 4
        ld a, (hl)
        inc hl
        add a, a
        add a, objPatterns % 256
        ld c, a
        ld a, (bc)
        ld (de), a
        inc e
        inc c
        ld a, (bc)
        ld (de), a
        inc e
        ENDR
        ld hl, (objX)                   ; leftHalf = objX < 128
        ld a, h
        or a
        ld a, $FF
        jp m, @lh
        jr nz, @rh
        bit 7, l
        jr z, @lh
@rh:
        xor a
@lh:
        ld (leftHalf), a
        ld a, (objectType)
        cp 4
        jr nz, @d5
        ld a, (scaleUp)                 ; small standard car: draw the
        cp LOD_CAR                      ; distant car instead
        ld a, 4
        jr nc, @d6
        inc a
        jr @d6
@d5:
        cp 10
        jr c, @d6
        ld a, 9                         ; signs: blank sign first
@d6:
        ld (thisObjectType), a
        call ScaleObject
        ret c
        ld a, (thisObjectType)
        call DrawObjectParts
        ld a, (thisObjectType)
        cp 9
        ret nz
        ld a, (directionFacing)         ; sign contents (front side only)
        or a
        ret m
        ld a, (objectType)
        cp 10
        ret c
        jr @d6

; ---------------------------------------------------------------------------
; ScaleObject: A = object type. Scales its scaffold by scaleUp as the BBC
; does (sums of scaleUp >> n, with two extra bits of precision for small
; objects) into OBJ_Y (yPixelCoord +- s) and OBJ_XL/OBJ_XH (objX +- h, h =
; h13Tab[s]). Each measurement is a pair of scaleTerms entries
; (scafTermTab). Returns carry set if the object is too big to draw.
; Uses IX.

ScaleObject:
        ld e, a
        ld d, 0
        ld hl, scafIndexTab
        add hl, de
        ld a, (hl)                      ; first measurement
        inc hl
        ld b, (hl)
        ld e, a
        ld a, b
        sub e
        ld b, a                         ; B = number of measurements
        ld hl, scafTermTab
        add hl, de
        add hl, de
        push hl
        ld hl, @down                    ; scaleDown: patch the sum's tail
        ld a, (scaleUp)
        cp 64
        jr nc, @s0
        ld (hl), $CB                    ; srl a / srl a / adc a, 0
        inc hl
        ld (hl), $3F
        inc hl
        ld (hl), $CB
        inc hl
        ld (hl), $3F
        inc hl
        ld (hl), $CE
        inc hl
        ld (hl), 0
        add a, a                        ; two more bits of precision
        add a, a
        jr @s1
@s0:
        ld (hl), $FA                    ; jp m, .big / nop x 3
        inc hl
        ld (hl), @big % 256
        inc hl
        ld (hl), @big / 256
        inc hl
        xor a
        ld (hl), a
        inc hl
        ld (hl), a
        inc hl
        ld (hl), a
        ld a, (scaleUp)
@s1:
        ld hl, scaleTerms               ; scaleTerms + n = scaleUp >> n
        ld (hl), a
        REPT 5
        srl a
        inc l
        ld (hl), a
        ENDR
        inc l
        ld (hl), 0                      ; + 6: nothing
        ld l, scaleTerms % 256 + 1
        ld a, (hl)
        inc l
        ld c, a
        add a, (hl)
        ld l, scaleTerms % 256 + 7
        ld (hl), a                      ; + 7: >> 1 + >> 2
        ld l, scaleTerms % 256 + 3
        ld a, c
        add a, (hl)
        ld l, scaleTerms % 256 + 8
        ld (hl), a                      ; + 8: >> 1 + >> 3
        ld a, (yPixelCoord)
        ld (@y1 + 1), a
        ld (@y2 + 1), a
        ld a, (objX)
        ld (@xl1 + 1), a
        ld (@xl2 + 1), a
        ld a, (objX + 1)
        ld (@xh1 + 1), a
        ld (@xh2 + 1), a
        ld ix, OBJ_XL
        pop de
@e1:
        ld a, (de)                      ; s = sum of two terms
        inc de
        ld l, a
        ld c, (hl)
        ld a, (de)
        inc de
        ld l, a
        ld a, (hl)
        add a, c
@down:
        ds 6                            ; patched: / 4 rounded, or s >= 128:
                                        ; too big
        ld l, a                         ; s < 128
        ld c, (hl)                      ; C = h = h13Tab[s]
@y1:
        ld a, 0                         ; patched: yPixelCoord
        add a, l
        ld (ix + OBJ_Y - OBJ_XL), a     ; OBJ_Y + i = y + s
@y2:
        ld a, 0                         ; patched: yPixelCoord
        sub l
        ld (ix + OBJ_Y + 8 - OBJ_XL), a ; OBJ_Y + 8 + i = y - s
@xl1:
        ld a, 0                         ; patched: objX
        add a, c
        ld (ix + 0), a                  ; OBJ_XL/XH + i = objX + h
@xh1:
        ld a, 0
        adc a, 0
        ld (ix + OBJ_XH - OBJ_XL), a
@xl2:
        ld a, 0
        sub c
        ld (ix + 8), a                  ; OBJ_XL/XH + 8 + i = objX - h
@xh2:
        ld a, 0
        sbc a, 0
        ld (ix + OBJ_XH + 8 - OBJ_XL), a
        inc ixl
        djnz @e1
        or a
        ret
@big:
        scf
        ret

        INCLUDE "objterms.asm"

; ---------------------------------------------------------------------------
; DrawObjectParts: A = object type. Each part is a 5-byte objPartTab entry:
; colour, top, bottom, left, right (scaffold indices); a four-edge part
; (colour bit 7) is followed by an entry holding colour 3, the third edge, -,
; the second edge and colour 2. Colour bit 6 marks the last part.

DrawObjectParts:
        ld e, a
        ld d, 0
        ld hl, objPartOffTab
        add hl, de
        ld e, (hl)
        ld hl, objPartTab
        add hl, de
@part:
        ld (partPtr), hl
        ld d, OBJ_LINE / 256
        ld a, (hl)                      ; colour
        ld (partColour), a
        inc hl
        ld a, (hl)                      ; top line
        inc hl
        add a, OBJ_Y % 256
        ld e, a
        ld a, (de)
        or a
        jp m, @skip                     ; above the view
        cp 80
        jr c, @p1
        ld a, 79
@p1:
        ld b, a
        ld a, (hl)                      ; bottom line
        inc hl
        add a, OBJ_Y % 256
        ld e, a
        ld a, (de)
        ld c, a
        or a
        jp m, @low
        ld a, (lowestTrackLine)
        cp c
        jr c, @p2
        jr z, @p2
@low:
        ld a, (lowestTrackLine)
        ld c, a
@p2:
        ld a, c                         ; lines (C, B] are drawn
        cp b
        jp nc, @skip
        ld a, b
        sub c
        ld (fillRows), a
        ld a, 79
        sub b
        ld (fillRow0), a
        ld a, (hl)                      ; left edge
        inc hl
        add a, OBJ_XL % 256
        ld e, a
        ld a, (de)
        ld c, a
        set 4, e
        ld a, (de)
        ld b, a                         ; BC = left x
        ld a, (hl)                      ; right edge: its pixel pair ends
        add a, OBJ_XL % 256               ; at x + 1
        ld e, a
        ld a, (de)
        ld l, a
        set 4, e
        ld a, (de)
        ld h, a
        inc hl
        ld (partXR), hl
        ld (edgeX), bc
        bit 7, h
        jp nz, @skip                    ; right edge left of the screen
        ld a, h
        or a
        ld a, l
        jr z, @xr1
        ld a, 255
@xr1:
        ld (partRight), a
        ld e, a
        ld a, b
        or a
        jp m, @xl0
        jp nz, @skip                    ; left edge right of the screen
        ld a, c
        jr @xl1
@xl0:
        xor a
@xl1:
        ld (partLeft), a
        ld d, a
        ld a, e
        cp d
        jp c, @skip                     ; (degenerate)
        ld a, (partColour)
        or a
        jp m, @four
        ; two edges: the fill patterns into the whole line bytes of the part
        ; (Blit masks the pixels outside it), then the edges if they differ
        and 3
        ld c, a                         ; C = fill colour
        add a, a
        add a, OBJ_PAT % 256
        ld l, a
        ld h, OBJ_LINE / 256
        ld a, d                         ; (D = partLeft, E = partRight)
        ld d, (hl)
        inc l
        ld b, (hl)                      ; D, B = fill patterns (even, odd line)
        rrca
        rrca
        rrca
        and $1F
        ld l, a                         ; L = first byte
        ld a, e
        rrca
        rrca
        rrca
        and $1F
        sub l
        inc a
        ld e, a                         ; E = bytes
@fl:
        ld (hl), d
        set 5, l
        ld (hl), b
        res 5, l
        inc l
        dec e
        jr nz, @fl
        ld a, (partColour)
        ld b, a
        rrca
        rrca
        and 3                           ; the edge colour
        cp c
        jr z, @t4                       ; the fill colour: no edges
        ld c, a
        bit 4, b
        jr z, @t1                       ; both edges
        ld a, (leftHalf)                ; one edge (the fill colour on the
        or a                            ; outside of the object)
        jr nz, @t2                      ; left half: the right edge
@t1:
        push bc
        ld a, c
        ld hl, (edgeX)
        call PlotEdge
        pop bc
        bit 4, b
        jr nz, @t4                      ; right half: the left edge only
@t2:
        ld a, c
        ld hl, (partXR)
        dec hl
        call PlotEdge
@t4:
        call Blit
        ld a, (partColour)
        and $40
        ret nz                          ; last part
        ld hl, (partPtr)
        ld de, 5
        add hl, de
        jp @part

@four:                                  ; four edges: second entry
        ld hl, (partPtr)
        ld de, 5
        add hl, de
        ld (partPtr), hl
        ld d, OBJ_LINE / 256
        ld a, (hl)
        ld (colour3), a
        inc hl
        ld a, (hl)                      ; third edge
        inc hl
        inc hl
        add a, OBJ_XL % 256
        ld e, a
        ld a, (de)
        ld c, a
        set 4, e
        ld a, (de)
        ld b, a
        ld (edge3), bc
        ld a, (hl)                      ; second edge
        inc hl
        add a, OBJ_XL % 256
        ld e, a
        ld a, (de)
        ld c, a
        set 4, e
        ld a, (de)
        ld b, a
        ld (edge2), bc
        ld a, (hl)
        ld (colour2), a
        ld a, (partColour)              ; fills
        and 3
        ld (fillColour), a
        ld de, (edgeX)
        ld hl, (edge2)
        dec hl
        call Run
        ld a, (colour2)
        and 3
        ld (fillColour), a
        ld de, (edge2)
        ld hl, (edge3)
        dec hl
        call Run
        ld a, (colour3)
        and 3
        ld (fillColour), a
        ld de, (edge3)
        ld hl, (partXR)
        call Run
        ld a, (partColour)              ; edges
        rrca
        rrca
        and 3
        ld hl, (edgeX)
        call PlotEdge
        ld a, (colour2)
        rrca
        rrca
        and 3
        ld hl, (edge2)
        call PlotEdge
        ld a, (colour3)
        rrca
        rrca
        and 3
        ld hl, (edge3)
        call PlotEdge
        ld a, (colour3)
        rrca
        rrca
        and 3
        ld hl, (partXR)
        dec hl
        call PlotEdge
        call Blit
        ld a, (colour3)
        and $40
        ret nz
        ld hl, (partPtr)
        ld de, 5
        add hl, de
        jp @part

@skip:                                  ; part not visible: skip its data
        ld hl, (partPtr)
        ld de, 5
        ld a, (hl)
        or a
        jp p, @sk1
        and $40                         ; four edges: the second entry
        ret nz
        add hl, de
        ld a, (hl)
@sk1:
        and $40
        ret nz
        add hl, de
        jp @part

partPtr:        dw 0
partColour:     db 0
colour2:        db 0
colour3:        db 0
edgeX:          dw 0
edge2:          dw 0
edge3:          dw 0
fillColour:     db 0

; ---------------------------------------------------------------------------
; Line buffers

; PlotEdge: an edge, pixels HL and HL + 1 (signed, clipped to 0-255) in
; logical colour A (the C64 draws edges one multicolour pixel wide)
PlotEdge:
        ex de, hl                       ; DE = x
        ld h, OBJ_LINE / 256
        add a, a
        add a, OBJ_PAT % 256
        ld l, a
        ld b, (hl)                      ; B = even line pattern
        inc l
        ld c, (hl)                      ; C = odd line pattern
        ld a, d
        or a
        jr nz, @clip
        ld a, e
        and 7
        or EDGEMASK % 256
        ld l, a
        ld a, e
        ld e, (hl)                      ; E = mask of the two pixels
        rrca
        rrca
        rrca
        and $1F
        ld l, a                         ; L = byte
        ld a, (hl)
        xor b
        and e
        xor (hl)
        ld (hl), a
        set 5, l
        ld a, (hl)
        xor c
        and e
        xor (hl)
        ld (hl), a
        dec e                           ; x & 7 = 7: second pixel in the next byte
        ret nz
        res 5, l
        inc l
        bit 5, l
        ret nz                          ; (x = 255)
        ld e, $80
        jp Run@merge
@clip:
        inc a
        ret nz                          ; x < -256 or x > 255
        ld a, e
        inc a
        ret nz                          ; x < -1
        ld l, a                         ; x = -1: pixel 0
        ld e, $80
        jp Run@merge

; Run: pixels DE..HL (signed, inclusive, clipped to 0-255) in logical colour
; fillColour
Run:
        bit 7, h
        ret nz                          ; ends left of the screen
        ld a, d
        or a
        jp p, @r1
        ld e, 0
        jr @r2
@r1:
        ret nz                          ; starts right of the screen
@r2:
        ld a, h
        or a
        jr z, @r3
        ld l, 255
@r3:
        ld a, l
        cp e
        ret c                           ; empty
        ld d, a                         ; E = x0, D = x1
        ld h, OBJ_LINE / 256
        ld a, (fillColour)
        add a, a
        add a, OBJ_PAT % 256
        ld l, a
        ld b, (hl)                      ; B = even line pattern
        inc l
        ld c, (hl)                      ; C = odd line pattern
        ld a, d
        and 7
        or LMASK % 256
        ld l, a
        ld a, (hl)
        ex af, af'                      ; A' = last byte mask
        ld a, e
        and 7
        or RMASK % 256
        ld l, a
        ld a, d
        ld d, (hl)                      ; D = first byte mask
        rrca
        rrca
        rrca
        and $1F
        ld l, a                         ; last byte
        ld a, e
        rrca
        rrca
        rrca
        and $1F
        ld e, a                         ; first byte
        ld a, l
        sub e
        ld l, e                         ; HL = first byte
        jr nz, @multi
        ex af, af'                      ; single byte: both masks
        and d
        ld e, a
        jr @merge
@multi:
        ld e, d                         ; first byte mask
        ld d, a                         ; D = bytes after the first
        call @merge
        inc l
        dec d
        jr z, @last
@mid:
        ld (hl), b
        set 5, l
        ld (hl), c
        res 5, l
        inc l
        dec d
        jr nz, @mid
@last:
        ex af, af'
        ld e, a
@merge:                                 ; both lines: (L) = merge with B/C, mask E
        ld a, (hl)
        xor b
        and e
        xor (hl)
        ld (hl), a
        set 5, l
        ld a, (hl)
        xor c
        and e
        xor (hl)
        ld (hl), a
        res 5, l
        ret

; ---------------------------------------------------------------------------
; Blit: copy the line buffers over partLeft..partRight into view rows
; fillRow0 .. fillRow0 + fillRows - 1 (even rows show odd track lines, the
; OBJ_LINE_O buffer). Parts one or two bytes wide merge pre-masked source
; bytes patched into their loops; wider parts copy the middle bytes with LDI.

Blit:
        ld a, (fillRow0)                ; note the highest row with objects
        ld hl, objTopRow
        cp (hl)
        jr nc, @top
        ld (hl), a
@top:
        ld c, a
        rrca
        rrca
        rrca
        ld b, a
        and $1F
        add a, VIEW_BUF / 256
        ld d, a
        ld a, b
        and $E0
        ld e, a                         ; DE = VIEW_BUF + 32 * row
        ld a, c                         ; L = 32 if the row is even
        cpl
        and 1
        rrca
        rrca
        rrca
        ld l, a
        ld h, OBJ_LINE / 256
        ld a, (partLeft)
        ld c, a
        rrca
        rrca
        rrca
        and $1F
        ld b, a                         ; B = first byte
        add a, e
        ld e, a                         ; DE = first destination byte
        ld a, l
        or b
        ld l, a                         ; HL = first source byte
        ld a, c
        and 7
        ld c, a                         ; C = first pixel in its byte
        ld a, (partRight)
        rrca
        rrca
        rrca
        and $1F
        sub b                           ; bytes after the first
        jr z, @one
        dec a
        jp nz, @wide

        ; two bytes: masks and sources of both row parities patched
        push de
        ld d, MASKS / 256
        ld e, c
        ld a, (de)                      ; first byte mask
        ld c, a
        cpl
        ld (@t1 + 1), a
        ld (@t3 + 1), a
        ld a, (partRight)
        and 7
        add a, MASKL % 256
        ld e, a
        ld a, (de)                      ; second byte mask
        ld b, a
        cpl
        ld (@t2 + 1), a
        ld (@t4 + 1), a
        ld a, (hl)
        and c
        ld (@s1 + 1), a
        inc l
        ld a, (hl)
        and b
        ld (@s2 + 1), a
        ld a, l
        xor 32
        ld l, a
        ld a, (hl)
        and b
        ld (@s4 + 1), a
        dec l
        ld a, (hl)
        and c
        ld (@s3 + 1), a
        pop hl
        ld de, 31
        ld a, (fillRows)
        ld b, a
@tl:
        ld a, (hl)
@t1:
        and 0
@s1:
        or 0
        ld (hl), a
        inc l
        ld a, (hl)
@t2:
        and 0
@s2:
        or 0
        ld (hl), a
        add hl, de
        dec b
        ret z
        ld a, (hl)
@t3:
        and 0
@s3:
        or 0
        ld (hl), a
        inc l
        ld a, (hl)
@t4:
        and 0
@s4:
        or 0
        ld (hl), a
        add hl, de
        djnz @tl
        ret

@one:                                   ; one byte: sources in B and C
        push de
        ld d, MASKS / 256
        ld e, c
        ld a, (de)
        ld c, a
        ld a, (partRight)
        and 7
        add a, MASKL % 256
        ld e, a
        ld a, (de)
        and c                           ; C = mask
        ld c, a
        cpl
        ld (@o1 + 1), a
        ld (@o2 + 1), a
        ld a, (hl)
        and c
        ld b, a
        ld a, l
        xor 32
        ld l, a
        ld a, (hl)
        and c
        ld c, a
        pop hl
        ld de, 32
        ld a, (fillRows)
        ld ixl, a
@ol:
        ld a, (hl)
@o1:
        and 0
        or b
        ld (hl), a
        add hl, de
        dec ixl
        ret z
        ld a, (hl)
@o2:
        and 0
        or c
        ld (hl), a
        add hl, de
        dec ixl
        jr nz, @ol
        ret

@wide:                                  ; A = n - 1 >= 1 middle bytes
        ld b, a
        inc a
        ld (@subN + 1), a
        cpl
        add a, 33
        ld (@addN + 1), a               ; next row: 32 - n
        ld a, b
        add a, a
        cpl
        add a, 0 + (LdiChainEnd + 1) % 256    ; entry = LdiChainEnd - 2 * (n - 1)
        ld (@chain + 1), a
        ld a, 0 + (LdiChainEnd + 1) / 256
        adc a, $FF
        ld (@chain + 2), a
        push hl
        ld h, MASKS / 256
        ld l, c
        ld a, (hl)
        ld (@m0 + 1), a
        ld a, (partRight)
        and 7
        add a, MASKL % 256
        ld l, a
        ld a, (hl)
        ld (@m1 + 1), a
        pop hl
        ld a, (fillRows)
        ld ixl, a
@wl:
        ld a, (de)                      ; first byte
        xor (hl)
@m0:
        and 0                           ; patched
        ex de, hl
        xor (hl)
        ld (hl), a
        ex de, hl
        inc l
        inc e
@chain:
        call 0                          ; patched: n - 1 LDIs
        ld a, (de)                      ; last byte
        xor (hl)
@m1:
        and 0                           ; patched
        ex de, hl
        xor (hl)
        ld (hl), a
        ex de, hl
        ld a, l                         ; source: other line, first byte
@subN:
        sub 0                           ; patched: n
        xor 32
        ld l, a
        ld a, e
@addN:
        add a, 0                        ; patched: 32 - n
        ld e, a
        jr nc, @w1
        inc d
@w1:
        dec ixl
        jr nz, @wl
        ret

LdiChain:
        REPT 31
        ldi
        ENDR
LdiChainEnd:
        ret

; DrawCornerMarkers: draw the markersToDraw corner markers found by
; GetTrackAndMarkers (red when bit 5 of markerData is set, else white)

DrawCornerMarkers:
        xor a
@c1:
        ld hl, markersToDraw
        cp (hl)
        jr z, @c7
        ld (markerNumber), a
        ld e, a
        ld d, 0
        ld hl, markerListIndex
        add hl, de
        ld c, (hl)                      ; C = verge entry
        ld hl, markerData
        add hl, de
        bit 5, (hl)
        jr z, @c2
        ld a, COL_RED
        ld (colourPalette + 2), a
@c2:
        ld hl, xMarkerHi                ; (U T) = xMarker * 2
        add hl, de
        ld a, (hl)
        ld hl, xMarkerLo
        add hl, de
        ld l, (hl)
        ld h, a
        add hl, hl
        ld (T), hl
        ld b, VERGE_XLO / 256            ; (A V) = verge x + (U T)
        ld a, (bc)
        add a, l
        ld (V), a
        ld e, a
        inc b
        ld a, (bc)
        adc a, h
        ld d, a
        add a, 24                       ; visible if -24 <= A < 24
        cp 48
        jr nc, @c6
        ld h, XH_LO / 256                ; x = 128 + yaw * 6.5
        ld l, d
        ld a, (hl)
        inc h
        ld b, (hl)
        ld h, XL_TAB / 256
        ld l, e
        add a, (hl)
        ld l, a
        ld a, b
        adc a, 0
        ld h, a
        ld de, 128
        add hl, de
        ld (objX), hl
        ld b, VERGE_Y / 256
        ld a, (bc)
        ld (yPixelCoord), a
        ld hl, (T)                      ; scaleUp = |xMarker * 8| / 256
        add hl, hl
        add hl, hl
        ld (T), hl
        ld a, h
        or a
        jp p, @c5
        neg
@c5:
        ld (scaleUp), a
        ld a, 6
        ld (objectType), a
        ld c, 23                        ; (keep the palette)
        call DrawObject
@c6:
        ld a, COL_WHITE
        ld (colourPalette + 2), a
        ld a, (markerNumber)
        inc a
        jp @c1
@c7:
        xor a
        ld (markersToDraw), a
        ret
