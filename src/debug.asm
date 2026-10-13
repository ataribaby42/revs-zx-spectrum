; Development helpers (test entry points used by the Python harness)

; RenderTest: verges, edges, compose and copy to the screen
RenderTest:
        call GetTrackAndMarkers
RenderOnly:
        call BuildEdges
        call Compose
        ; fall through

; CopyViewSimple: copy the view buffer to screen rows VIEW_TOP.. (no cockpit)
CopyViewSimple:
        ld hl, VIEW_BUF
        ld b, VIEW_TOP
@row:
        push bc
        ld a, b
        call ScreenRowAddr              ; DE = screen address of row A
        ld bc, 32
        ldir
        pop bc
        inc b
        ld a, b
        cp VIEW_TOP + VIEW_ROWS
        jr nz, @row
        ret

; ---------------------------------------------------------------------------
; Fly-through demo: the camera follows the middle of the track

DemoInit:
        xor a
        ld (directionFacing), a
        ld (frontSegmentIndex), a
        ld (resetSectionList), a
        ld (turnCounter), a
        ld (newSectionFetched), a
        ld (markersToDraw), a
        ld (spinYawAngleHi), a
        ld (spinYawAngleTop), a
        ld (spinPitchAngle), a
        ld (playerPitchAngle), a
        ld a, 6
        ld (sectionListValid), a
        dec a
        ld (sectionListPointer), a
        ld a, 3
        ld (sectionListStart), a
        ld (sectionListSize), a
        ld a, 19
        ld (currentPlayer), a
        ld a, (trackSectionCount)
        sub 8
        ld (OBJ_SECTION + 23), a
        add a, trackSectionSize & $FF
        ld l, a
        ld h, trackSectionSize / 256
        ld a, (hl)
        dec a
        ld (OBJ_SEGMT + 23), a
        xor a
        ld (OBJ_SEGLO + 23), a
        ld (OBJ_SEGHI + 23), a
        ld b, 40
@g:
        push bc
        call GetTrackSegment
        pop bc
        djnz @g
        ret

DemoFrame:
        call GetTrackSegment
        call PlacePlayer
        call GetTrackAndMarkers
        call WaitView
        call BuildEdges
        call Compose
        ld a, 1
        ld (viewReady), a
        ret

; PlacePlayer: put the camera in the middle of the player's segment, looking
; at the middle of the segment three ahead
PlacePlayer:
        ld a, (playerSegmentIndex)
        ld c, a
        call MidPoint                   ; xCoord2 = middle of segment C
        ld hl, (SEG_LO + xCoord2)       ; x lo / y lo
        ld a, l
        ld (playerCoordX + 1), a
        ld a, (SEG_HI + xCoord2)
        ld (playerCoordX + 2), a
        ld a, (SEG_LO + xCoord2 + 2)
        ld (playerCoordZ + 1), a
        ld a, (SEG_HI + xCoord2 + 2)
        ld (playerCoordZ + 2), a
        ld a, (SEG_LO + xCoord2 + 1)    ; y + 172
        ld l, a
        ld a, (SEG_HI + xCoord2 + 1)
        ld h, a
        ld de, 172
        add hl, de
        ld a, l
        ld (playerCoordY + 1), a
        ld a, h
        ld (playerCoordY + 2), a
        ld a, (playerSegmentIndex)
        add a, 9
        cp 120
        jr c, @p1
        sub 120
@p1:
        ld c, a
        call MidPoint
        ld c, xCoord2
        call GetObjYawAngle
        ld a, (II)
        ld (playerYawAngleLo), a
        ld a, (JJ)
        ld (playerYawAngleHi), a
        ret

; MidPoint: xCoord2 = (inner + outer) / 2 of segment buffer entry C
MidPoint:
        ld b, 3
        ld a, xCoord2
        ld (@dst + 1), a
@m:
        ld l, c
        ld h, SEG_LO / 256
        ld e, (hl)
        inc h
        ld d, (hl)                      ; DE = inner
        ld a, l
        add a, xSegmentCoordO
        ld l, a
        ld a, (hl)
        dec h
        ld l, (hl)
        ld h, a                         ; HL = outer
        or a
        sbc hl, de
        sra h
        rr l
        add hl, de
        ex de, hl                       ; DE = middle
@dst:
        ld l, 0
        ld h, SEG_LO / 256
        ld (hl), e
        inc h
        ld (hl), d
        ld a, l
        inc a
        ld (@dst + 1), a
        inc c
        djnz @m
        ret

; ---------------------------------------------------------------------------
; DebugStart (from Entry): the menus, or for the test tools (debugStart set
; in the snapshot) Novice qualifying (1) or a race (2) at once, 5 minutes /
; 5 laps, the session ended through the UI (PLEASE WAIT, FinishRace)

debugStart:     db 0

DebugStart:
        ld a, (debugStart)
        or a
        jp z, UiNewGame
        push af
        xor a
        call InitialiseDrivers
        ld a, 4
        ld (qualifyingTime), a
        call ResetBestLapTimes
        ld a, 19
        ld (currentPlayer), a
        pop af
        dec a
        ld a, %00101000
        jr z, @d1
        xor a                           ; grid from the qualifying times
        call SortDrivers
        call UiAdjustClass
        ld a, 5
        ld (numberOfLaps), a
        ld a, %10000000
@d1:
        call HeadToTrack
        call UiFinish
        jp UiNewGame
