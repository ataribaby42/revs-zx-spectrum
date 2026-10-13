; Race set-up (C64 versions). Runs once per session: cold memory.

; ---------------------------------------------------------------------------
; ResetVariables: reset the driving state before a practice, qualifying or
; race session and place the cars on the grid.

ResetVariables:
        ld hl, ZPAGE                       ; zero page $00-$68 (the C64 also
        ld de, ZPAGE + 1                   ; clears $FE68, a sound variable)
        ld bc, $68
        ld (hl), 0
        ldir
        ld hl, BLK62
        ld b, BLK62_END - BLK62
        xor a
@r1:
        ld (hl), a
        inc hl
        djnz @r1
        ld a, 23
        ld (previousSignNumber), a
        ld de, (trackStartLine)         ; all objects on the start line
        ld h, OBJ_PAGE / 256
        ld c, 23
@r3:
        ld a, OBJ_SEGHI % 256
        add a, c
        ld l, a
        ld (hl), d
        sub 24
        ld l, a
        ld (hl), e
        ld a, OBJ_SECTION % 256
        add a, c
        ld l, a
        ld (hl), 0
        ld a, OBJ_SEGMT % 256
        add a, c
        ld l, a
        ld (hl), 0
        dec c
        jp p, @r3
        call SetPlayerPositions
        ld a, (raceStarted)
        or a
        ld a, 1                         ; race: one segment between cars
        jp m, @r4
        ld a, (trackStartPosition)      ; practice: player starts at a fixed
        ld c, a                         ; position on the grid
        ld a, (currentPosition)
        ld b, a
        call SwapDriverPosition
        call SetPlayerPositions
        ld a, (trackCarSpacing)
@r4:
        call PlaceCarsOnTrack
        ld c, 19
@r5:
        ld h, CAR_PAGE / 256
        ld a, TOTAL_RACE_MINUTES % 256
        add a, c
        ld l, a
        ld (hl), $80
        ld a, CAR_SECTIONSPEED % 256
        add a, c
        ld l, a
        ld (hl), $FF
        ld b, 0
        ld a, DRIVER_LAPNUMBER % 256
        add a, c
        ld l, a
        ld (hl), b
        ld a, CAR_STEERING % 256
        add a, c
        ld l, a
        ld (hl), b
        ld a, CAR_PROGRESS % 256
        add a, c
        ld l, a
        ld (hl), b
        ld a, CAR_SPEEDHI % 256
        add a, c
        ld l, a
        ld (hl), b
        ld a, CAR_SPEEDLO % 256
        add a, c
        ld l, a
        ld (hl), b
        ld a, POSITION_NUMBER % 256
        add a, c
        ld l, a
        ld (hl), b
        ld h, OBJ_PAGE / 256
        ld a, OBJ_STATUS % 256
        add a, c
        ld l, a
        ld (hl), $80
        dec c
        jp p, @r5
        ld a, 1
        ld (gearNumber), a
        ld (pastHalfway), a
        ld hl, mirrorContents           ; (A = 1, as on the C64)
        ld b, 6
@r6:
        ld (hl), a
        inc hl
        djnz @r6
        ld a, 7
        ld (oddsOfEngineStart), a
        dec a
        ld (sectionListValid), a
        ld (sectionListPointer), a
        call PrintGearNumber
        ld a, (raceStarted)
        or a
        jp m, @r7
        ld c, 45                        ; practice / qualifying: timers in
        call PrintSecondLine            ; row 0, row 1 blank
        ld c, 40
        call PrintFirstLine
        ld c, 1
        call ZeroTimer
        call PrintBestLapTime
        ld a, $DF
        ld (firstLapStarted), a
        ret
@r7:
        ld (updateDrivingInfo), a       ; race
        ld (updateDriverInfo), a
        ld c, 43
        call PrintFirstLine
        ld c, 44
        call PrintSecondLine
        ld a, (currentPosition)
        call ConvertNumberToBCD
        ld (positionChangeBCD), a
        ret

; ConvertNumberToBCD: A = 0..98 -> BCD of A + 1
ConvertNumberToBCD:
        inc a
        ld b, 0
@c1:
        sub 10
        jr c, @c2
        inc b
        jr @c1
@c2:
        add a, 10
        ld c, a
        ld a, b
        add a, a
        add a, a
        add a, a
        add a, a
        or c
        ret

; ---------------------------------------------------------------------------
; PlaceCarsOnTrack: A = spacing in segments between grid positions. Cars are
; placed behind the start line in grid order, the sign object 23 just ahead
; of the player; the player's segment buffer is filled.

PlaceCarsOnTrack:
        ld (V), a
        ld hl, updateLapTimes           ; no lap times while placing the cars
        scf
        rr (hl)
@p1:
        ld c, 19                        ; move all cars until object 0 is on
@p2:                                    ; the start line again
        ld a, c
        call MoveObjectForward
        dec c
        jp p, @p2
        ld hl, (OBJ_SEGLO)
        ld a, (OBJ_SEGHI)
        or l
        jr nz, @p1
        ld a, $FF
        ld (G), a
        jr @p5
@p3:
        ld a, (V)
        ld (W), a
@p4:
        ld a, DRIVERS_IN_ORDER % 256      ; move the driver in position C back
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (hl)
        call MoveObjectBack
        ld hl, W
        dec (hl)
        jp p, @p4
        inc c
        ld a, c
        cp 20
        jr c, @p3
@p5:
        ld hl, G
        inc (hl)
        ld c, (hl)
        ld a, c
        cp 20
        jr c, @p3
@p6:
        ld a, 23                        ; move object 23 to 32 segments ahead
        call MoveObjectForward          ; of the player
        ld b, 23
        ld a, (currentPlayer)
        ld c, a
        scf
        call CompareSegments
        jr c, @p6
        cp 32
        jr nz, @p6
        ld a, 49
        ld (V), a
        ld (segmentCounter), a
@p7:
        ld a, 23
        call MoveObjectBack
        ld hl, V
        dec (hl)
        jr nz, @p7
@p8:
        ld hl, segmentCounter
        inc (hl)
        ld a, 23
        call MoveObjectBack
        jr nc, @p8
        ld a, 80                        ; alternate racing lines
        ld c, 19
@p9:
        cpl
        ld b, a
        ld a, DRIVERS_IN_ORDER % 256
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (hl)
        add a, CAR_RACINGLINE % 256
        ld l, a
        ld (hl), b
        ld a, b
        dec c
        jp p, @p9
        xor a
        ld (frontSegmentIndex), a
@p10:
        call GetTrackSegment
        ld hl, segmentCounter
        dec (hl)
        jr nz, @p10
        ld hl, updateLapTimes
        srl (hl)
        ret


; ---------------------------------------------------------------------------
; InitialiseDrivers: called with A = 0. Grid order 0..19, two cars per row,
; random speeds, no points. Sets the race class to Novice.

InitialiseDrivers:
        ld (setSpeedForDriver), a
        ld (raceClass), a
        ld c, a
        call GetSectionSteering
        ld c, 0
@d1:
        ld h, CAR_PAGE / 256
        ld a, DRIVERS_IN_ORDER % 256
        add a, c
        ld l, a
        ld (hl), c
        ld a, c
        srl a
        ld b, a
        ld a, DRIVER_GRIDROW % 256
        add a, c
        ld l, a
        ld (hl), b
        call SetDriverSpeed             ; C = next driver (0..19, descending)
        ld h, DRV_PAGE / 256
        xor a
        ld b, a
        ld a, TOTAL_POINTS_LO % 256
        add a, c
        ld l, a
        ld (hl), b
        ld a, TOTAL_POINTS_HI % 256
        add a, c
        ld l, a
        ld (hl), b
        ld a, TOTAL_POINTS_TOP % 256
        add a, c
        ld l, a
        ld (hl), b
        ld a, c
        or a
        jr nz, @d1
        ret


; ---------------------------------------------------------------------------
; GetSectionSteering: C = race class. Sets baseSpeed and scales the track's
; per-section steering for the class (bit 1 set: no scaling).

GetSectionSteering:
        ld a, trackBaseSpeed % 256
        add a, c
        ld l, a
        ld h, trackBaseSpeed / 256
        ld a, (hl)
        ld (baseSpeed), a
        ld (U), a
        ld a, (trackSectionCount)
        rrca
        rrca
        rrca
        and $1F
        ld b, a
        ld c, a
@s1:
@tcSteering:                            ; (track code: the track's table)
        ld hl, trackSteering
        ld a, l
        add a, c
        ld l, a
        ld a, (hl)
        srl a
        rr d                            ; bit 7 of D = steering flag (bit 0)
        srl a
        jr c, @s2
        call Multiply8x8
@s2:
        add a, a
        rl d
        rra
        ld hl, sectionSteering
        ld e, c
        ld d, 0
        add hl, de
        ld (hl), a
        dec c
        jp p, @s1
        ret

; ---------------------------------------------------------------------------
; SortDrivers: A bit 6 set = by total points (descending), bit 7 set = by
; total race time, otherwise by best lap time. Bubble sort of driversInOrder;
; positionNumber gets each position, equal times/points share a position.

SortDrivers:
        ld (G), a                       ; BBC leftOfEdge
@sort1:
        xor a
        ld (V), a                       ; BBC edgePixel: swaps in this pass
        ld (POSITION_NUMBER), a
        ld c, 1
@sort2:
        ld a, c
        ld (W), a
        ld h, CAR_PAGE / 256
        add a, DRIVERS_IN_ORDER % 256
        ld l, a
        ld e, (hl)                      ; E = driver at this position (6502 Y)
        dec l
        ld d, (hl)                      ; D = driver ahead (6502 X)
        ld a, POSITION_NUMBER % 256
        add a, c
        ld l, a
        ld (hl), c
        ld a, (G)
        bit 6, a
        jr nz, @sort5
        bit 7, a
        jr nz, @sort6
        ld h, DRV_PAGE / 256             ; best lap: this - ahead
        ld b, BEST_LAP_TENTHS % 256
        call @subYX
        ld (U), a
        ld b, BEST_LAP_SECONDS % 256
        call @sbcYX
        ld (Hv), a                      ; BBC rightOfEdge
        ld b, BEST_LAP_MINUTES % 256
        call @sbcYX
        jr c, @sort7
@sort3:
        ld hl, U
        or (hl)
        ld hl, Hv
        or (hl)
        jr nz, @sort4
        ld a, POSITION_NUMBER % 256 - 1   ; tie: share the position ahead
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (hl)
        inc l
        ld (hl), a
@sort4:
        inc c
        ld a, c
        cp 20
        jr c, @sort2
        ld a, (V)
        or a
        jr nz, @sort1
        jp SetPlayerPositions

@sort5:                                 ; points: ahead - this
        ld h, DRV_PAGE / 256
        ld b, TOTAL_POINTS_LO % 256
        call @subXY
        ld (U), a
        ld b, TOTAL_POINTS_HI % 256
        call @sbcXY
        ld (Hv), a
        ld b, TOTAL_POINTS_TOP % 256
        call @sbcXY
        jr c, @sort7
        jr @sort3

@sort6:                                 ; race time: this - ahead, no ties
        ld h, DRV_PAGE / 256
        ld b, TOTAL_RACE_TENTHS % 256
        call @subYX
        ld (U), a
        ld b, TOTAL_RACE_SECONDS % 256
        call @sbcYX
        ld (Hv), a
        ld h, CAR_PAGE / 256
        ld b, TOTAL_RACE_MINUTES % 256
        call @sbcYX
        jr nc, @sort4

@sort7:                                 ; swap with the driver ahead
        ld a, d
        ld (T), a
        ld a, DRIVERS_IN_ORDER % 256 - 1
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld (hl), e
        inc l
        ld (hl), d
        ld hl, V
        dec (hl)
        jr @sort4

; BCD subtraction of table B (page H) entries: A = [B+E] - [B+D] (.subYX,
; .sbcYX with borrow) or [B+D] - [B+E] (.subXY, .sbcXY). Carry = borrow of
; the binary subtraction, as the 6502's decimal SBC: DAA would change it
; for bytes that are not BCD (the DNF mark $C0 of ClearTotalRaceTime).
@subYX:
        or a
@sbcYX:
        push af
        ld a, b
        add a, d
        ld l, a
        ld a, (hl)
        ld (@yx + 1), a
        ld a, b
        add a, e
        ld l, a
        pop af
        ld a, (hl)
@yx:
        sbc a, 0                        ; patched
@daa:
        jr c, @daa1
        daa
        or a                            ; no borrow
        ret
@daa1:
        daa
        scf
        ret

@subXY:
        or a
@sbcXY:
        push af
        ld a, b
        add a, e
        ld l, a
        ld a, (hl)
        ld (@xy + 1), a
        ld a, b
        add a, d
        ld l, a
        pop af
        ld a, (hl)
@xy:
        sbc a, 0                        ; patched
        jr @daa

; ---------------------------------------------------------------------------
; FinishRace: the player has left the track. Keep simulating the other cars
; until they have all finished the race (or, in qualifying, for the rest of
; the session)

FinishRace:
        xor a
        ld (playerMoving), a
        ld (raceStarting), a
        call HideAllCars
        ld a, (currentPlayer)
        ld c, a
        call ClearTotalRaceTime
@fini1:
        ld a, $FE                       ; Caps Shift + 3: to the main menu
        in a, ($FE)
        rra
        jr c, @fini1k
        ld a, $F7
        in a, ($FE)
        and 4
        jp z, UiNewGame
@fini1k:
        call ProcessTime
        call MoveCars
        call ProcessOvertaking
        call SetPlayerPositions
        ld c, 19
        ld a, (raceStarted)
        or a
        jp m, @fini2
        ld a, (currentPlayer)
        cp c
        ret nz
        ld a, (mainLoopCounterHi)
        cp 10
        jr c, @fini1
        ret
@fini2:
        ld a, OBJ_STATUS % 256
        add a, c
        ld l, a
        ld h, OBJ_STATUS / 256
        bit 6, (hl)
        jr nz, @fini3
        ld a, DRIVER_LAPNUMBER % 256
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (numberOfLaps)
        cp (hl)
        jr nc, @fini1
@fini3:
        dec c
        jp p, @fini2
        ret

; ---------------------------------------------------------------------------
; BuildPlayerCar: place the player on the track at their car's position and
; point them along the track

BuildPlayerCar:
        ld a, (currentPlayer)
        ld (driverPrinted), a
        ld (colourScheme), a
        ld c, a
        CAR_INDEX
        ld a, (playerSegmentIndex)
        ld e, a
        call BuildCarObjects
        ld hl, SEG_LO + xCoord2
        ld de, playerCoordX + 1
        call @copy
        ld de, playerCoordY + 1
        call @copy
        ld de, playerCoordZ + 1
        call @copy
        ld a, (playerSegmentIndex)
        add a, 3
        cp 120
        jr c, @b2
        xor a
@b2:
        ld e, a
        ld a, (driverPrinted)
        ld c, a
        CAR_INDEX
        call BuildCarObjects
        ld a, c
        add a, OBJ_YAWLO % 256
        ld l, a
        ld h, OBJ_YAWLO / 256
        ld a, (hl)
        ld (playerYawAngleLo), a
        ld a, l
        add a, 24
        ld l, a
        ld a, (directionFacing)
        xor (hl)
        ld (playerYawAngleHi), a
        ret
@copy:                                  ; (DE) = SEG_LO (HL), (DE+1) = SEG_HI (HL)
        ld a, (hl)
        ld (de), a
        inc de
        inc h
        ld a, (hl)
        ld (de), a
        dec h
        inc l
        ret
