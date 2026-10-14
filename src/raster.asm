; Edge rasteriser: steps a polyline through verge entries one track line at a
; time and stores the x position per line (see render.asm).

p0x:            dw 0            ; segment start: screen x, track line, colour
p0y:            db 0
p0c:            db 0
p1x:            dw 0            ; segment end
p1y:            db 0
p1c:            db 0
reOff:          db 0            ; 0 inner edge, 16 outer edge
reEnd:          db 0            ; end verge index (exclusive)
rsTabLo:        db 0            ; edge table address
rsTabHi:        db 0
rsCount:        db 0
; tail modes (TailModes): 0 none, TAIL_LEFT: at x = 0, TAIL_RIGHT: at x = 255,
; + TAIL_TRACK: the camera is on the track
TAIL_LEFT       EQU 1
TAIL_RIGHT      EQU 2
TAIL_TRACK      EQU $80

; RasterEdge: B = first verge index, C = end index (exclusive), A = x offset
; (0 inner, 16 outer), HL = edge table, DE <> 0: also store colours at HL+$100

RasterEdge:
        ld (reOff), a
        ld a, l
        ld (rsTabLo), a
        ld a, h
        ld (rsTabHi), a
        ld a, d
        or e
        ld hl, $3624                    ; INC H / LD (HL),n
        ld a, $24                       ; (RasterTwo: INC H)
        jr nz, @col
        ld hl, $0218                    ; JR +2
        ld a, $C9                       ; (RasterTwo: RET)
@col:
        ld (rsColOp), hl
        ld (RasterTwo@col), a
        ld a, c
        ld (reEnd), a
        ld a, b
        cp c
        ret nc
        call LoadPoint
        ld hl, (p1x)
        ld (p0x), hl
        ld hl, (p1y)
        ld (p0y), hl
        inc b
@loop:
        ld a, (reEnd)
        cp b
        ret z
        ret c
        call LoadPoint
        push bc
        ld a, b
        inc a
        ld hl, reEnd
        cp (hl)
        jr z, @last
        call RasterSeg
        pop bc
        ld hl, (p1x)
        ld (p0x), hl
        ld hl, (p1y)
        ld (p0y), hl
        inc b
        jr @loop
@last:
        call RasterSegLast
        pop bc
        jp RasterTail

; RasterTail: after the last segment. A descending last segment has been
; extended to the bottom by RasterSeg; otherwise (flat or rising) the edge
; runs straight down from the lower end of the segment, so the track around
; the car is drawn. When that end is off the screen (the nearest verge point
; is beside or behind the camera): at the screen border on its side, or with
; the camera on the track at the screen side of its verge (a point behind the
; camera can lie on the other side). When it is on the screen (the verge runs
; across the view): as its tail mode says (TailModes): at the screen side of
; its verge, or not at all. Lines below HIDDEN_LINES (behind the cockpit)
; are never rasterised.
RasterTail:
        ld a, (p0y)
        ld b, a
        ld a, (p1y)
        sub b
        ret m                           ; descending: done
        ld a, (p1y)                     ; flat: from p1
        ld hl, (p1x)
        jr z, @t1
        ld a, b                         ; rising: from p0 (the lower end)
        ld hl, (p0x)
@t1:
        or a
        ret m                           ; below the view
        cp VIEW_ROWS + 1
        jr c, @t2
        ld a, VIEW_ROWS
@t2:
        sub HIDDEN_LINES
        ret z                           ; nothing above the hidden lines
        ret c
        ld c, a                         ; C = lines HIDDEN_LINES .. to fill
        ld a, (tailModes)
        inc a
        call z, TailModes               ; (the first such edge of this frame)
        ld a, (reEnd)                   ; E = the tail mode of this verge: the
        cp 40                           ; right one (verge entries below 40)
        ld a, (tailModes)               ; or the left one
        jr c, @tm
        ld a, (tailModes + 1)
@tm:
        ld e, a
        ld a, h
        or a
        jr z, @t2m                      ; on the screen: as the mode says
        bit 7, e
        jr nz, @t2s                     ; on the track: the side of its verge
        ld l, 0                         ; off: the border it is beyond
        bit 7, h
        jr nz, @t2x
        ld l, 255
        jr @t2x
@t2m:
        ld a, e
        and 3
        ret z                           ; this verge ends here
@t2s:
        ld a, e
        and 3
        dec a
        ld l, 0
        jr z, @t2x                      ; the left verge: x = 0
        ld l, 255
@t2x:
        ld a, (rsColOp + 2)
        ld b, a                         ; B = colour of the last segment
        ld a, (rsTabLo)
        add a, HIDDEN_LINES
        ld e, a
        ld a, (rsTabHi)
        ld d, a
        ld a, (rsColOp)
        cp $24                          ; colours stored? (INC H)
        ld a, l
        ex de, hl                       ; HL = first visible line of the table
        jr nz, @t5
@t4:
        ld (hl), a
        inc h
        ld (hl), b
        dec h
        inc l
        dec c
        jr nz, @t4
        ret
@t5:
        ld (hl), a
        inc l
        dec c
        jr nz, @t5
        ret

; LoadPoint: verge entry B -> p1x (screen x), p1y (track line), p1c (colour)
LoadPoint:
        ld l, b
        ld h, VERGE_Y / 256
        ld a, (hl)
        ld (p1y), a
        ld h, VERGE_DATA / 256
        ld a, (hl)
        and 3
        ld (p1c), a
        ld a, (reOff)
        add a, b
        ld l, a
        ld h, VERGE_XLO / 256
        ld e, (hl)                      ; fraction
        inc h
        ld l, (hl)                      ; signed units
        ld h, XH_LO / 256
        ld a, (hl)
        inc h
        ld h, (hl)
        ld l, a                         ; HL = floor(units * 6.5)
        ld d, XL_TAB / 256
        ld a, (de)
        add a, 128
        add a, l
        ld l, a
        adc a, h
        sub l
        ld h, a
        ld (p1x), hl
        ret

; RasterSeg: step from p0 to p1. RasterSegLast: the last segment of the
; edge, a descending one is extended to line 0. Shortcuts (not for an
; extended segment): ends one line apart store their two lines (RasterTwo),
; ends off the screen on the same side are a run of clamped values
; (RasterOff); over 1, 2 or 4 lines the step is a shift, not a division.

RasterSegLast:
        ld e, 1
        jr RasterSegE
RasterSeg:
        ld e, 0                         ; E = 1: the last segment
RasterSegE:
        ld a, (p0c)
        ld (rsColOp + 2), a
        ld a, (p0y)
        ld b, a
        ld a, (p1y)
        sub b                           ; dy
        jp z, RasterFlat
        jp m, @down
        ld c, a                         ; ascending: n = dy, n + 1 lines
        inc a
        ld (rsCount), a
        ld a, $2C                       ; INC L
        jr @common
@down:
        neg
        ld c, a                         ; n = -dy
        inc a
        ld (rsCount), a
        ld a, $2D                       ; DEC L
        dec e
        jr nz, @common
        ld e, b                         ; extend to line 0: y0 + 1 lines
        inc e
        dec e
        jp m, @common
        inc e
        ld hl, rsCount
        ld (hl), e
        ld (rsLStep), a
        ld hl, (p1x)
        ld de, (p0x)
        jr @dx                          ; (x runs on past p1: no shortcut)
@common:
        ld (rsLStep), a
        ld hl, (p1x)
        ld de, (p0x)
        dec c
        jp z, RasterTwo                 ; one line apart (most segments)
        inc c
        ld a, d                         ; both ends off the screen on one
        or a                            ; side: clamped values
        jr z, @dx
        xor h
        jp m, @dx
        ld a, h
        or a
        jp nz, RasterOff
@dx:                                   ; step = (x1 - x0) / n as a signed
        or a                            ; 16.8 value
        sbc hl, de
        push af                         ; sign of dx
        jp p, @dpos
        xor a
        sub l
        ld l, a
        sbc a, a
        sub h
        ld h, a
@dpos:
        ld a, c
        cp 128
        jr c, @nok
        srl c                           ; long segments: halve both
        srl h
        rr l
@nok:
        ld a, c                         ; n = 1, 2, 4 (most segments span
        dec a                           ; one line): shifts
        jr z, @n1
        dec a
        jr z, @n2
        sub 2
        jr z, @n4
        ld a, h
        or a
        jr nz, @big
        ld a, l
        cp c
        jr nc, @full
        ld hl, 0                        ; |dx| < n: no integer part
        jr @frac
@n4:
        srl h                           ; (A = 0)
        rr l
        rra
@n2:
        srl h
        rr l
        rra
@n1:
        ld e, a                         ; the fraction: the bits shifted out
        jr @divdone
@full:
        ld h, l                         ; |dx| < 256: (|dx| * 256) / n gives 8.8
        ld l, 0
        call Div16by8
        ld e, l
        ld l, h
        ld h, 0
        jr @divdone
@big:
        call Div16by8                   ; HL = |dx| / n, A = remainder
@frac:
        ld e, 0                         ; fraction = remainder * 256 / n
        REPT 8
        sla e
        add a, a
        cp c
        jr c, $ + 4
        sub c
        inc e
        ENDR
@divdone:
        pop af
        jp p, @spos
        xor a                           ; negate the 24-bit step (H, L, E)
        sub e
        ld e, a
        ld a, 0
        sbc a, l
        ld l, a
        ld a, 0
        sbc a, h
        ld h, a
@spos:
        ld a, e
        ld (rsSF + 1), a
        ld a, l
        ld (rsSL + 1), a
        ld a, h
        ld (rsSH + 1), a
        ld de, (p0x)
        ld c, $80
        ld a, (rsCount)
        ld h, a                         ; H = lines to go
        ; clip at the start
        ld a, (rsLStep)
        cp $2D
        jr nz, @clipUp
@clipDown:                              ; descending: start at most at line 79
        ld a, b
        or a
        ret m                           ; starts below the view
        cp HIDDEN_LINES
        ret c                           ; ... or behind the cockpit
        cp VIEW_ROWS
        jr c, @cd2
        call StepX
        dec b
        dec h
        ret z
        jr @clipDown
@cd2:
        ld a, b                         ; at most down to line HIDDEN_LINES
        inc a
        sub HIDDEN_LINES
        cp h
        jr nc, @go
        ld h, a
        jr @go
@clipUp:                                ; ascending: start at least at line
        ld a, b                         ; HIDDEN_LINES (signed compare)
        add a, 128
        cp 128 + HIDDEN_LINES
        jr nc, @cu2
        call StepX
        inc b
        dec h
        ret z
        jr @clipUp
@cu2:
        ld a, b
        cp VIEW_ROWS
        ret nc
        ld a, VIEW_ROWS                 ; at most 80 - y lines
        sub b
        cp h
        jr nc, @go
        ld h, a
@go:
        ld a, h
        ld (rsCount), a
        ld a, (rsSL + 1)                ; the step must fit 8.8 (|step| < 128)
        rla
        sbc a, a
        ld hl, rsSH + 1
        cp (hl)
        jr nz, @slow
        ld a, d                         ; where does the run start?
        or a
        jp z, RasterFast                ; on the screen
        jp m, @left
        ld a, (hl)                      ; right of the screen: coming in?
        or a
        jp m, RasterEntry
        ld a, 255
        jp RasterConst
@left:
        ld a, (hl)                      ; left of the screen: coming in?
        or a
        jp m, @left0
        ld a, (rsSL + 1)
        ld hl, rsSF + 1
        or (hl)
        jp nz, RasterEntry
@left0:
        xor a
        jp RasterConst
@slow:
        ld a, (rsTabLo)
        add a, b
        ld l, a
        ld a, (rsTabHi)
        ld h, a
        ld a, (rsCount)
        ld b, a
        jp RasterLoop

; RasterTwo: RasterSeg's lines when the ends are one line apart (and the
; segment is not extended): line y0 gets x0, line y1 gets x1, clamped to the
; screen (as stepping by dx from x0 + 1/2 gives them), each line clipped as
; RasterSeg clips them. B = y0, DE = x0, HL = x1
RasterTwo:
        push hl
        ex de, hl
        ld c, b
        call @put                       ; line y0
        pop hl
        ld a, (p1y)
        ld c, a                         ; line y1
@put:                                   ; line C gets x = HL (clamped) unless
        ld a, c                         ; it is clipped
        cp VIEW_ROWS
        ret nc
        cp HIDDEN_LINES
        ret c
        ld a, h
        or a
        ld a, l
        jr z, @p1
        ld a, h
        rla
        sbc a, a
        cpl                             ; right of the screen: 255, left: 0
@p1:
        ld hl, (rsTabLo)                ; (rsTabHi follows)
        ld e, a
        ld a, l
        add a, c
        ld l, a
        ld (hl), e
@col:
        inc h                           ; patched: INC H, or RET without
        ld a, (rsColOp + 2)             ; colours
        ld (hl), a
        ret

; RasterOff: RasterSeg's lines when both ends lie off the screen on the side
; of D (the high byte of x0): 0 or 255, the lines clipped as RasterSeg clips
; them (B = first line, rsCount, rsLStep)
RasterOff:
        ld a, d
        rla
        sbc a, a
        cpl                             ; right of the screen: 255, left: 0
        ld e, a
        ld a, (rsCount)
        ld h, a                         ; H = lines
        ld a, (rsLStep)
        cp $2D
        jr nz, @up
        ld a, b                         ; descending: from at most line 79
        or a
        ret m                           ; starts below the view
        cp HIDDEN_LINES
        ret c                           ; ... or behind the cockpit
        sub VIEW_ROWS
        jr c, @d2
        inc a                           ; the lines above the view
        ld c, a
        ld a, h
        sub c
        ret z
        ret c
        ld h, a
        ld b, VIEW_ROWS - 1
@d2:
        ld a, b                         ; at most down to line HIDDEN_LINES
        inc a
        sub HIDDEN_LINES
        cp h
        jr nc, @go
        ld h, a
@go:
        ld a, h
        ld (rsCount), a
        ld a, e
        jp RasterConst
@up:
        ld a, b                         ; ascending: from at least line
        add a, 128                      ; HIDDEN_LINES (signed compare)
        cp 128 + HIDDEN_LINES
        jr nc, @u2
        ld a, HIDDEN_LINES
        sub b
        ld c, a                         ; the lines below it
        ld a, h
        sub c
        ret z
        ret c
        ld h, a
        ld b, HIDDEN_LINES
@u2:
        ld a, b
        cp VIEW_ROWS
        ret nc
        ld a, VIEW_ROWS                 ; at most 80 - y lines
        sub b
        cp h
        jr nc, @go
        ld h, a
        jr @go

; RasterPtr: B = first line -> BC = edge table pointer, IXL = rsCount; the
; line step (INC C / DEC C) is patched into the run loops (when it changes)
RasterPtr:
        ld a, (rsTabLo)
        add a, b
        ld c, a
        ld a, (rsTabHi)
        ld b, a
        ld a, (rsCount)
        ld ixl, a
        ld a, (rsLStep)
        sub $2C - $0C                   ; INC L / DEC L -> INC C / DEC C
@last:
        cp 0                            ; patched: the step patched last time
        ret z
        ld (@last + 1), a
        ld (RasterFastGo@fs1), a
        ld (RasterFastGo@fs2), a
        ld (RasterConstGo@cs1), a
        ld (RasterConstGo@cs2), a
        ld (RasterEntry@es1), a
        ld (RasterEntry@es2), a
        ret

; RasterFast: B = first line, E.C = x (8.8, on the screen), step rsSL.rsSF
; (|step| < 128). Once x leaves the screen the remaining lines get the
; clamped value.
RasterFast:
        ld h, e
        ld l, c
        call RasterPtr
RasterFastGo:                           ; HL = x (8.8), BC = pointer, IXL = lines
        ld a, (rsSL + 1)
        ld d, a
        ld a, (rsSF + 1)
        ld e, a                         ; DE = step
        ld a, $30                       ; step >= 0: JR NC (stop past 255)
        bit 7, d
        jr z, @f1
        ld a, $38                       ; step < 0: JR C (stop below 0)
@f1:
        ld (@xc), a
        ld (@xn), a
        ld a, (rsColOp)
        cp $18                          ; JR: no colours
        jr z, @nocol
        ld a, (rsColOp + 2)
        ld (@col + 1), a
@fc:
        ld a, h
        ld (bc), a
        inc b
@col:
        ld a, 0                         ; patched: colour
        ld (bc), a
        dec b
        dec ixl
        ret z
@fs1:
        dec c                           ; patched: INC C / DEC C
        add hl, de
@xc:
        jr nc, @fc                      ; patched: JR NC / JR C
        jr @out
@nocol:
        ld a, h
        ld (bc), a
        dec ixl
        ret z
@fs2:
        dec c                           ; patched
        add hl, de
@xn:
        jr nc, @nocol                   ; patched
@out:                                   ; off the screen: clamp the rest
        ld a, d
        rla
        sbc a, a
        cpl                             ; step >= 0: 255, < 0: 0
        jr RasterConstGo

; RasterConst: A = value for all rsCount lines from line B
RasterConst:
        ld e, a
        call RasterPtr
        ld a, e
RasterConstGo:                          ; A = value, BC = pointer, IXL = lines
        ld e, a
        ld a, (rsColOp)
        cp $18
        jr z, @nocol
        ld a, (rsColOp + 2)
        ld d, a
@cc:
        ld a, e
        ld (bc), a
        inc b
        ld a, d
        ld (bc), a
        dec b
@cs1:
        dec c                           ; patched
        dec ixl
        jr nz, @cc
        ret
@nocol:
        ld a, e
@cn:
        ld (bc), a
@cs2:
        dec c                           ; patched
        dec ixl
        jr nz, @cn
        ret

; RasterEntry: B = first line, DE.C = x (off the screen), moving towards it
; with step rsSH.rsSL.rsSF (|step| < 128): clamped values until x is on
; the screen, then RasterFastGo
RasterEntry:
        ld h, d
        ld l, e
        ld a, c
        ld iyl, a                       ; HL.IYL = x
        call RasterPtr
        ld a, h
        rla
        sbc a, a
        cpl                             ; left of the screen: 0, right: 255
        ld (@k1 + 1), a
        ld (@k2 + 1), a
        ld a, (rsSH + 1)
        ld iyh, a
        ld a, (rsSL + 1)
        ld d, a
        ld a, (rsSF + 1)
        ld e, a                         ; IYH.D.E = step
        ld a, (rsColOp)
        cp $18
        jr z, @nocol
        ld a, (rsColOp + 2)
        ld (@col + 1), a
@ec:
@k1:
        ld a, 0                         ; patched: clamped value
        ld (bc), a
        inc b
@col:
        ld a, 0                         ; patched: colour
        ld (bc), a
        dec b
        dec ixl
        ret z
@es1:
        dec c                           ; patched
        ld a, iyl
        add a, e
        ld iyl, a
        ld a, l
        adc a, d
        ld l, a
        ld a, h
        adc a, iyh
        ld h, a
        jr nz, @ec
        jr @in
@nocol:
@k2:
        ld a, 0                         ; patched
        ld (bc), a
        dec ixl
        ret z
@es2:
        dec c                           ; patched
        ld a, iyl
        add a, e
        ld iyl, a
        ld a, l
        adc a, d
        ld l, a
        ld a, h
        adc a, iyh
        ld h, a
        jr nz, @nocol
@in:
        ld h, l                         ; on the screen: HL = x (8.8)
        ld a, iyl
        ld l, a
        jp RasterFastGo

; HL = table pointer, DE = x (signed integer part), C = fraction, B = lines
RasterLoop:
        ld a, d
        or a
        jr nz, RLclamp
        ld a, e
RLst:
        ld (hl), a
rsColOp:
        inc h                           ; patched: INC H / LD (HL),n / DEC H
        ld (hl), 0                      ;   or JR +2 when there is no colour
        dec h
rsLStep:
        dec l                           ; patched: INC L / DEC L
        dec b
        ret z
        ld a, c
rsSF:
        add a, 0
        ld c, a
        ld a, e
rsSL:
        adc a, 0
        ld e, a
        ld a, d
rsSH:
        adc a, 0
        ld d, a
        jp RasterLoop
RLclamp:
        rla
        ld a, 0
        jr c, RLst
        dec a
        jr RLst

; StepX: advance x by one step (used for clipping)
StepX:
        ld a, (rsSF + 1)
        add a, c
        ld c, a
        ld a, (rsSL + 1)
        adc a, e
        ld e, a
        ld a, (rsSH + 1)
        adc a, d
        ld d, a
        ret

; flat segment: store x1 at line y1
RasterFlat:
        ld a, (p1y)
        cp VIEW_ROWS
        ret nc                          ; also rejects negative lines
        cp HIDDEN_LINES
        ret c                           ; behind the cockpit
        ld b, a
        ld a, (rsTabLo)
        add a, b
        ld l, a
        ld a, (rsTabHi)
        ld h, a
        ld de, (p1x)
        ld b, 1
        ld c, 0
        jp RasterLoop
