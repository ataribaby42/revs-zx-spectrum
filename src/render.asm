; Track renderer
;
; 1. BuildEdges: the four verge edges are polylines through the verge buffer
;    entries (far to near). Each segment is stepped one track line at a time
;    and its x position stored per line, nearer segments overwriting farther
;    ones (this hides the track behind crests). The inner edges also record
;    the verge-mark colour per line.
; 2. Compose: each track line becomes one row of the view buffer:
;    grass | left verge | road | right verge | grass, or sky above the horizon.

VIEW_ROWS       EQU 80

EDGE_LOUT       EQU EDGE_PAGE1 + $00    ; x of the left edge of the left verge
EDGE_LIN        EQU EDGE_PAGE1 + $50    ; x of the right edge of the left verge
EDGE_RIN        EQU EDGE_PAGE1 + $A0    ; x of the left edge of the right verge
EDGE_ROUT       EQU EDGE_PAGE2 + $00    ; x of the right edge of the right verge
EDGE_COLL       EQU EDGE_PAGE2 + $50    ; left verge colour per line ($FF: no road)
EDGE_COLR       EQU EDGE_PAGE2 + $A0    ; right verge colour per line

XH_LO           EQU XCONV + $000        ; floor(h * 6.5), low byte
XH_HI           EQU XCONV + $100        ; high byte
XL_TAB          EQU XCONV + $200        ; floor(l * 6.5 / 256)
MASKL           EQU MASKS + $10         ; $FF << (7 - n)
MASKBIT         EQU MASKS + $08         ; $80 >> n

; Material patterns of both line parities (grass and verges: cpPatterns in
; compose.asm)
PAT_SKY         EQU $00
PAT_ROAD        EQU $FF

; ---------------------------------------------------------------------------
; BuildEdges

BuildEdges:
        ; COLL and COLR (contiguous) = $FF, written downwards with PUSH. An
        ; interrupt meanwhile pushes onto EDGE_ROUT below, which is rebuilt
        ; afterwards.
        ld (beSP), sp
        ld sp, EDGE_COLL + 2 * VIEW_ROWS
        ld hl, $FFFF
        ld b, VIEW_ROWS / 8
@f1:
        REPT 8
        push hl
        ENDR
        djnz @f1
        ld sp, (beSP)
        ld a, $FF                       ; the tail modes of this frame are not
        ld (tailModes), a               ; known yet (RasterTail: TailModes)
        ; right inner edge (with colours)
        ld a, (horizonListIndex)
        ld b, a
        ld a, (segmentListRight)
        ld c, a
        ld hl, EDGE_RIN
        ld de, EDGE_COLR
        xor a
        call RasterEdge
        ld hl, EDGE_RIN + HIDDEN_LINES
        ld de, EDGE_ROUT + HIDDEN_LINES
        call CopyEdge
        ld a, (horizonListIndex)        ; right outer edge
        cp 9
        jr nc, @r1
        ld a, 9
@r1:
        ld b, a
        ld a, (segmentListRight)
        ld c, a
        ld hl, EDGE_ROUT
        ld de, 0
        ld a, 16
        call RasterEdge
        ; left inner edge
        ld a, (horizonListIndex)
        add a, 40
        ld b, a
        ld a, (segmentListPointer)
        ld c, a
        ld hl, EDGE_LIN
        ld de, EDGE_COLL
        xor a
        call RasterEdge
        ld hl, EDGE_LIN + HIDDEN_LINES
        ld de, EDGE_LOUT + HIDDEN_LINES
        call CopyEdge
        ld a, (horizonListIndex)        ; left outer edge
        add a, 40
        cp 49
        jr nc, @l1
        ld a, 49
@l1:
        ld b, a
        ld a, (segmentListPointer)
        ld c, a
        ld hl, EDGE_LOUT
        ld de, 0
        ld a, 16
        jp RasterEdge


beSP:           dw 0

; TailModes: how an edge whose last part is flat or rising continues down
; (RasterTail, which calls this for the first such edge of a frame):
; tailModes = right, left. On the track (the last points of the two verges
; lie on opposite sides of the camera, 90 degrees or more apart) both at the
; screen side of their verge (+ TAIL_TRACK); off the track only the farther
; verge (the higher last point), if that point is in front of the camera;
; the nearer one ends (grass below). BuildEdges sets tailModes to $FF (not
; known yet). Preserves BC, HL.
TailModes:
        push bc
        push hl
        ld a, (segmentListRight)
        dec a
        ld l, a
        ld h, VERGE_XHI / 256
        ld b, (hl)                      ; B = right verge: yaw of its last point
        ld h, VERGE_Y / 256
        ld c, (hl)                      ; C = its line
        ld a, (segmentListPointer)
        dec a
        ld l, a
        ld e, (hl)                      ; E = left verge: line of its last point
        ld h, VERGE_XHI / 256
        ld d, (hl)                      ; D = its yaw
        ld a, b
        sub d
        jp p, @t1
        neg
@t1:
        cp 64
        ld hl, (TAIL_LEFT + TAIL_TRACK) * 256 + TAIL_RIGHT + TAIL_TRACK
        jr nc, @t3                      ; on the track: both
        ld hl, TAIL_LEFT * 256 + TAIL_RIGHT
        ld a, c                         ; off: which last point is lower
        xor $80                         ; (signed lines)
        ld c, a
        ld a, e
        xor $80
        cp c
        ld a, d
        jr nc, @t2
        ld h, 0                         ; the left verge is nearer
        ld a, b
        jr @t2a
@t2:
        ld l, 0                         ; the right verge is nearer
@t2a:
        add a, 64                       ; the farther one's last point
        jp p, @t3                       ; behind the camera: no tail either
        ld hl, 0
@t3:
        ld (tailModes), hl
        pop hl
        pop bc
        ret

tailModes:      dw 0                    ; RasterTail's tail mode: right, left

; CopyEdge: an edge table from HL to DE, the lines from HIDDEN_LINES up
; (the lines below are behind the cockpit: never drawn nor read)
CopyEdge:
        REPT VIEW_ROWS - HIDDEN_LINES
        ldi
        ENDR
        ret

; ---------------------------------------------------------------------------
; CheckSurfaces: is there grass under the front tyres? The original reads
; two screen bytes beside the dashboard (C64: track line 10, multicolour
; pixels 28-31 and 128-131); a side is on grass when the whole byte is
; grass. Here the same span is checked in the edge tables of line 10
; (SURF_LEFT / SURF_RIGHT, from the horizontal scale) exactly as Compose
; draws the line: all grass when either side has no road on it, else grass
; left of b0 and from b3 on. Sets leftSurface / rightSurface to $FF for
; grass.

SURFACE_LINE    EQU 10
        ASSERT SURFACE_LINE >= HIDDEN_LINES     ; (lines below are not rasterised)
        INCLUDE "scale.asm"

CheckSurfaces:
        ld a, (EDGE_COLL + SURFACE_LINE)
        ld hl, EDGE_COLR + SURFACE_LINE
        or (hl)                         ; (colours 0-3, $FF: no road)
        inc a
        jr z, @grass2                   ; a side without road: all grass
        ld hl, EDGE_LOUT + SURFACE_LINE ; b0 = min(LOUT, LIN)
        ld a, (EDGE_LIN + SURFACE_LINE)
        ld d, a
        cp (hl)
        jr c, @s1
        ld a, (hl)
@s1:
        ld b, a
        ld a, (EDGE_RIN + SURFACE_LINE) ; b3 = max(LIN, RIN, ROUT)
        cp d
        jr nc, @s2
        ld a, d
@s2:
        ld hl, EDGE_ROUT + SURFACE_LINE
        cp (hl)
        jr nc, @s3
        ld a, (hl)
@s3:
        ld c, a
        cp b
        jr z, @grass2                   ; b0 = b3: no verge or road drawn
        ld de, SURF_LEFT                ; left span
        call @span
        ld (leftSurface), a
        ld de, SURF_RIGHT               ; right span
        call @span
        ld (rightSurface), a
        ret
@grass2:
        ld a, $FF
        ld (leftSurface), a
        ld (rightSurface), a
        ret
; .span: D..E all grass (E < b0 or D >= b3) -> A = $FF, else 0
@span:
        ld a, e
        cp b
        jr c, @yes
        ld a, d
        cp c
        jr nc, @yes
        xor a
        ret
@yes:
        ld a, $FF
        ret
