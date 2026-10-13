; The main driving loop and the switch between the UI overlay (ui.asm:
; game flow, menus, grid and results) and the driving screen

FRAME_HALVES    EQU 13                  ; one 0.13 s step = 6.5 TV frames

; ---------------------------------------------------------------------------

; ResetBestLapTimes: all best laps to 10:00.00
ResetBestLapTimes:
        ld c, 19
@r1:
        call ResetBestLapTime
        dec c
        jp p, @r1
        ret

ResetBestLapTime:
        ld h, DRV_PAGE / 256
        ld a, BEST_LAP_TENTHS % 256
        add a, c
        ld l, a
        ld (hl), 0
        add a, 24
        ld l, a
        ld (hl), 0
        add a, 24
        ld l, a
        ld (hl), $10
        ret

; HeadToTrack: A = raceStarted / raceStarting value. Called from the UI
; overlay, which InitDrivingScreen stores away (StoreUI); it is back in place
; (LoadUI) when this returns.
HeadToTrack:
        ld (raceStarted), a
        ld (raceStarting), a
        call MainDrivingLoop
StopDriving:
        xor a
        ld (engineStatus), a
        ld (playerMoving), a            ; (no tyre animation over the UI)
        call FlushSoundBuffers
        call WaitView                   ; the last view copy is done
        ; fall through

; ---------------------------------------------------------------------------
; UI overlay storage: while driving, the overlay area (UI_RUN to UI_LIMIT,
; 3 KiB) is kept in the hidden sky (character rows 2-9: of each pixel line
; the 192 bytes of rows 2-7 in the first screen third, then the 64 bytes of
; rows 8-9 in the second third) and the last KiB at UI_STORE.

LoadUI:                                 ; hidden sky, UI_STORE -> UI_RUN
        ld a, $EB                       ; (EX DE, HL)
        jr UiSwap
StoreUI:                                ; UI_RUN -> hidden sky, UI_STORE
        xor a                           ; (NOP)
        call UiSwap
        ld hl, EDGE_PAGE1               ; the edge tables start empty, as
        ld de, EDGE_PAGE1 + 1           ; when the game is loaded
        ld bc, 2 * 256 - 1
        ld (hl), 0
        ldir
        ret
UiSwap:
        ld (@x1), a
        ld (@x2), a
        ld hl, UI_RUN
        ld de, $4000 + HIDDEN_ROW * 32
@u1:
        ld bc, (8 - HIDDEN_ROW) * 32
        call @copy                      ; DE: $4n40 -> $4(n+1)00
        ld e, HIDDEN_ROW * 32
        ld a, d
        cp $48
        jr nz, @u1
        ld e, 0
@u2:
        ld bc, (HIDDEN_ROW + HIDDEN_ROWS - 8) * 32
        call @copy                      ; DE: $4n00 -> $4n40
        ld e, 0
        inc d
        ld a, d
        cp $50
        jr nz, @u2
        ld de, UI_STORE
        ld bc, UI_LIMIT - UI_RUN - HIDDEN_ROWS * 256
@copy:
@x1:    nop                             ; patched
        ldir
@x2:    nop                             ; patched
        ret

; ---------------------------------------------------------------------------
; Track code patches (the patch list at TRACKCODE: db length, dw address,
; new bytes, old bytes, ...; db 0): TcApply writes the new bytes (the C64
; track hook), TcUndo the old ones (before another track is loaded)

TcApply:
        xor a                           ; the new bytes
        jr TcPatch
TcUndo:
        ld a, 1                         ; the old bytes
TcPatch:
        ld (@mode + 1), a
        ld hl, (tcPatchList)
@p1:
        ld a, (hl)                      ; length
        inc hl
        or a
        ret z
        ld c, a
        ld b, 0
        ld e, (hl)
        inc hl
        ld d, (hl)                      ; DE = address
        inc hl
@mode:
        ld a, 0                         ; patched: mode
        or a
        jr z, @p2
        add hl, bc                      ; old: skip the new bytes
        ldir
        jr @p1
@p2:
        push bc
        ldir
        pop bc
        add hl, bc                      ; skip the old bytes
        jr @p1

; TcReset: back to the main program's own code (no track code)
TcReset:
        call TcUndo
        ld hl, TcNone
        ld (tcPatchList), hl
        ret

; TcLoaded: the track code has loaded at TRACKCODE: its patch list (pointed
; to by its first word) applies
TcLoaded:
        ld hl, (TRACKCODE)
        ld (tcPatchList), hl
        jr TcApply

tcPatchList:    dw TcNone               ; the patch list in effect
TcNone:         db 0

; ---------------------------------------------------------------------------
; MainDrivingLoop

MainDrivingLoop:
        call InitDrivingScreen
@main1:
        ld c, 0
        call ZeroTimer
@main2:
        call ResetVariables
@main3:
        call BuildPlayerCar
        call ScaleWingSettings
        ld a, (frameCounter)
        add a, a
        ld (paceTarget), a
@main5:
        ld a, SOUND_LIVE                ; (the driving sounds go on)
        ld (soundLive), a
        call ProcessTime
        call ShowStartingLights
        call ReadKeys
        call ControlKeys
        ld a, (sessionKey)
        or a
        jp nz, @session
@main6:
        call ProcessDrivingKeys
        call ClutchKey
        call UpdateDashboard
        call ApplyDrivingModel
        call GetTrackAndMarkers
        call MovePlayerOnTrack
        call MovePlayerSegment
        call UpdateLapTimers
        call WaitView
@tcEdges:                               ; (track code: HookFov first)
        call BuildEdges
        call CheckSurfaces
        call Compose
        call BuildRoadSign
        ld c, 23
        call DrawCarOrSign
        call DrawCornerMarkers
        call MoveAndDrawCars
        call UpdateMirrors
        call ProcessContact
        call CheckForCrash
        call StartLights
        call EndView
        ld a, 1
        ld (viewReady), a
        call FramePace
        ld a, (crashedIntoFence)
        or a
        jr z, @main11
        ld hl, crashedIntoFence         ; crashed: CRASHED over the HUD (as
        inc (hl)                        ; the user's version), pause, then
        ld hl, crashedText              ; restart
        call ShowNotice
        ld b, 100
@wait:
        halt
        djnz @wait
        call RedrawHud
@main8:
        ld a, (qualifyingTime)
        or a
        jp m, @main1                    ; practice
        ld a, (raceStarted)
        or a
        jp p, @main2                    ; qualifying: back to the start
        ld a, (raceClass)
        or a
        jp z, @main3                    ; Novice race: rejoin
        jr @main9
@main11:
        ld a, (leaveTrackTimer)
        or a
        jp z, @main5
        dec a
        jr z, @main9
        ld (leaveTrackTimer), a
        jp @main5
@main9:
        call FlushSoundBuffers
        ld a, (qualifyingTime)
        or a
        jp m, @main8
        ret                             ; HeadToTrack -> the UI finishes

; Caps Shift + 3: new game; + 2: end qualifying or retire from the race
; (not in practice); + 1: the pits, in practice or qualifying while the car
; stands, then the car starts again from its initial place (the session
; clock and best lap stay)
@session:
        bit 2, a
        jp nz, NewGame
        bit 1, a
        jr z, @pits
        ld a, (qualifyingTime)
        or a
        jp p, @main9
        jp @main6
@pits:
        ld a, (raceStarted)
        or a
        jp m, @main6
        ld a, (playerMoving)
        or a
        jp nz, @main6
        call StopDriving                ; and LoadUI
        call UiPits
        call InitDrivingScreen
        jp @main2

; NewGame: back to the main menu from driving
NewGame:
        call StopDriving
        jp UiNewGame

; FramePace: keep one main loop iteration at 6.5 TV frames (0.13 s), the
; C64 time step, so the game runs in real time when the frame is fast enough
FramePace:
        ld a, (paceTarget)
        add a, FRAME_HALVES
        ld (paceTarget), a
@f1:
        ld a, (frameCounter)
        add a, a
        ld hl, paceTarget
        sub (hl)
        jp p, @f2                       ; on time or late
        halt
        jr @f1
@f2:
        cp 2 * 7                        ; far behind: do not try to catch up
        ret c
        ld a, (frameCounter)
        add a, a
        ld (paceTarget), a
        ret

paceTarget:     db 0

crashedText:    db "CRASHED", 0
