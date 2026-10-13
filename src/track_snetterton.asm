; Snetterton for the tracks tape: a module of the build (src/revs.lst)
; with two sections, the track file for the track slot and the track
; code for TRACKCODE (z80asm writes each to its own file).

        INCLUDE "memmap.asm"
        INCLUDE "tracklink.asm"

        SECTION track_snetterton
        org TRACK
        PHASE TRACK
        INCLUDE "trackdata_snetterton.asm"
        DEPHASE

        SECTION trackcode_snetterton
        org TRACKCODE
        PHASE TRACKCODE
        INCLUDE "trackconst_snetterton.asm"
        INCLUDE "trackcode.asm"
        DEPHASE
