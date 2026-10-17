; Lap counting, timers and position info (C64 versions)
;
; Times are BCD: "tenths" hold hundredths of a second (the C64 adds 0.13 s
; per main loop iteration, 0.26 s once every trackTimerAdjust iterations).

; ---------------------------------------------------------------------------
; UpdateLaps: object IX has crossed the start/finish line. Preserves BC, DE.

UpdateLaps:
        ld a, (updateLapTimes)
        or a
        ret m
        ld a, ixl
        sub OBJ_BIAS
        cp 20
        ret nc
        push bc
        push de
        call @update
        pop de
        pop bc
        ret

@update:
        ld c, a
        ld a, (ix + objectStatus)
        add a, a
        ret m                           ; bit 6: car not racing
        ld a, (currentPlayer)
        cp c
        jr nz, @u3
        ld hl, pastHalfway              ; the player only completes a lap
        dec (hl)                        ; after passing the halfway section
        jr z, @u2
        inc (hl)
        ret
@u2:
        ld a, $80
        ld (updateDrivingInfo), a
@u3:
        ld h, CAR_PAGE / 256
        ld a, DRIVER_LAPNUMBER % 256
        add a, c
        ld l, a
        ld a, (hl)
        or a
        jp m, @u4
        inc (hl)
@u4:
        ld b, a                         ; lap number before the increment
        ld a, (raceStarted)
        or a
        ld a, (currentPlayer)
        jp p, @u5
        ld a, b                         ; race
        ld hl, numberOfLaps
        cp (hl)
        jr c, @u7
        ret nz
        ld a, (currentPlayer)           ; last lap done: the player leaves
        cp c                            ; the track
        jr nz, @u7
        ld a, 55
        ld (leaveTrackTimer), a
        jr @u7
@u5:
        cp c                            ; practice: lap times only for the
        ret c                           ; human players
@u7:
        ld a, TOTAL_RACE_SECONDS % 256    ; lap time = clock - time at the line
        add a, c
        ld e, a
        ld a, TOTAL_RACE_MINUTES % 256
        add a, c
        ld d, a
        ld h, DRV_PAGE / 256
        ld a, TOTAL_RACE_TENTHS % 256
        add a, c
        ld l, a
        ld a, (CLOCK_TENTHS)
        sub (hl)
        daa
        ld (T), a
        ld l, e
        ld a, (CLOCK_SECONDS)
        sbc a, (hl)
        daa
        jr nc, @u8
        add a, $60
        daa
        scf
@u8:
        ld (U), a
        ld h, CAR_PAGE / 256
        ld l, d
        ld a, (CLOCK_MINUTES)
        sbc a, (hl)
        daa
        ld (Hv), a                      ; BBC rightOfEdge
        jr c, @u9                       ; first crossing (minutes bit 7 set)
        ld h, DRV_PAGE / 256             ; faster than the best lap?
        ld a, BEST_LAP_TENTHS % 256
        add a, c
        ld e, a                         ; E, D, B = best lap tenths, seconds,
        add a, 24                       ; minutes entries
        ld d, a
        add a, 24
        ld b, a
        ld l, e
        ld a, (T)
        sub (hl)
        ld l, d
        ld a, (U)
        sbc a, (hl)
        ld l, b
        ld a, (Hv)
        sbc a, (hl)
        jr nc, @u9
        ld l, e                         ; new best lap
        ld a, (T)
        and $F0
        ld (hl), a
        ld l, d
        ld a, (U)
        ld (hl), a
        ld l, b
        ld a, (Hv)
        ld (hl), a
@u9:
        ld h, DRV_PAGE / 256             ; remember the time at the line
        ld a, TOTAL_RACE_TENTHS % 256
        add a, c
        ld l, a
        ld a, (CLOCK_TENTHS)
        ld (hl), a
        ld a, TOTAL_RACE_SECONDS % 256
        add a, c
        ld l, a
        ld a, (CLOCK_SECONDS)
        ld (hl), a
        ld h, CAR_PAGE / 256
        ld a, TOTAL_RACE_MINUTES % 256
        add a, c
        ld l, a
        ld a, (CLOCK_MINUTES)
        ld (hl), a
        ret

; ---------------------------------------------------------------------------
; ZeroTimer: C = timer (0 = clock, 1 = lap timer). Returns A = 0, Z set.

ZeroTimer:
        ld h, DRV_PAGE / 256
        ld a, CLOCK_TENTHS % 256
        add a, c
        ld l, a
        ld (hl), 0
        add a, 24
        ld l, a
        ld (hl), 0
        add a, 24
        ld l, a
        xor a
        ld (hl), a
        ret

; AddTimeToTimer: C = timer. Adds one main loop step (0.13 s, or 0.26 s when
; timerAdjust = trackTimerAdjust). Returns carry = hundredths overflowed.

AddTimeToTimer:
        ld a, (trackTimerAdjust)
        ld b, a
        ld a, (timerAdjust)
        cp b
        ld b, $13
        jr nz, @t1
        ld b, $26
@t1:
        ld h, DRV_PAGE / 256
        ld a, CLOCK_TENTHS % 256
        add a, c
        ld l, a
        ld a, (hl)
        add a, b
        daa
        ld (hl), a
        ld b, 0
        rl b                            ; B = carry
        push bc
        ld a, l
        add a, 24
        ld l, a
        ld a, (hl)
        add a, b
        daa
        ld b, 0
        cp $60
        jr c, @t2
        xor a
        inc b
@t2:
        ld (hl), a
        ld a, l
        add a, 24
        ld l, a
        ld a, (hl)
        add a, b
        daa
        ld (hl), a
        or a
        jp p, @t3
        call ZeroTimer                  ; 80 minutes: give up
        ld a, (currentPlayer)
        add a, TOTAL_RACE_MINUTES % 256
        ld l, a
        ld h, CAR_PAGE / 256
        ld (hl), $80
@t3:
        pop bc
        ld a, b
        rrca
        ret

; ProcessTime: per main loop iteration: clock, loop counter, driver speeds

ProcessTime:
        ld a, (timerAdjust)
        or a
        jr nz, @t1
        ld a, (trackTimerAdjust)
        inc a
        jr z, @t2
@t1:
        dec a
        ld (timerAdjust), a
@t2:
        ld a, (raceStarting)
        or a
        jp m, @t3
        ld c, 0
        call AddTimeToTimer
@t3:
        ld hl, mainLoopCounterLo
        inc (hl)
        jr nz, @t4
        ld hl, mainLoopCounterHi
        inc (hl)
@t4:
        ld a, (CLOCK_SECONDS)
        or a
        jr z, @t5
        ld a, (mainLoopCounterLo)
        and $1F
        ret nz
@t5:
        jp SetDriverSpeed

; ---------------------------------------------------------------------------
; UpdateLapTimers: lap timer (practice/qualifying), laps to go and position
; (race), end of qualifying

UpdateLapTimers:
        ld a, (raceStarted)
        or a
        jp p, @laps2
        ld a, (updateDrivingInfo)
        or a
        jp p, @laps1
        xor a
        ld (updateDrivingInfo), a
        ld (G), a
        ld a, (currentPlayer)
        add a, DRIVER_LAPNUMBER % 256
        ld l, a
        ld h, CAR_PAGE / 256
        ld b, (hl)
        ld a, b
        cp 1
        ccf                             ; 6502 carry: lap >= 1
        ld a, b
        cpl
        ld hl, numberOfLaps
        adc a, (hl)                     ; laps to go - 1
        push af
        call ConvertNumberToBCD
        call PrintLapsToGo
        pop af
        jp p, @laps1
        call PrintFinished              ; in place of the laps to go
@laps1:
        ld a, (leaveTrackTimer)
        or a
        ret nz
        jp UpdatePositionInfo

@laps2:
        ld c, 1
        call AddTimeToTimer
        push af                         ; carry: a second has passed
        ld a, (updateDrivingInfo)
        bit 6, a
        jr nz, @laps4
        or a
        jp p, @laps6p
        ld hl, updateDrivingInfo        ; crossed the line
        srl (hl)
        ld a, (firstLapStarted)
        add a, 33
        ld (firstLapStarted), a
        jr z, @laps3
        ld a, %00100110
        call PrintLapTimeA              ; time of the lap just finished
@laps3:
        ld c, 1
        call ZeroTimer
        jr @laps6p
@laps4:
        ld a, (firstLapStarted)
        or a
        jr z, @laps5
        dec a
        ld (firstLapStarted), a
        jr nz, @laps6p
        call PrintBestLapTime
        ld a, 2
        call PrintSpaces
        jr @laps6p
@laps5:
        pop af
        call PrintLapUpdate             ; (carry: a second has passed)
        jr @laps6
@laps6p:
        pop af
@laps6:
        ld a, (qualifyingTime)
        or a
        ret m
        ld hl, CLOCK_MINUTES
        cp (hl)
        jr c, @laps7
        ret nz
        ld a, (qualifyTimeEnding)
        bit 6, a
        ret nz
        ld a, %01000000                 ; one minute left
        ld (qualifyTimeEnding), a
        ld c, 41
        jp PrintSecondLine
@laps7:
        ld a, (qualifyTimeEnding)
        or a
        ret m
        ld a, %11000000                 ; time up
        ld (qualifyTimeEnding), a
        ld a, 41
        ld (leaveTrackTimer), a
        ld c, 42
        jp PrintSecondLine

; UpdatePositionInfo: race position and the drivers ahead and behind

UpdatePositionInfo:
        ld a, (positionChangeBCD)
        or a
        jr z, @p1
        ld hl, currentPositionBCD
        ld b, a
        add a, (hl)
        ld c, a                         ; (the 6502 sets Z from the binary sum)
        ld a, b
        add a, (hl)
        daa
        ld (hl), a
        inc c
        dec c
        jr z, @p1
        cp $21
        jr nc, @p1
        xor a
        ld (positionChangeBCD), a
        ld (G), a
        ld a, (hl)
        call PrintPosition
@p1:
        ld a, (updateDriverInfo)
        or a
        jp p, @p2
        ld a, (positionAhead)
        ld c, a
        ld a, $20
        call PrintNearestDriver
        ld a, (positionBehind)
        ld c, a
        ld a, $29
        call PrintNearestDriver
@p2:
        ld hl, updateDriverInfo
        srl (hl)
        ret

; ---------------------------------------------------------------------------
; PrintSpeed: the player's speed in mph, right-aligned in three columns of
; HUD row 1 and followed by MPH: always columns 0-5 (in the race followed by
; the laps to go). mph = playerSpeed (8.8) * 1.3125 (1 +
; 1/4 + 1/16): the car moves 2 units per iteration per unit of speed, an
; iteration is 0.13 s, and Silverstone is 124,289 units for 2.932 miles; at
; most 254. Printed only when it changes, and not over the time warnings or
; FINISHED. MPH is printed after RedrawHud, InitDrivingScreen or
; PrintSecondLine (they set shownSpeed to $FF).

PrintSpeed:
        ld a, (playerSpeedLo)
        ld l, a
        ld a, (playerSpeedHi)
        ld h, a                         ; HL = speed (8.8)
        ld d, h
        ld e, l
        ld b, 2
@m1:
        srl d                           ; + speed / 4, / 16
        rr e
        srl d
        rr e
        add hl, de
        jr c, @m2
        djnz @m1
        ld a, h
        cp 255
        jr c, @m3
@m2:
        ld a, 254                       ; (255: no speed shown)
@m3:
        ld hl, shownSpeed
        cp (hl)
        ret z
        ld e, a                         ; E = mph
        ld bc, 0 * 256 + 1              ; column 0 of row 1
        ld a, (raceStarted)
        rla
        jr nc, @s1
        ld a, (leaveTrackTimer)         ; the race: not after FINISHED
        jr @s2
@s1:
        ld a, (qualifyTimeEnding)       ; not over the time warnings
        and $C0
@s2:
        or a
        ret nz
        ld a, (hl)
        inc a                           ; Z: the row was printed again
        ld (hl), e
        push af
        ld a, e
        ld de, 100 * 256 + ' '          ; D = place value, E = leading zero
        call @digit
        ld d, 10
        call @digit
        ld de, 1 * 256 + '0'
        call @digit
        pop af
        ret nz
        ld hl, mphText
        jp PrintText
@digit:                                 ; A = value
        ld h, '0' - 1
@d1:
        inc h
        sub d
        jr nc, @d1
        add a, d
        ld l, a                         ; L = the rest
        ld a, h
        cp '0'
        jr nz, @d2
        ld a, e                         ; a leading zero
        jr @d3
@d2:
        ld e, '0'                       ; zeros after a digit are digits
@d3:
        call PrintChar                  ; (advances B, preserves C, DE, HL)
        ld a, l
        ret
