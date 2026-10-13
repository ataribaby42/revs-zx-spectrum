; UI overlay: menus, championship tables and tape transfers, as the user's
; ZX version (github.com/ataribaby42/revs-zx-spectrum-c64-rate:
; src/menu_overlay.asm, track_menu.asm, championship_results.asm,
; results_tape.asm, ui_keyboard.asm): the same screens, texts, colours and
; keys, captions in capitals.
;
; Assembled for and loaded at UI_RUN (the view buffer and edge pages,
; uncontended, unused outside driving); while driving it is kept in the
; hidden sky and at UI_STORE (StoreUI and LoadUI in game.asm), so its
; variables (the results record, the menu choices, the track in memory)
; keep their values.
;
; Text lists: attribute, character row, column, text, 0, ..., 0.

; ---------------------------------------------------------------------------
; Entry points

UiNewGame:                              ; start, Caps Shift + 3, BREAK
        di
        ld sp, STACK_TOP
        ei
UiMainMenu:
        call UiClear
        ld hl, uiTitleText
        call UiTextList
        ld hl, uiMainText
        call UiTextList
        ld a, (uiResultsValid)
        or a
        ld hl, uiShowText
        call nz, UiTextList
        call UiWaitRelease
@m1:
        call UiKey
        cp '1'
        jr z, UiPractice
        cp '2'
        jr z, UiCompetition
        cp '3'
        jp z, UiResultsLoad
        cp '4'
        jp z, UiResultsSave
        cp '5'
        jr z, @clear
        cp '6'
        jr nz, @m1
        ld a, (uiResultsValid)          ; 6 only after results exist
        or a
        jr z, @m1
        call UiShowResults
        jr UiMainMenu
@clear:
        call UiClearResults
        jr UiMainMenu

; UiPractice: THE PITS, the track, then practice laps without opponents
; or time limit (BBC: player 0, qualifyingTime = 255) until Caps Shift + 3
UiPractice:
        call UiWings
        call UiTrackMenu
        xor a
        call InitialiseDrivers
        xor a
        ld (currentPlayer), a
        dec a
        ld (qualifyingTime), a
        call ResetBestLapTimes
        call UiSetWings
        ld a, %00101000
        call HeadToTrack
        jr UiMainMenu

; UiCompetition: the Formula 3 championship (BBC MainLoop, one player)
UiCompetition:
        ld hl, uiClassText
        call UiThreeOptions
        ld (uiClass), a
        ld hl, uiDurationText
        call UiThreeOptions
        ld e, a
        ld d, 0
        ld hl, uiDurationValues
        add hl, de
        ld a, (hl)
        ld (uiDuration), a
        call UiNameEntry
        call UiWings
        call UiTrackMenu
        ; qualifying
        xor a
        call InitialiseDrivers
        ld a, (uiClass)
        ld (raceClass), a
        ld c, a
        call GetSectionSteering
        ld a, (uiDuration)
        ld (qualifyingTime), a
        call ResetBestLapTimes
        ld a, 19
        ld (currentPlayer), a
        call UiPlayerName
        call UiSetWings
        ld a, %00101000
        call HeadToTrack
        call UiFinish
        xor a                           ; grid by the best laps
        call SortDrivers
        call UiAdjustClass
        xor a
        call UiTable                    ; GRID POSITIONS
        ld hl, uiLapsText
        call UiThreeOptions
        ld (uiLapsChoice), a
        call UiSpace
        call UiWings
        ; the race
        ld a, (uiLapsChoice)
        ld e, a
        ld d, 0
        ld hl, uiLapValues
        add hl, de
        ld a, (hl)
        ld (numberOfLaps), a
        ld c, 19                        ; the grid order again (BBC game14)
@r1:
        ld a, DRIVERS_IN_ORDER2 % 256
        add a, c
        ld l, a
        ld h, DRV_PAGE / 256
        ld b, (hl)
        ld a, DRIVERS_IN_ORDER % 256
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld (hl), b
        dec c
        jp p, @r1
        call ResetBestLapTimes
        call UiSetWings
        ld a, %10000000
        call HeadToTrack
        call UiFinish
        ld a, %10000000                 ; race order: 9, 6, 4, 3, 2, 1 points
        call SortDrivers
        ld c, 0
@r2:
        push bc
        ld hl, uiPlacePoints
        ld b, 0
        add hl, bc
        ld a, DRIVERS_IN_ORDER % 256
        add a, c
        ld e, a
        ld d, CAR_PAGE / 256
        ld a, (de)
        ld e, a
        ld a, (hl)
        call UiAddPoints
        pop bc
        inc c
        ld a, c
        cp 6
        jr c, @r2
        ld a, 1
        call UiTable                    ; POINTS
        xor a                           ; one point for the fastest lap
        call SortDrivers
        ld a, (DRIVERS_IN_ORDER)
        ld e, a
        ld a, 1
        call UiAddPoints
        ld a, 2
        call UiTable                    ; BEST LAP TIMES
        call UiShowScores               ; ACCUMULATED POINTS
        jp UiMainMenu

; UiPits: Caps Shift + 1 while stationary in practice or qualifying (called
; from the driving loop, which then places the car at the start again)
UiPits:
        call UiWings
        ; fall through

; UiSetWings: the chosen wing settings for the driving model
UiSetWings:
        ld a, (uiRearWing)
        ld (rearWingSetting), a
        ld a, (uiFrontWing)
        ld (frontWingSetting), a
        ret

; UiPlayerName: the driver name for the player's identity (19)
UiPlayerName:
        ld hl, uiDriverName
        ld de, driverNames + 19 * 12
        ld bc, 12
        ldir
        ret

; UiFinish: PLEASE WAIT while FinishRace completes the session for the other
; drivers (Caps Shift + 3 returns to the menu from there)
UiFinish:
        call UiClear
        ld hl, uiPleaseWaitText
        call UiTextList
        jp FinishRace

; UiAdjustClass (BBC MainLoop game6-game10): a slowest human qualifier can
; lower the class by the track's lap times; the steering for the class;
; the grid order is kept in driversInOrder2 and the player's grid row is
; the (shared) position / 2
UiAdjustClass:
        ld a, (DRIVERS_IN_ORDER + 19)
        cp 19
        jr nz, @a3
        ld bc, 0
@a1:
        ld hl, trackLapTimeSec
        add hl, bc
        ld a, (BEST_LAP_SECONDS + 19)
        sub (hl)
        inc hl                          ; trackLapTimeMin (INC HL keeps the
        inc hl                          ; borrow of the seconds)
        inc hl
        ASSERT trackLapTimeMin == trackLapTimeSec + 3
        ld a, (BEST_LAP_MINUTES + 19)
        sbc a, (hl)
        jr nc, @a2
        inc c
        jr @a1
@a2:
        ld a, c
        ld hl, raceClass
        cp (hl)
        jr nc, @a3
        ld (hl), a
@a3:
        ld a, (raceClass)
        ld (uiClass), a
        ld c, a
        call GetSectionSteering
        ld c, 19
@g1:
        ld a, DRIVERS_IN_ORDER % 256
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld b, (hl)
        ld a, DRIVERS_IN_ORDER2 % 256
        add a, c
        ld l, a
        ld h, DRV_PAGE / 256
        ld (hl), b
        ld a, b
        cp 19
        jr c, @g2
        ld a, POSITION_NUMBER % 256
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (hl)
        srl a
        ld e, a
        ld a, DRIVER_GRIDROW % 256
        add a, b
        ld l, a
        ld (hl), e
@g2:
        dec c
        jp p, @g1
        ret

; UiAddPoints: A = points (BCD) for driver identity E, six BCD digits
UiAddPoints:
        ld hl, uiResultsValid
        ld (hl), 1
        ld d, 0
        ld hl, uiPoints
        add hl, de
        add hl, de
        add hl, de
        add a, (hl)
        daa
        ld (hl), a
        inc hl
        ld a, (hl)
        adc a, 0
        daa
        ld (hl), a
        inc hl
        ld a, (hl)
        adc a, 0
        daa
        ld (hl), a
        ret

; UiShowResults: main menu 6, the standings without awarding anything
UiShowResults:
        ld hl, DRIVERS_IN_ORDER
        ld b, 20
        xor a
@o1:
        ld (hl), a
        inc l
        inc a
        djnz @o1
        call UiPlayerName
UiShowScores:
        ld hl, uiPoints                 ; scores into the BBC points tables
        ld c, 0
@s1:
        ld d, DRV_PAGE / 256
        ld a, TOTAL_POINTS_LO % 256
        add a, c
        ld e, a
        ldi
        inc bc
        ld a, TOTAL_POINTS_HI % 256
        add a, c
        ld e, a
        ldi
        inc bc
        ld a, TOTAL_POINTS_TOP % 256
        add a, c
        ld e, a
        ldi
        inc bc
        inc c
        ld a, c
        cp 20
        jr c, @s1
        ld a, %01000000
        call SortDrivers
        ld a, 3
        jp UiTable                      ; ACCUMULATED POINTS

; UiClearResults: an empty record, the name cleared
UiClearResults:
        xor a
        ld (uiResultsValid), a
        ld hl, uiNameLength
        ld (hl), a
        inc hl
        ld b, 12
@c1:
        ld (hl), ' '
        inc hl
        djnz @c1
        ld b, 60
@c2:
        ld (hl), a
        inc hl
        djnz @c2
        ret

; ---------------------------------------------------------------------------
; Menus and editors

UiChampTitle:
        call UiClear
        ld hl, uiChampText
        jp UiTextList

; UiThreeOptions: HL = text list. Returns A = 0..2 (keys 1-3).
UiThreeOptions:
        push hl
        call UiChampTitle
        ld hl, uiChoicesText
        call UiTextList
        pop hl
        call UiTextList
        call UiWaitRelease
@w1:
        call UiKey
        sub '1'
        cp 3
        jr nc, @w1
        ret

; UiSpace: PRESS SPACE TO CONTINUE, wait for SPACE
UiSpace:
        ld hl, uiSpaceText
        call UiTextList
        call UiWaitRelease
@s1:
        call UiKey
        cp ' '
        jr nz, @s1
        ret

; UiWings: THE PITS, rear then front wing (0-40), then SPACE
UiWings:
        call UiClear
        ld hl, uiPitsText
        call UiTextList
        ld a, 14
        call UiNumberInput
        ld (uiRearWing), a
        ld hl, uiFrontText
        call UiTextList
        ld a, 16
        call UiNumberInput
        ld (uiFrontWing), a
        jp UiSpace

; UiNumberInput: A = row. Returns 0..40; ENTER needs a digit, Caps Shift +
; 0 deletes one, values above 40 are not accepted.
UiNumberInput:
        ld (uiInputRow), a
        xor a
        ld (uiInputLength), a
        ld (uiInputValue), a
        ld hl, $2020                    ; two spaces
        ld (uiInputText), hl
@i1:
        ld a, (uiInputRow)
        ld d, a
        ld e, 20
        ld hl, uiInputText
        ld a, $43
        call UiPrint
@i2:
        call UiWaitRelease
@i3:
        call UiKey
        or a
        jr z, @i3
        cp 8
        jr z, @del
        cp 13
        jr z, @enter
        sub '0'
        cp 10
        jr nc, @i2
        ld c, a
        ld a, (uiInputLength)
        cp 2
        jr nc, @i2
        ld a, (uiInputValue)            ; value * 10 + digit
        add a, a
        ld b, a
        add a, a
        add a, a
        add a, b
        add a, c
        cp 41
        jr nc, @i2
        ld (uiInputValue), a
        ld a, (uiInputLength)
        ld e, a
        ld d, 0
        inc a
        ld (uiInputLength), a
        ld hl, uiInputText
        add hl, de
        ld a, c
        add a, '0'
        ld (hl), a
        jr @i1
@del:
        ld a, (uiInputLength)
        or a
        jr z, @i2
        dec a
        ld (uiInputLength), a
        ld e, a
        ld d, 0
        ld hl, uiInputText
        add hl, de
        ld (hl), ' '
        ld a, (uiInputText)             ; the value of what is left
        sub '0'
        jr nc, @d1
        xor a
@d1:
        ld (uiInputValue), a
        jr @i1
@enter:
        ld a, (uiInputLength)
        or a
        jr z, @i2
        ld a, (uiInputValue)
        ret

; UiNameEntry: ENTER NAME OF DRIVER, up to 12 characters, the last name
; prefilled; ENTER confirms, Caps Shift + 0 deletes, Symbol Shift + M is a
; full stop
UiNameEntry:
        call UiChampTitle
        ld hl, uiNameText
        call UiTextList
@n1:
        ld hl, uiDriverName
        ld de, uiLine
        ld bc, 12
        ldir
        xor a
        ld (de), a
        ld hl, uiLine
        ld de, 14 * 256 + 10
        ld a, $43
        call UiPrint
@n2:
        call UiWaitRelease
@n3:
        call UiKey
        or a
        jr z, @n3
        cp 13
        jr z, @enter
        cp 8
        jr z, @del
        cp ' '
        jr c, @n2
        ld c, a
        ld a, (uiNameLength)
        cp 12
        jr nc, @n2
        ld e, a
        ld d, 0
        inc a
        ld (uiNameLength), a
        ld hl, uiDriverName
        add hl, de
        ld (hl), c
        jr @n1
@del:
        ld a, (uiNameLength)
        or a
        jr z, @n2
        dec a
        ld (uiNameLength), a
        ld e, a
        ld d, 0
        ld hl, uiDriverName
        add hl, de
        ld (hl), ' '
        jr @n1
@enter:
        ld a, (uiNameLength)
        or a
        jr z, @n2
        ret

; UiTrackMenu: the six tracks; the one in memory ("* " before its name) is
; used as it is, another one is loaded from the tracks tape
UiTrackMenu:
        call UiClear
        ld hl, uiTitleText
        call UiTextList
        ld hl, uiTrackText
        call UiTextList
        ld a, (uiCachedTrack)
        or a
        jr z, @t1
        sub '1'
        add a, a
        add a, 10
        ld d, a
        ld e, 9
        ld hl, uiStarText
        ld a, $46
        call UiPrint
@t1:
        call UiWaitRelease
@t2:
        call UiKey
        sub '1'
        cp 6
        jr nc, @t2
        add a, '1'
        ld (uiChoice), a
        ld hl, uiCachedTrack
        cp (hl)
        ret z
        ; fall through

; UiLoadTrack: the track uiChoice from the tracks tape into the track slot.
; Headers: CODE, the first six characters of the track name, 2048 bytes.
; The slot counts as empty from the start of the data block until it has
; loaded without error (an interrupted load must be repeated).
UiLoadTrack:
        call UiClear
        ld hl, uiLoadText
        call UiTextList
        ld a, (uiChoice)
        sub '1'
        add a, a
        ld e, a
        ld d, 0
        ld hl, uiTrackNames
        add hl, de
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        ld (uiTrackName), hl
        push hl
        ld b, 32                        ; centred in row 10
@l1:
        ld a, (hl)
        inc hl
        or a
        jr z, @l2
        dec b
        jr @l1
@l2:
        srl b
        ld e, b
        ld d, 10
        pop hl
        ld a, $46
        call UiPrint
@find:
        ld ix, uiHeader
        ld de, 17
        xor a
        scf
        call UiReadBlock
        jr nc, @find
        ld a, (uiHeader)
        cp 3
        jr nz, @find
        ld hl, (uiTrackName)
        ld de, uiHeader + 1
        ld b, 6
@l3:
        ld a, (de)
        cp (hl)
        jr nz, @find
        inc hl
        inc de
        djnz @l3
        ld hl, (uiHeader + 11)
        ld de, -2048
        add hl, de
        ld a, h
        or l
        jr nz, @find
        ld (uiCachedTrack), a           ; the slot is being overwritten
        call TcReset                    ; (the old track's code is undone)
        ld ix, TRACK
        ld de, 2048
        ld a, $FF
        scf
        call UiReadBlock
        jr nc, @error
@code:                                  ; then its code (header: CODE for
        ld ix, uiHeader                 ; TRACKCODE)
        ld de, 17
        xor a
        scf
        call UiReadBlock
        jr nc, @code
        ld hl, (uiHeader + 13)
        ld de, -TRACKCODE
        add hl, de
        ld a, h
        or l
        jr nz, @code
        ld de, (uiHeader + 11)
        ld ix, TRACKCODE
        ld a, $FF
        scf
        call UiReadBlock
        jr nc, @error
        call TcLoaded
        ld a, (uiChoice)
        ld (uiCachedTrack), a
        ret
@error:
        ld hl, uiTapeErrorText
        ld de, 22 * 256 + 4
        ld a, $42
        call UiPrint
        jp @find

; ---------------------------------------------------------------------------
; Results tape: the 76-byte record (signature, version, name, scores)

UiResultsLoad:
        ld hl, uiResultsLoadText
        call UiResultsPrompt
@find:
        ld ix, uiHeader
        ld de, 17
        xor a
        scf
        call UiReadBlock
        jr nc, @find
        ld hl, uiResultsHeader          ; type, name and length
        ld de, uiHeader
        ld b, 13
@f1:
        ld a, (de)
        cp (hl)
        jr nz, @find
        inc hl
        inc de
        djnz @f1
        ld ix, UI_TAPE_BUF
        ld de, UI_RECORD_SIZE
        ld a, $FF
        scf
        call UiReadBlock
        jr nc, @error
        ld hl, (UI_TAPE_BUF)            ; check it all before using it
        ld de, 'R' + 256 * 'C'
        or a
        sbc hl, de
        jr nz, @error
        ld a, (UI_TAPE_BUF + 2)
        dec a
        jr nz, @error
        ld a, (UI_TAPE_BUF + 3)
        cp 13
        jr nc, @error
        ld hl, UI_TAPE_BUF + 4
        ld b, 12
@c1:
        ld a, (hl)
        sub 32
        cp 95
        jr nc, @error
        inc hl
        djnz @c1
        ld b, 60
@c2:
        ld a, (hl)
        and 15
        cp 10
        jr nc, @error
        ld a, (hl)
        cp $A0
        jr nc, @error
        inc hl
        djnz @c2
        ld hl, UI_TAPE_BUF
        ld de, uiRecord
        ld bc, UI_RECORD_SIZE
        ldir
        ld a, 1
        ld (uiResultsValid), a
        jp UiMainMenu
@error:
        ld hl, uiTapeErrorText
        ld de, 6 * 256 + 4
        ld a, $42
        call UiPrint
        jp @find

UiResultsSave:
        ld hl, uiResultsSaveText
        call UiResultsPrompt
        call UiSpace
        call UiWaitRelease
        ld ix, uiResultsHeader
        ld de, 17
        xor a
        call UiWriteBlock
        ld b, 50                        ; the usual pause after a header
@p1:
        halt
        djnz @p1
        ld ix, uiRecord
        ld de, UI_RECORD_SIZE
        ld a, $FF
        call UiWriteBlock
        jp UiMainMenu

UiResultsPrompt:
        push hl
        call UiClear
        ld hl, uiTitleText
        call UiTextList
        pop hl
        jp UiTextList

; UiReadBlock: ROM LD-BYTES (A = flag, carry = load, IX, DE), entered after
; its PUSH of SA/LD-RET so that it returns here (no BREAK error). Returns
; carry = loaded. BREAK (Caps Shift + Space) returns to the main menu.
UiReadBlock:
        inc d
        ex af, af'
        dec d
        di
        ld a, $0F
        out ($FE), a
        call $0562
        jr UiTapeDone

; UiWriteBlock: ROM SA-BYTES (A = flag, IX, DE), the same way
UiWriteBlock:
        di
        call $04C6
UiTapeDone:
        push af
        xor a                           ; black border
        out ($FE), a
        ld a, $7F
        in a, ($FE)
        rra
        jr c, @t1
        ld a, $FE
        in a, ($FE)
        rra
        jp nc, UiNewGame                ; BREAK
@t1:
        pop af
        ei
        ret

; ---------------------------------------------------------------------------
; Driver tables: A = 0 GRID POSITIONS, 1 POINTS, 2 BEST LAP TIMES,
; 3 ACCUMULATED POINTS. 20 rows in colour bands with black gutters.

UiTable:
        ld (uiTableKind), a
        call UiClear
        ld a, (uiTableKind)
        add a, a
        ld e, a
        ld d, 0
        ld hl, uiTableTitles
        add hl, de
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        call UiTextList
        ld a, (uiTableKind)
        cp 3
        jr z, @t1
        ld a, (uiClass)                 ; class and laps in row 1
        add a, a
        ld e, a
        ld d, 0
        ld hl, uiClassNames
        add hl, de
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        ld de, 1 * 256 + 2
        ld a, 7
        call UiPrint
        ld a, (uiLapsChoice)
        add a, a
        ld e, a
        ld d, 0
        ld hl, uiLapNames
        add hl, de
        ld a, (hl)
        inc hl
        ld h, (hl)
        ld l, a
        ld de, 1 * 256 + 23
        ld a, 7
        call UiPrint
@t1:
        xor a
        ld (uiTableIndex), a
@row:
        ld hl, uiLine                   ; 28 spaces
        ld de, uiLine + 1
        ld bc, 27
        ld (hl), ' '
        ldir
        ld a, (uiTableIndex)
        ld c, a
        add a, POSITION_NUMBER % 256      ; position (shared by ties)
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (hl)
        inc a
        ld de, uiLine
        call UiDecimal
        ld a, (uiTableIndex)
        add a, DRIVERS_IN_ORDER % 256
        ld l, a
        ld a, (hl)
        ld (uiTableDriver), a
        ld l, a                         ; name: driverNames + 12 * driver
        ld h, 0
        add hl, hl
        add hl, hl
        ld e, l
        ld d, h
        add hl, hl
        add hl, de
        ld de, driverNames
        add hl, de
        ld de, uiLine + 4
        ld bc, 12
        ldir
        ld a, (uiTableDriver)
        ld c, a
        ld a, (uiTableKind)
        cp 1
        jr z, @points
        cp 3
        jr z, @total
        ld de, uiLine + 20              ; best lap MM:SS.T
        ld h, DRV_PAGE / 256
        ld a, BEST_LAP_MINUTES % 256
        add a, c
        ld l, a
        ld a, (hl)
        call UiBcd
        ld a, ':'
        ld (de), a
        inc de
        ld a, BEST_LAP_SECONDS % 256
        add a, c
        ld l, a
        ld a, (hl)
        call UiBcd
        ld a, '.'
        ld (de), a
        inc de
        ld a, BEST_LAP_TENTHS % 256       ; hundredths: the tenths digit
        add a, c
        ld l, a
        ld a, (hl)
        rrca
        rrca
        rrca
        rrca
        and 15
        add a, '0'
        ld (de), a
        jr @print
@points:
        ld a, (uiTableIndex)            ; the first six places
        cp 6
        jr nc, @print
        ld e, a
        ld d, 0
        ld hl, uiPlacePoints
        add hl, de
        ld a, (hl)
        add a, '0'
        ld (uiLine + 26), a
        jr @print
@total:
        ld b, 0                         ; six BCD digits, leading zeros off
        ld hl, uiPoints + 2
        add hl, bc
        add hl, bc
        add hl, bc
        ld de, uiLine + 21
        ld b, 3
@d1:
        ld a, (hl)
        call UiBcd
        dec hl
        djnz @d1
        ld hl, uiLine + 21
        ld b, 5
@d2:
        ld a, (hl)
        cp '0'
        jr nz, @print
        ld (hl), ' '
        inc hl
        djnz @d2
@print:
        ld a, (uiTableIndex)            ; the band colour
        and 1
        ld e, a
        ld a, (uiTableKind)
        add a, a
        add a, e
        ld e, a
        ld d, 0
        ld hl, uiTableColours
        add hl, de
        ld c, (hl)
        ld a, (uiTableIndex)
        add a, 2
        ld d, a
        ld e, 2
        ld a, c
        ld hl, uiLine
        call UiPrint
        ld a, (uiTableIndex)            ; black gutters: columns 4-5, 18-21
        add a, 2
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, $5804
        add hl, de
        xor a
        ld (hl), a
        inc hl
        ld (hl), a
        ld de, 13
        add hl, de
        ld b, 4
@g1:
        ld (hl), a
        inc hl
        djnz @g1
        ld hl, uiTableIndex
        inc (hl)
        ld a, (hl)
        cp 20
        jp c, @row
        jp UiSpace

; UiDecimal: A = 0..29 as two characters (space for no tens) at DE
UiDecimal:
        ld b, ' '
@d1:
        cp 10
        jr c, @d2
        sub 10
        inc b
        bit 4, b
        jr nz, @d1
        ld b, '1'
        jr @d1
@d2:
        ld c, a
        ld a, b
        ld (de), a
        inc de
        ld a, c
        add a, '0'
        ld (de), a
        ret

; UiBcd: A = two BCD digits as characters at DE (DE += 2). Preserves BC, HL.
UiBcd:
        push af
        rrca
        rrca
        rrca
        rrca
        call @digit
        pop af
@digit:
        and 15
        add a, '0'
        ld (de), a
        inc de
        ret

; ---------------------------------------------------------------------------
; Screen and keyboard

; UiClear: black border and screen
UiClear:
        xor a
        out ($FE), a
        ld hl, $4000
        ld de, $4001
        ld bc, $1AFF
        ld (hl), a
        ldir
        ret

; UiTextList: HL = text list
UiTextList:
        ld a, (hl)
        or a
        ret z
        inc hl
        ld d, (hl)
        inc hl
        ld e, (hl)
        inc hl
        call UiPrint
        jr UiTextList

; UiPrint: A = attribute, D = character row, E = column, HL = text (0
; terminated) in the ROM font. Returns HL after the terminator.
UiPrint:
        ld (@col + 1), a
        ld a, d
        rrca
        rrca
        rrca
        ld b, a
        and $E0
        or e
        ld c, a
        ld a, b
        and 3
        or $58
        ld b, a                         ; BC = attribute address
        ld a, d
        and 7
        rrca
        rrca
        rrca
        or e
        ld e, a
        ld a, d
        and $18
        or $40
        ld d, a                         ; DE = screen address
@ch:
        ld a, (hl)
        inc hl
        or a
        ret z
        push hl
        push de
        push bc
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        ld bc, ROM_FONT
        add hl, bc
        ld b, 8
@gl:
        ld a, (hl)
        ld (de), a
        inc hl
        inc d
        djnz @gl
        pop bc
        pop de
        pop hl
@col:
        ld a, 0                         ; patched: attribute
        ld (bc), a
        inc bc
        inc e
        jr @ch

; ---------------------------------------------------------------------------
; Texts (user's version: menu_overlay.asm, track_menu.asm, ...)

uiTitleText:
        db $43, 3, 14, "R", 0
        db $46, 3, 15, "E", 0
        db $45, 3, 16, "V", 0
        db $44, 3, 17, "S", 0
        db 0
uiMainText:
        db $45, 8, 4, "PRESS", 0
        db $4D, 10, 4, " 1 ", 0
        db $46, 10, 11, "PRACTICE", 0
        db $4D, 12, 4, " 2 ", 0
        db $46, 12, 11, "COMPETITION", 0
        db $4D, 14, 4, " 3 ", 0
        db $46, 14, 11, "LOAD RESULTS", 0
        db $4D, 16, 4, " 4 ", 0
        db $46, 16, 11, "SAVE RESULTS", 0
        db $4D, 18, 4, " 5 ", 0
        db $46, 18, 11, "CLEAR RESULTS", 0
        db 0
uiShowText:
        db $4D, 20, 4, " 6 ", 0
        db $46, 20, 11, "SHOW RESULTS", 0
        db 0
uiPitsText:
        db $71, 3, 11, " THE PITS ", 0
        db $45, 8, 6, "SELECT WING SETTINGS", 0
        db $45, 10, 9, "RANGE 0 TO 40", 0
        db $47, 14, 11, "REAR", 0
        db $43, 14, 18, ">", 0
        db 0
uiFrontText:
        db $47, 16, 10, "FRONT", 0
        db $43, 16, 18, ">", 0
        db 0
uiSpaceText:
        db $45, 23, 5, "PRESS SPACE TO CONTINUE", 0
        db 0
uiChampText:
        db $56, 3, 4, "FORMULA 3 CHAMPIONSHIP", 0
        db 0
uiChoicesText:
        db $45, 10, 4, "PRESS", 0
        db $4D, 12, 4, " 1 ", 0
        db $4D, 14, 4, " 2 ", 0
        db $4D, 16, 4, " 3 ", 0
        db 0
uiClassText:
        db $45, 8, 4, "SELECT THE CLASS OF RACE", 0
        db $46, 12, 12
uiNovice:
        db "NOVICE", 0
        db $46, 14, 12
uiAmateur:
        db "AMATEUR", 0
        db $46, 16, 12
uiProfessional:
        db "PROFESSIONAL", 0
        db 0
uiDurationText:
        db $45, 8, 5, "QUALIFICATION DURATION", 0
        db $46, 12, 12, " 5 MINS", 0
        db $46, 14, 12, "10 MINS", 0
        db $46, 16, 12, "20 MINS", 0
        db 0
uiLapsText:
        db $45, 8, 5, "SELECT NUMBER OF LAPS", 0
        db $46, 12, 12
uiLaps5:
        db " 5 LAPS", 0
        db $46, 14, 12
uiLaps10:
        db "10 LAPS", 0
        db $46, 16, 12
uiLaps20:
        db "20 LAPS", 0
        db 0
uiNameText:
        db $45, 8, 6, "ENTER NAME OF DRIVER", 0
        db $43, 14, 8, ">", 0
        db $46, 15, 10, "------------", 0
        db 0
uiTrackText:
        db $45, 8, 4, "PRESS", 0
        db $4D, 10, 4, " 1 ", 0
        db $46, 10, 11
uiTrack1:
        db "BRANDS HATCH", 0
        db $4D, 12, 4, " 2 ", 0
        db $46, 12, 11
uiTrack2:
        db "DONINGTON PARK", 0
        db $4D, 14, 4, " 3 ", 0
        db $46, 14, 11
uiTrack3:
        db "NURBURGRING", 0
        db $4D, 16, 4, " 4 ", 0
        db $46, 16, 11
uiTrack4:
        db "OULTON PARK", 0
        db $4D, 18, 4, " 5 ", 0
        db $46, 18, 11
uiTrack5:
        db "SILVERSTONE", 0
        db $4D, 20, 4, " 6 ", 0
        db $46, 20, 11
uiTrack6:
        db "SNETTERTON", 0
        db 0
uiStarText:     db "* ", 0
uiLoadText:
        db $45, 12, 7, "REWIND TRACKS TAPE", 0
        db $45, 14, 9, "AND PRESS PLAY", 0
        db 0
uiTapeErrorText:
        db "TAPE ERROR - REWIND TAPE", 0
uiResultsLoadText:
        db $45, 12, 6, "REWIND RESULTS TAPE", 0
        db $45, 14, 9, "AND PRESS PLAY", 0
        db 0
uiResultsSaveText:
        db $45, 12, 6, "START TAPE RECORDING", 0
        db 0
uiPleaseWaitText:
        db $45, 12, 10, "PLEASE WAIT", 0
        db 0
uiGridTitle:
        db $5F, 0, 9, "GRID POSITIONS", 0
        db 0
uiPointsTitle:
        db $56, 0, 13, "POINTS", 0
        db 0
uiBestTitle:
        db $5F, 0, 9, "BEST LAP TIMES", 0
        db 0
uiTotalTitle:
        db $4F, 0, 7, "ACCUMULATED POINTS", 0
        db 0

uiTrackNames:   dw uiTrack1, uiTrack2, uiTrack3, uiTrack4, uiTrack5, uiTrack6
uiClassNames:   dw uiNovice, uiAmateur, uiProfessional
uiLapNames:     dw uiLaps5, uiLaps10, uiLaps20
uiTableTitles:  dw uiGridTitle, uiPointsTitle, uiBestTitle, uiTotalTitle
uiTableColours: db $69, $7B, $72, $61, $69, $7B, $56, $79
uiPlacePoints:  db 9, 6, 4, 3, 2, 1
uiDurationValues: db $04, $09, $19      ; qualifyingTime (BBC timeFromOption)
uiLapValues:    db 5, 10, 20
uiResultsHeader:                        ; CODE "REVSRESULT", the record
        db 3, "REVSRESULT"
        dw UI_RECORD_SIZE, uiRecord, $8000

; ---------------------------------------------------------------------------
; State (kept while driving with the rest of the overlay)

uiRecord:                               ; the results record (76 bytes)
        db "RC", 1
uiNameLength:   db 0
uiDriverName:   ds 12, ' '
uiPoints:       ds 60                   ; 20 x 3 BCD (low, middle, high) by
uiRecordEnd:                            ; driver identity (19: the player)
UI_RECORD_SIZE  EQU uiRecordEnd - uiRecord
        ASSERT UI_RECORD_SIZE == 76
uiResultsValid: db 0                    ; 6 SHOW RESULTS available
uiClass:        db 0
uiDuration:     db $04
uiLapsChoice:   db 0                    ; 0-2: 5, 10, 20 laps
uiRearWing:     db 20
uiFrontWing:    db 20
uiCachedTrack:  db '5'                  ; the track in memory ('1'-'6'), 0: none
uiChoice:       db 0
uiTrackName:    dw 0
uiTableKind:    db 0
uiTableIndex:   db 0
uiTableDriver:  db 0
uiInputRow:     db 0
uiInputLength:  db 0
uiInputValue:   db 0
uiInputText:    db "  ", 0
uiLine:         ds 28, ' '              ; table row / name buffer
                db 0
uiHeader:       ds 17                   ; tape header read
