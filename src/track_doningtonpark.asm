; Donington Park for the tracks tape: a module of the build (src/revs.lst)
; with two sections, the track file for the track slot and the track
; code for TRACKCODE (z80asm writes each to its own file).

        INCLUDE "memmap.asm"
        INCLUDE "tracklink.asm"

        SECTION track_doningtonpark
        org TRACK
        PHASE TRACK
        INCLUDE "trackdata_doningtonpark.asm"
        DEPHASE

        SECTION trackcode_doningtonpark
        org TRACKCODE
        PHASE TRACKCODE
        INCLUDE "trackconst_doningtonpark.asm"
        INCLUDE "trackcode.asm"
        DEPHASE
