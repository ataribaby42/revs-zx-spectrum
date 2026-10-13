; HUD and dashboard: the two text lines at the top of the screen, starting
; lights, rev counter hand and gear indicator.
;
; Text uses the ROM character set, black on white in character rows 0 and 1,
; laid out as in the user's original ZX version: timers in row 0 during
; practice/qualifying (row 1: warnings), position/laps and the nearest
; drivers in the race (FINISHED replaces the laps). Notices (N, M, H) cover
; both rows; afterwards RedrawHud prints them again.

ROM_FONT        EQU $3C00               ; character c at ROM_FONT + 8 * c

DIAL_X          EQU 128                 ; rev counter centre (screen pixels)
DIAL_Y          EQU 165

; ---------------------------------------------------------------------------
; Text output

; PrintChar: A = character at column B of character row C. Advances B.
; Preserves C, DE, HL. While a notice covers the HUD, rows 0-1 are not
; printed (RedrawHud prints them again afterwards).
PrintChar:
        push hl
        push de
        ld e, a
        ld a, c
        cp 2
        jr nc, @p1
        ld a, (hudCovered)
        or a
        jr nz, @p2
@p1:
        ld a, e
        call DrawGlyph
@p2:
        pop de
        pop hl
        inc b
        ret

; DrawGlyph: A = character at column B, row C (screen only). Corrupts DE, HL.
DrawGlyph:
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, ROM_FONT
        add hl, de
        call CharAddr
        ld a, (hl)
        ld (de), a
        REPT 7
        inc hl
        inc d
        ld a, (hl)
        ld (de), a
        ENDR
        ret

hudCovered:     db 0                    ; non-zero: a notice covers the HUD
noticeStart:    db 0                    ; frameCounter when it was shown

; ClearHud: clear HUD rows 0-1 (8 pixel lines of 64 bytes)
ClearHud:
        ld hl, $4000
        ld b, 8
@c1:
        push bc
        push hl
        ld d, h
        ld e, l
        inc e
        ld (hl), 0
        ld bc, 63
        ldir
        pop hl
        inc h
        pop bc
        djnz @c1
        ret

; ShowNotice: HL = text (0-terminated): clear both HUD rows and centre the
; text in row 1 (for about 0.5 s, see NoticeTick)
ShowNotice:
        push hl
        call ClearHud
        pop hl
        push hl
        ld b, 0                         ; length
@s2:
        ld a, (hl)
        or a
        jr z, @s3
        inc b
        inc hl
        jr @s2
@s3:
        ld a, 32
        sub b
        srl a
        ld b, a                         ; column
        ld c, 1
        pop hl
@s4:
        ld a, (hl)
        or a
        jr z, @s5
        push hl
        call DrawGlyph
        pop hl
        inc hl
        inc b
        jr @s4
@s5:
        ld a, 1
        ld (hudCovered), a
        ld a, (frameCounter)
        ld (noticeStart), a
        ret

; NoticeTick: restore the HUD 25 frames after a notice was shown
NoticeTick:
        ld a, (hudCovered)
        or a
        ret z
        ld a, (noticeStart)
        ld b, a
        ld a, (frameCounter)
        sub b
        cp 25
        ret c
        jr RedrawHud

; RedrawHud: clear HUD rows 0-1 and print them again from the game state
RedrawHud:
        xor a
        ld (hudCovered), a
        call ClearHud
        ld a, (raceStarted)
        or a
        jp m, @race
        ld c, 40                        ; practice / qualifying: the timers
        call PrintFirstLine             ; (the lap time as shown before, 0
        ld bc, 25 * 256 + 0             ; until the first crossing; both as
        ld hl, shownBest                ; shown before), the time warning in
        call PrintTimeVals              ; row 1
        ld bc, 9 * 256 + 0
        ld hl, shownLap
        call PrintTimeVals
        ld a, (qualifyTimeEnding)
        ld c, 42
        or a
        jp m, PrintSecondLine
        ld c, 41
        add a, a
        jp m, PrintSecondLine
        ret
@race:
        ld c, 43
        call PrintFirstLine
        ld c, 44
        call PrintSecondLine
        ld a, (currentPositionBCD)
        call PrintPosition
        ld a, (currentPlayer)           ; laps to go (as UpdateLaps)
        add a, DRIVER_LAPNUMBER % 256
        ld l, a
        ld h, CAR_PAGE / 256
        ld b, (hl)
        ld a, b
        cp 1
        ccf
        ld a, b
        cpl
        ld hl, numberOfLaps
        adc a, (hl)
        jp m, @fin
        call ConvertNumberToBCD
        call PrintLapsToGo
        jr @names
@fin:
        call PrintFinished
@names:
        ld a, (positionAhead)
        ld c, a
        ld a, $20
        call PrintNearestDriver
        ld a, (positionBehind)
        ld c, a
        ld a, $29
        jp PrintNearestDriver

; CharAddr: DE = screen address of character cell (column B, row C)
CharAddr:
        ld a, c
        and $18
        or $40
        ld d, a
        ld a, c
        and 7
        rrca
        rrca
        rrca
        add a, b
        ld e, a
        ret

; PrintText: string at HL (0-terminated) at column B, row C
PrintText:
        ld a, (hl)
        or a
        ret z
        call PrintChar
        inc hl
        jr PrintText

; PrintBCD: A = BCD number as two digits (leading zero as a space)
PrintBCD:
        push af
        rrca
        rrca
        rrca
        rrca
        and $0F
        jr nz, @p1
        ld a, ' ' - '0'
@p1:
        add a, '0'
        call PrintChar
        pop af
PrintDigit:                             ; low nibble of A
        and $0F
        add a, '0'
        jp PrintChar

; PrintTime: timer entry E of the DRV page tables (tenths, seconds, minutes)
; as "MM:SS.T" at column B, row C. PrintTimeTo: the same, keeping the three
; values at HL.
PrintTime:
        ld hl, timeVals
PrintTimeTo:
        push hl
        ld d, DRV_PAGE / 256
        ld a, BEST_LAP_MINUTES % 256
        add a, e
        ld e, a
        ld a, (de)
        ld (hl), a                      ; minutes
        inc hl
        ld a, e
        sub 24
        ld e, a
        ld a, (de)
        ld (hl), a                      ; seconds
        inc hl
        ld a, e
        sub 24
        ld e, a
        ld a, (de)
        ld (hl), a                      ; hundredths
        pop hl
        ; fall through

; PrintTimeVals: HL = minutes, seconds, hundredths (BCD) as "MM:SS.T"
PrintTimeVals:
        ld a, (hl)
        call PrintBCD
        ld a, ':'
        call PrintChar
        inc hl
        ld a, (hl)
        push af
        rrca
        rrca
        rrca
        rrca
        call PrintDigit
        pop af
        call PrintDigit
        ld a, '.'
        call PrintChar
        inc hl
        ld a, (hl)                      ; hundredths: print the tenths
        rrca
        rrca
        rrca
        rrca
        jp PrintDigit

timeVals:       ds 3
shownLap:       ds 3                    ; the lap time shown in the HUD
shownBest:      ds 3                    ; the best lap time shown in the HUD

; ---------------------------------------------------------------------------
; Text routines called by the game code (BBC names)

; PrintFirstLine / PrintSecondLine: C = token. PrintSecondLineGap: token C
; on the second line and a blank first line.
PrintSecondLineGap:
        call PrintSecondLine
        ld c, 45
PrintFirstLine:
        ld a, c
        ld c, 0
        jr PrintLine
PrintSecondLine:
        ld a, c
        ld c, 1
PrintLine:
        ld hl, tokenTable
@t1:
        cp (hl)
        inc hl
        jr z, @t2
        inc hl
        inc hl
        jr @t1
@t2:
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl
        ld b, 0
        jp PrintText

tokenTable:
        db 40
        dw token40
        db 41
        dw token41
        db 42
        dw token42
        db 43
        dw token43
        db 44
        dw token44
        db 48
        dw token48
        db 53
        dw token53
        db 45
        dw token45

token40:        db "Lap Time            Best        ", 0
token41:        db "   Less than one minute to go   ", 0
token42:        db "        YOUR TIME IS UP!        ", 0
token43:        db "Pos.      In front:             ", 0
token44:        db "Laps:       Behind:             ", 0
token45:        db "                                ", 0
token48:        db "          PLEASE WAIT           ", 0
token53:        db "            FINISHED            ", 0

; PrintLapTime: the lap timer (row 0)
PrintLapTime:
PrintLapTimeA:
        ld bc, 9 * 256 + 0
        ld e, 21                        ; timer 1 (lap) follows the 20 drivers
        ld hl, shownLap
        jp PrintTimeTo

; PrintLapUpdate: the running lap time on every update. When a second has
; passed (carry) the whole time, as the original; otherwise only the tenths,
; which the original leaves standing between the seconds.
PrintLapUpdate:
        jr c, PrintLapTime
        ld a, (BEST_LAP_TENTHS + 21)    ; timer 1: hundredths (BCD)
        ld (shownLap + 2), a
        rrca
        rrca
        rrca
        rrca
        ld bc, 15 * 256 + 0             ; column of the tenths
        jp PrintDigit

; PrintBestLapTime: the player's best lap (right-aligned), then the lap timer
PrintBestLapTime:
        ld a, (currentPlayer)
        ld e, a
        ld bc, 25 * 256 + 0
        ld hl, shownBest
        call PrintTimeTo
        jr PrintLapTime

PrintSpaces:
        xor a
        ret

; PrintPosition / PrintLapsToGo: A = BCD value
PrintPosition:
        ld bc, 5 * 256 + 0
        jp PrintBCD
PrintLapsToGo:
        ld bc, 5 * 256 + 1
        jp PrintBCD

; PrintFinished: FINISHED in place of the laps to go (row 1)
PrintFinished:
        ld hl, finishedText
        ld bc, 0 * 256 + 1
        jp PrintText
finishedText:   db "FINISHED", 0

; PrintNearestDriver: name of the driver at position C on the first line
; (A = $20) or the second line (A = $29)
PrintNearestDriver:
        ld b, a
        ld a, DRIVERS_IN_ORDER % 256
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (hl)
        ld l, a                         ; HL = driverNames + 12 * driver
        ld h, 0
        add hl, hl
        add hl, hl
        ld e, l
        ld d, h
        add hl, hl
        add hl, de
        ld de, driverNames
        add hl, de
        ld a, b
        cp $29
        ld bc, 20 * 256 + 0
        jr nz, @n1
        inc c
@n1:
        ld e, 12
@n2:
        ld a, (hl)
        call PrintChar
        inc hl
        dec e
        jr nz, @n2
        ret

; ---------------------------------------------------------------------------
; Dashboard

; PrintGearNumber: the gear glyph (R N 1-5) in the gear window
PrintGearNumber:
        ld a, (gearNumber)
        ld l, a                         ; HL = gearGlyphs + 12 * gear
        ld h, 0
        add hl, hl
        add hl, hl
        ld e, l
        ld d, h
        add hl, hl
        add hl, de
        ld de, gearGlyphs
        add hl, de
        ld a, GEAR_ROW
        ld b, 6
@g1:
        push af
        push bc
        call ScreenRowAddr              ; DE = row start
        ld a, e
        add a, GEAR_ADDR_COL
        ld e, a
        ld a, (hl)                      ; black = field and not white
        cpl
        and GEAR_MASK0
        ld b, a
        ld a, (de)
        and (~GEAR_MASK0) & $FF
        or b
        ld (de), a
        inc hl
        inc e
        ld a, (hl)
        cpl
        and GEAR_MASK1
        ld b, a
        ld a, (de)
        and (~GEAR_MASK1) & $FF
        or b
        ld (de), a
        inc hl
        pop bc
        pop af
        inc a
        djnz @g1
        ret

; UpdateDashboard: rev counter hand (as the BBC: revCount clamped to 30-170,
; 0.75 * revCount on a 152-step dial with 76 at the bottom)
UpdateDashboard:
        ld a, (revCount)
        cp 30
        jr nc, @u1
        ld a, 30
@u1:
        ld b, a
        srl a
        add a, b
        rra
        sub 76
        jr nc, @u2
        add a, 152
@u2:
        ld hl, needlePos
        cp (hl)
        call nz, @newNeedle
        ; steering wheel mark: pose 2 * min(61, steeringHi * 2 + steeringLo
        ; bit 7) + steeringLo bit 0 (set: left), with its end stop
        ld a, (steeringHi)
        cp 31
        ld a, 61
        jr nc, @w1
        ld a, (steeringLo)
        rla
        ld a, (steeringHi)
        adc a, a
@w1:
        add a, a
        ld b, a
        ld a, (steeringLo)
        and 1
        or b
        ld hl, wheelPos
        cp (hl)
        ret z
        push af
        ld a, (hl)
        call XorWheelMark
        pop af
        ld (wheelPos), a
        jp XorWheelMark

@newNeedle:
        push af
        ld a, (hl)
        call XorNeedle                  ; erase the old hand
        pop af
        ld (needlePos), a
        ; fall through: draw the new hand

; XorNeedle: A = dial position (0-151): XOR the hand into the screen
XorNeedle:
        ld l, a                         ; (positions up to 151: 16-bit index)
        ld h, 0
        add hl, hl
        ld de, needleTab
        add hl, de
        ld a, (hl)                      ; dx
        inc hl
        ld e, (hl)                      ; dy
        ld d, a
        ld bc, DIAL_X * 256 + DIAL_Y
        jp XorLine

needlePos:      db 0
wheelPos:       db 0

; XorWheelMark: A = pose 0..123 (bit 0 set: left, the mirror image of the
; right-hand pose A / 2): XOR its runs into the white cockpit pixels
XorWheelMark:
        ld c, a
        srl a
        ld e, a
        ld d, 0
        ld hl, wheelPoseIdx
        add hl, de
        ld e, (hl)                      ; first run
        inc hl
        ld a, (hl)
        sub e
        ret z
        ld b, a                         ; B = runs
        ld l, e
        ld h, d
        add hl, hl
        add hl, de                      ; 3 * run
        ld de, wheelRuns
        add hl, de
        push hl
        pop ix
@run:
        push bc
        ld a, (ix + 1)
        ld e, a
        and $1F
        bit 0, c
        jr z, @r1
        cpl                             ; mirror: column 31 - c
        and $1F
@r1:
        ld (@col + 1), a
        ld (@ccol + 1), a
        ld a, e
        rlca
        rlca
        rlca
        and 7
        inc a
        ld (@rows + 1), a
        ld a, (ix + 2)                  ; mask
        bit 0, c
        jr z, @r2
        ld e, a                         ; mirror: reverse the bits
        ld b, 8
@rev:
        rr e
        rla
        djnz @rev
@r2:
        ld (@mask + 1), a
        ld a, (ix + 0)
        add a, 128 - COCKPIT_TOP        ; HL = cockpit byte of the first row
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
@ccol:
        ld de, 0                        ; patched: column
        add hl, de
        ld de, CockpitBitmap
        add hl, de
        ld a, (ix + 0)
        add a, 128
        ld b, a                         ; B = screen row
@rows:
        ld c, 0                         ; patched: rows
@row:
        ld a, b
        call ScreenRowAddr              ; DE = row address
        ld a, e
@col:
        add a, 0                        ; patched: column
        ld e, a
        ld a, (hl)                      ; white cockpit pixels only
        cpl
@mask:
        and 0                           ; patched
        ex de, hl
        xor (hl)
        ld (hl), a
        ex de, hl
        ld de, 32
        add hl, de
        inc b
        dec c
        jr nz, @row
        ld de, 3
        add ix, de
        pop bc
        djnz @run
        ret

; DrawCasIndicator: the C64 Revs+ CAS indicator on the rev counter, white
; pixels on the dial while CAS is on, the cockpit bytes when off
DrawCasIndicator:
        ld hl, casIndicator
@d1:
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld a, d
        or e
        ret z
        ld c, (hl)                      ; C = mask
        inc hl
        ld a, (casOn)
        or a
        ld a, (hl)                      ; cockpit byte
        inc hl
        jr z, @d2
        ld a, c                         ; on: clear (white) the masked pixels
        cpl
        ex de, hl
        and (hl)
        ld (hl), a
        ex de, hl
        jr @d1
@d2:
        ex de, hl                       ; off: the cockpit bits under the mask
        xor (hl)
        and c
        xor (hl)
        ld (hl), a
        ex de, hl
        jr @d1

; XorLine: line from (B, C) by (D, E) (signed offsets), XORed into the screen.
; The screen byte (HL) and the pixel mask (C) step from pixel to pixel.
XorLine:
        ld a, d                         ; x: to the right (RRC C, INC L) or
        ld hl, $2C09                    ; to the left (RLC C, DEC L)
        or a
        jp p, @l1
        neg
        ld hl, $2D01
@l1:
        ld d, a                         ; D = |dx|
        ld a, l
        ld (@hx + 1), a
        ld (@vx + 1), a
        ld a, h
        ld (@hxb), a
        ld (@vxb), a
        ld a, e                         ; y: down or up
        ld hl, ScreenDown
        or a
        jp p, @l2
        neg
        ld hl, ScreenUp
@l2:
        ld e, a                         ; E = |dy|
        ld (@hy + 1), hl
        ld (@vy + 1), hl
        push de
        ld a, c                         ; HL = screen byte of (B, C)
        call ScreenRowAddr
        ld a, b
        rrca
        rrca
        rrca
        and $1F
        add a, e
        ld l, a
        ld h, d
        ld a, b                         ; C = its pixel mask
        and 7
        add a, MASKBIT % 256
        ld e, a
        ld d, MASKS / 256
        ld a, (de)
        ld c, a
        pop de
        ld a, d
        cp e
        jr c, @steep
        ld (@hdx + 1), a                ; mostly horizontal: |dx| + 1 pixels
        ld b, a
        inc b
        srl a
        ld d, a                         ; D = error
        ld a, e
        ld (@hdy + 1), a
@h1:
        ld a, (hl)
        xor c
        ld (hl), a
@hx:
        rrc c                           ; patched: RRC C / RLC C
        jr nc, @h2
@hxb:
        inc l                           ; patched: INC L / DEC L
@h2:
        ld a, d
@hdy:
        sub 0                           ; patched: |dy|
        ld d, a
        jr nc, @h3
@hdx:
        add a, 0                        ; patched: |dx|
        ld d, a
@hy:
        call ScreenDown                 ; patched: ScreenDown / ScreenUp
@h3:
        djnz @h1
        ret
@steep:
        ld a, d                         ; mostly vertical: |dy| + 1 pixels
        ld (@vdx + 1), a
        ld a, e
        ld (@vdy + 1), a
        ld b, a
        inc b
        srl a
        ld d, a                         ; D = error
@v1:
        ld a, (hl)
        xor c
        ld (hl), a
@vy:
        call ScreenDown                 ; patched: ScreenDown / ScreenUp
        ld a, d
@vdx:
        sub 0                           ; patched: |dx|
        ld d, a
        jr nc, @v3
@vdy:
        add a, 0                        ; patched: |dy|
        ld d, a
@vx:
        rrc c                           ; patched: RRC C / RLC C
        jr nc, @v3
@vxb:
        inc l                           ; patched: INC L / DEC L
@v3:
        djnz @v1
        ret

; ScreenDown / ScreenUp: HL = screen address one pixel row lower / higher
ScreenDown:
        inc h
        ld a, h
        and 7
        ret nz
        ld a, l
        add a, 32
        ld l, a
        ret c
        ld a, h
        sub 8
        ld h, a
        ret

ScreenUp:
        ld a, h
        dec h
        and 7
        ret nz
        ld a, l
        sub 32
        ld l, a
        ret c
        ld a, h
        add a, 8
        ld h, a
        ret

; ScreenRowAddr: A = pixel row (0..191) -> DE = address of its first byte.
; Preserves BC, HL.
ScreenRowAddr:
        ld d, a
        and 7
        ld e, a
        ld a, d
        rra
        rra
        rra
        and %00011000
        or e
        or $40
        ld e, a
        ld a, d
        rla
        rla
        and %11100000
        ld d, e
        ld e, a
        ret

; ---------------------------------------------------------------------------
; Starting lights, as the user's ZX version (and the BBC, top right just above
; the horizon): three 8x8 lamps at x = 232-255, y = 88-95 (attribute cells
; 29-31 of row 11) with white frames (ink) and coloured paper (black = off,
; blue, green), and a black line above, below and left of the group

LIGHTS_Y        EQU 87                  ; the black line above the lamps

; DrawStartingLights: A = LIGHTS_OFF, LIGHTS_BLUE or LIGHTS_GREEN (the lamps
; are drawn by StartLights)
DrawStartingLights:
        ld b, %01000111                 ; off: white ink on black paper
        cp LIGHTS_BLUE
        jr c, @l1
        ld b, %01001111                 ; blue paper
        jr z, @l1
        ld b, %01100111                 ; green paper
@l1:
        ld a, b
        ld (lightsShown), a
        ret

lightsShown:    db 0                    ; attribute of the lamps, 0: none

; StartLights: after the objects, before EndView (the view buffer is not
; being copied). While the lights are shown they are drawn over the view
; buffer; the view copy takes them to the screen (the whole view is copied
; when their colour changes). Once the race runs they are removed from the
; sky rows of the buffer (the ground rows are composed again every frame),
; and the attributes are restored next time, after that view copy.
StartLights:
        ld a, (lightsShown)
        or a
        ret z
        ld c, a                         ; C = attribute
        ld b, $FF                       ; B = mask of the lamp bytes
        ld a, (raceStarting)
        or a
        jr nz, @s1
        ld b, a                         ; the race runs
        ld a, c
        cp ATTR_VIEW
        jr z, @s0
        ld a, ATTR_VIEW                 ; first remove the lamps
        ld (lightsShown), a
        xor a
        ld (screenSky), a
        jr @s2
@s0:
        xor a                           ; then the attributes
        ld (lightsShown), a
@s1:
        ld hl, $5800 + (LIGHTS_Y + 1) / 8 * 32 + 29
        ld a, (hl)
        cp c
        jr z, @s2
        ld (hl), c                      ; a new colour (or none)
        inc l
        ld (hl), c
        inc l
        ld (hl), c
        xor a                           ; copy the whole view this time
        ld (screenSky), a
@s2:
        ld c, 10                        ; C = rows
        ld a, b
        or a
        jr nz, @s3
        call SkyRows                    ; removing: only the sky rows
        sub LIGHTS_Y - VIEW_TOP
        ret c
        ret z
        cp c
        jr nc, @s3
        ld c, a
@s3:
        ld de, lightsRows
        ld hl, VIEW_BUF + (LIGHTS_Y - VIEW_TOP) * 32 + 28
@s4:
        ld a, (hl)                      ; x = 231: the line left of the lamps
        or 1
        bit 0, b
        jr nz, @s5
        and $FE
@s5:
        ld (hl), a
        ld a, (de)
        inc de
        and b
        REPT 3
        inc l
        ld (hl), a
        ENDR
        ld a, l                         ; next row
        add a, 32 - 3
        ld l, a
        jr nc, @s6
        inc h
@s6:
        dec c
        jr nz, @s4
        ret

lightsRows:     db $FF, $FF             ; y = 87: black line, 88: frames
                db $81, $81, $81, $81, $81, $81
                db $FF, $FF             ; y = 95: frames, 96: black line

; ---------------------------------------------------------------------------
; UpdateMirrors (as the BBC): the car behind appears as a block in one of six
; mirror segments, chosen from its yaw angle relative to ours, with a height
; from its size. While the engine runs the reflection shudders (random white
; pixels), so a segment showing a car is redrawn on every iteration.

mirrorSegment:  db 18, 17, 16, 14, 13, 12
mirrorV:        db 0
mirrorRnd:      dw 0                    ; walks through the ROM for random bytes
mirrorEngine:   db 0                    ; engineStatus at the last update
mirrorRedraw:   db 0                    ; non-zero: redraw a segment with a car

UpdateMirrors:
        ld a, (mirrorsOn)               ; M off: as if the car behind were
        or a                            ; hidden (clears the segments once)
        ld a, $FF
        jp z, @v
        ld a, (engineStatus)            ; redraw while the engine runs, and
        ld hl, mirrorEngine             ; once more when it stops
        ld b, (hl)
        ld (hl), a
        or b
        ld (mirrorRedraw), a
        ld a, (positionBehind)
        add a, DRIVERS_IN_ORDER % 256
        ld l, a
        ld h, CAR_PAGE / 256
        ld c, (hl)                      ; C = driver behind
        ld a, c
        add a, OBJ_STATUS % 256
        ld l, a
        ld h, OBJ_STATUS / 256
        ld a, (hl)
        or a
        ld a, $FF                       ; hidden: no segment matches
        jp m, @v
        ld a, c
        add a, OBJ_SIZE % 256
        ld l, a
        ld a, (hl)                      ; T = size / 8, at most 7
        rrca
        rrca
        rrca
        and $1F
        cp 8
        jr c, @t1
        ld a, 7
@t1:
        inc a
        ld e, a                         ; E = mirror contents (T + 1)
        ld a, c
        add a, OBJ_YAWHI % 256
        ld l, a
        ld a, (hl)
        ld hl, playerYawAngleHi
        sub (hl)
        sub 4
        rrca
        rrca
        rrca
        and $1F
@v:
        ld (mirrorV), a
        ld b, 5
@m1:
        push de
        ld d, 0
        ld e, b
        ld hl, mirrorSegment
        add hl, de
        ld a, (mirrorV)
        cp (hl)
        ld hl, mirrorContents
        add hl, de                      ; (keeps the zero flag)
        pop de
        jr z, @car
        ld a, (hl)                      ; no car: clear the segment if needed
        or a
        jr z, @next
        xor a
        jr @draw
@car:
        ld a, (mirrorRedraw)            ; engine on: shudder on every update
        or a
        jr nz, @c1
        ld a, e
        cp (hl)
        jr z, @next
@c1:
        ld a, e
@draw:                                  ; A = new contents, (HL) = old
        push bc
        push de
        ld d, (hl)
        ld (hl), a
        call DrawMirrorSegment
        pop de
        pop bc
@next:
        dec b
        jp p, @m1
        ret

; DrawMirrorSegment: segment B, A = 0 (no car) or T + 1 (T = size / 8, at
; most 7). The car has the shape approved in the user's version: four source
; pixels at 2x1 (8 pixels), half the BBC height (T rows, at most 6) centred
; on MIRROR_MID, and at the largest size the top two rows only the central
; four pixels. It is black with random white source pixels while the engine
; runs (a fresh sample per row). The band of six rows around the centre is
; redrawn; the rest of the glass stays white.
MIRROR_BAND     EQU MIRROR_MID - 3 - MIRROR_TOP ; first band row in the masks

DrawMirrorSegment:
        ld e, 0                         ; E = first car row, D = end row,
        ld d, e                         ; L = end of the narrow rows
        ld l, e
        or a
        jr z, @n2
        dec a                           ; T
        ld c, a
        cp 7
        jr c, @n1
        ld a, 6
@n1:
        ld h, a                         ; n = rows
        srl a
        add a, 3
        ld d, a                         ; end = 3 + n / 2
        sub h
        ld e, a                         ; first = end - n
        ld l, e
        ld a, c
        cp 7
        jr c, @n2
        inc l                           ; largest: two narrow rows
        inc l
@n2:
        ld a, e
        ld (@lo + 1), a
        ld a, d
        ld (@hi + 1), a
        ld a, l
        ld (@nar + 1), a
        ld a, (engineStatus)
        ld (@eng + 1), a
        ld hl, mirrorShift
        ld a, l
        add a, b
        ld l, a
        adc a, h
        sub l
        ld h, a
        ld a, (hl)
        ld (@sh + 1), a                 ; patched: shift
        ld a, b                         ; IX = masks of the band rows
        add a, a
        ld l, a
        ld h, 0
        ld de, mirrorSegs
        add hl, de
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        ld a, (hl)
        ld (@col + 1), a                ; first byte column
        ld de, 1 + 2 * MIRROR_BAND
        add hl, de
        push hl
        pop ix
        ld hl, mirrorRows + 2 * MIRROR_BAND
        ld c, 0                         ; C = band row
@row:
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        push hl
        ld a, e
@col:
        add a, 0                        ; patched
        ld e, a                         ; DE = first screen byte
        ld b, 0                         ; B = car pixels (none)
        ld a, c
@lo:
        cp 0                            ; patched
        jr c, @w
@hi:
        cp 0                            ; patched
        jr nc, @w
        ld hl, (mirrorRnd)              ; random white source pixels while
        ld a, r                         ; the engine runs
        and (hl)
        inc l
        ld (mirrorRnd), hl
@eng:
        and 0                           ; patched: engineStatus
        cpl
        rrca
        rrca
        rrca
        rrca
        and $0F                         ; four black source pixels
        ld hl, mirrorPixels
        add a, l
        ld l, a
        adc a, h
        sub l
        ld h, a
        ld b, (hl)                      ; doubled to 8 pixels
        ld a, c
@nar:
        cp 0                            ; patched: narrow rows end
        jr nc, @w
        ld a, b
        and $3C                         ; the central four pixels
        ld b, a
@w:
        ld l, 0                         ; (B L) = pixels >> shift
@sh:
        ld a, 0                         ; patched
        or a
        jr z, @s2
@s1:
        srl b
        rr l
        dec a
        jr nz, @s1
@s2:
        ld a, (ix + 0)                  ; screen = screen ^ (screen ^ ink) & mask
        ld h, a
        ld a, (de)
        xor b
        and h
        ex de, hl
        xor (hl)
        ld (hl), a
        ex de, hl
        inc e
        ld a, (ix + 1)
        ld h, a
        ld a, (de)
        xor l
        and h
        ex de, hl
        xor (hl)
        ld (hl), a
        ex de, hl
        inc ix
        inc ix
        pop hl
        inc c
        ld a, c
        cp 6
        jr c, @row
        ld hl, mirrorRnd + 1            ; next ROM page for the next update
        inc (hl)
        res 6, (hl)
        ret

mirrorPixels:                           ; four source pixels -> eight pixels
        db $00, $03, $0C, $0F, $30, $33, $3C, $3F
        db $C0, $C3, $CC, $CF, $F0, $F3, $FC, $FF


        INCLUDE "mirrors.asm"
        INCLUDE "wheel.asm"

; ---------------------------------------------------------------------------
; InitDrivingScreen: cockpit, HUD lines, dashboard

InitDrivingScreen:
        call InitScreen
        call StoreUI                    ; the UI overlay into the hidden sky
        xor a                           ; the HUD is not covered, no lights
        ld (hudCovered), a
        ld (lightsShown), a
        xor a                           ; the view on the screen is clear sky,
        ld (skyClean), a                ; the buffer has to be rebuilt
        ld a, VIEW_ROWS
        ld (screenSky), a
        ld (objTopRow), a
        ld a, (needlePos)
        call XorNeedle
        ld a, (wheelPos)
        call XorWheelMark
        call DrawCasIndicator
        jp PrintGearNumber

        INCLUDE "text.asm"
