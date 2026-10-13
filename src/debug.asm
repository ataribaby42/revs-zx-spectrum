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
