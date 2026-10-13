; Memory map
;
; $4000-$5AFF  screen; while driving, character rows 2-9 (pixel rows 16-79,
;              "hidden sky", attributes ink = paper) keep 2 KiB of the UI
;              overlay
; $5B00-$5EFF  the last KiB of the UI overlay while driving (the BASIC
;              area and system variables are not used after start-up; tape
;              transfers use the ROM routines without SA/LD-RET)
; $5F00-$5FFF  free, kept in every phase (championship data)
; $6000-$7FFF  contended: cold code and data (loaded)
; $8000-$BFFF  uncontended: hot code and variables
; $C000-$C7FF  the track (one at a time: Silverstone is loaded with the
;              game, a track loaded from tape replaces it)
; $C800-$FD5F  uncontended: page-aligned tables and buffers, more hot code
;              ($F800-$FBFF), object line buffers ($FC00), stack (below $FD60)
; $E200-$EDFF  view buffer and edge pages while driving; the UI overlay runs
;              here between the sessions (loaded here with the game)
; $E180-$E1FF  UI keyboard routines (resident, loaded)
; $FD60-$FFF3  track code of an extra track (loaded with the track)
; $FFF4-$FFFF  IM2: JP Isr at $FFF4, the JR of the ROM vector at $FFFF

LOAD_START      EQU $6000       ; first byte loaded from tape
CODE_START      EQU $8000       ; entry point / hot code
STACK_TOP       EQU $FD60       ; stack below the track code (deepest use
                                ; while driving: 34 bytes)

; Track code of an extra track (src/trackcode.asm, loaded with the track):
; $FD60-$FFF3. The IM2 vector comes from the ROM: I = $39, where the ROM
; holds $FF bytes, so the vector is $FFFF: JR (to $FFF4, the ROM has $F3 at
; $0000) and JP Isr at $FFF4.
TRACKCODE       EQU STACK_TOP
TRACKCODE_END   EQU $FFF4
IM2_PAGE        EQU $39
IM2_JP          EQU $FFF4

; ---------------------------------------------------------------------------
; Page-aligned data (addresses fixed so that H selects a table, L the index)

TRACK           EQU $C000       ; 2 KiB track file (C64 layout, see track.asm)
SEG_LO          EQU $C800       ; track segment buffer, low bytes (C64 $0900)
SEG_HI          EQU $C900       ; track segment buffer, high bytes (C64 $0A00)
SEGDATA         EQU $CA00       ; segmentVector/Steering/Flags, stride 3 (C64 $8900)
VERGE_XLO       EQU $CB00       ; xVergeRightLo (0..39), xVergeLeftLo (40..79)
VERGE_XHI       EQU $CC00       ; xVergeRightHi (0..39), xVergeLeftHi (40..79)
VERGE_DATA      EQU $CD00       ; vergeDataRight (0..39), vergeDataLeft (40..79)
VERGE_Y         EQU $CE00       ; yVergeRight (0..39), yVergeLeft (40..79)
OBJ_PAGE        EQU $CF00       ; per-object arrays (24 entries)
CAR_PAGE        EQU $D000       ; per-driver arrays (20 entries)
PROJ_TABLES     EQU $D100       ; 16 pages copied from C64 $BC00-$CBFF
VIEW_BUF        EQU $E200       ; 80 rows x 32 bytes ($E200-$EBFF)
EDGE_PAGE1      EQU $EC00       ; per-line edge tables (render.asm)
EDGE_PAGE2      EQU $ED00
XCONV           EQU $EE00       ; 3 pages: yaw -> screen x
MASKS           EQU $F100       ; pixel masks
QSQ_LO          EQU $F200       ; quarter squares, low bytes (2 pages)
QSQ_HI          EQU $F400       ; high bytes (2 pages)
MASKX           EQU $F600       ; Compose boundary masks by x (gen_tables.py)
DRV_PAGE        EQU $F700       ; per-driver timing and points tables (vars.asm)
HOT2            EQU $F800       ; second hot code area (race.asm, object tables)
OBJ_LINE        EQU $FC00       ; object part line buffers, 2 x 32 bytes (objdraw.asm)

; ---------------------------------------------------------------------------
; UI overlay

UI_RUN          EQU VIEW_BUF    ; runs at $E200-$EDFF between the sessions
UI_LIMIT        EQU XCONV
UI_STORE        EQU $5B00       ; last KiB while driving ($5B00-$5EFF)
UI_TAPE_BUF     EQU UI_STORE    ; tape transfers while the UI runs
UI_KEYS         EQU PROJ_TABLES + $1080     ; after the projection tables
HIDDEN_ROW      EQU 2           ; hidden sky: character rows 2-9 (pixel rows
HIDDEN_ROWS     EQU 8           ; 16-79): 2 KiB of the overlay while driving
        ASSERT UI_LIMIT - UI_RUN == HIDDEN_ROWS * 256 + 1024
        ASSERT EDGE_PAGE2 + 256 == UI_LIMIT
