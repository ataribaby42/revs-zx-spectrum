; Revs for the ZX Spectrum 48K - main file
; Assembled with z88dk z80asm (build.bat): the program is one block from
; LOAD_START, its parts at fixed addresses in ascending order (PHASE: the
; labels are absolute addresses, padding between the parts with ds)

        INCLUDE "memmap.asm"
        INCLUDE "tracklink.asm"         ; symbols of the track code modules
        INCLUDE "macros.asm"

        org LOAD_START
        PHASE LOAD_START
        jp Entry                        ; (a snapshot of the program starts here)
        INCLUDE "screen.asm"

; ---------------------------------------------------------------------------
; Code that runs once per session (contended memory below $8000)

COLD_CODE:
        INCLUDE "setup.asm"
        INCLUDE "game.asm"
        INCLUDE "debug.asm"
        INCLUDE "hud.asm"
        INCLUDE "controls.asm"
COLD_END:
        ASSERT COLD_END <= CODE_START
        ds CODE_START - $

; ---------------------------------------------------------------------------
; Hot code (uncontended)

Entry:
        di
        ld sp, STACK_TOP
        xor a
        out (254), a
        call SetupIM2
        call InitScreen
        ei
        jp DebugStart

        INCLUDE "vars.asm"
        INCLUDE "isr.asm"
        INCLUDE "track.asm"
        INCLUDE "proj.asm"
        INCLUDE "proj_code.asm"
        INCLUDE "verges.asm"
        INCLUDE "workspace.asm"
        INCLUDE "laps.asm"
        INCLUDE "math.asm"
        INCLUDE "render.asm"
        INCLUDE "raster.asm"
        INCLUDE "compose.asm"
        INCLUDE "physics.asm"
        INCLUDE "physics2.asm"
        INCLUDE "keys.asm"
        INCLUDE "player.asm"
        INCLUDE "drivers.asm"
        INCLUDE "ai.asm"
        INCLUDE "objects.asm"
        INCLUDE "objdraw.asm"

CODE_END:
        ASSERT CODE_END <= TRACK
        ds TRACK - $

; ---------------------------------------------------------------------------
; Page-aligned data

        INCLUDE "trackdata_silverstone.asm"   ; (the track in memory at the start)
        ASSERT $ <= PROJ_TABLES
        ds PROJ_TABLES - $
        INCLUDE "projdata.asm"
PROJ_END:

; ---------------------------------------------------------------------------
; UI overlay (game flow, menus): runs at UI_RUN between the sessions, kept
; in the hidden sky and at UI_STORE while driving (see memmap.asm)

        ASSERT PROJ_END <= UI_KEYS
        ds UI_KEYS - $
        INCLUDE "uikeys.asm"
UI_KEYS_END:
        ASSERT UI_KEYS_END <= VIEW_BUF && VIEW_BUF == UI_RUN
        ds UI_RUN - $
        INCLUDE "ui.asm"
UI_END:
        ASSERT UI_END <= UI_LIMIT && UI_LIMIT <= XCONV

; ---------------------------------------------------------------------------
; Page-aligned tables

        ds XCONV - $
        INCLUDE "xconv.asm"
        ASSERT $ <= MASKS
        ds MASKS - $
        INCLUDE "masks.asm"
HOT3:                                   ; hot code in the rest of the masks page
        INCLUDE "sound.asm"
HOT3_END:
        ASSERT $ <= QSQ_LO
        ds QSQ_LO - $
        INCLUDE "qsq.asm"
        ASSERT $ <= MASKX
        ds MASKX - $
        INCLUDE "maskx.asm"

; ---------------------------------------------------------------------------
; Second hot code area (uncontended, loaded)

        ASSERT $ <= HOT2
        ds HOT2 - $
        INCLUDE "objdata.asm"           ; h13Tab first (page aligned)
        INCLUDE "race.asm"
HOT2_END:
        ASSERT HOT2_END <= OBJ_LINE

        ASSERT HOT2_END <= EDGEMASK
        ds EDGEMASK - $                 ; masks in the object line page
        db $C0, $60, $30, $18, $0C, $06, $03, $01
        ASSERT $ == RMASK
        db $FF, $7F, $3F, $1F, $0F, $07, $03, $01
        ASSERT $ == LMASK
        db $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF
DATA_END:

; ---------------------------------------------------------------------------
; The places in the main program that the track code patches (tracklink.asm)

        DEFC ApplyElevation_tcSlope = ApplyElevation@tcSlope
        DEFC BuildCarObjects_tcHeightCap = BuildCarObjects@tcHeightCap
        DEFC BuildRoadSign_tcSignHi = BuildRoadSign@tcSignHi
        DEFC BuildRoadSign_tcSignLo = BuildRoadSign@tcSignLo
        DEFC BuildRoadSign_tcSignX = BuildRoadSign@tcSignX
        DEFC BuildRoadSign_tcSignY = BuildRoadSign@tcSignY
        DEFC BuildRoadSign_tcSignZ = BuildRoadSign@tcSignZ
        DEFC DrawObject_tcCutoff = DrawObject@tcCutoff
        DEFC GetFirstSegment_tcSite = GetFirstSegment@tcSite
        DEFC GetSectionAngles_gsec3 = GetSectionAngles@gsec3
        DEFC GetSectionAngles_tcHorizon = GetSectionAngles@tcHorizon
        DEFC GetSectionAngles_tcSkip = GetSectionAngles@tcSkip
        DEFC GetSectionCoords_tcSite = GetSectionCoords@tcSite
        DEFC GetSectionSteering_tcSteering = GetSectionSteering@tcSteering
        DEFC GetTrackAndMarkers_t3b = GetTrackAndMarkers@t3b
        DEFC GetTrackAndMarkers_tcTail = GetTrackAndMarkers@tcTail
        DEFC GetTrackSegment_tcSite = GetTrackSegment@tcSite
        DEFC MainDrivingLoop_tcEdges = MainDrivingLoop@tcEdges
        DEFC ProcessOvertaking_tcBrake = ProcessOvertaking@tcBrake
        DEFC TurnPlayerAround_tcSite = TurnPlayerAround@tcSite

; Checks that need labels defined later in the program

        ASSERT (BEST_LAP_TENTHS + 21) / 256 == DRV_PAGE / 256   ; (hud.asm PrintLapUpdate)

        DEPHASE
