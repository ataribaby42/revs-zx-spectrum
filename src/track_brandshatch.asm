; Brands Hatch for the tracks tape: a module of the build (src/revs.lst)
; with two sections, the track file for the track slot and the track
; code for TRACKCODE (z80asm writes each to its own file).

        INCLUDE "memmap.asm"
        INCLUDE "tracklink.asm"

        SECTION track_brandshatch
        org TRACK
        PHASE TRACK
        INCLUDE "trackdata_brandshatch.asm"
        DEPHASE

        SECTION trackcode_brandshatch
        org TRACKCODE
        PHASE TRACKCODE
        INCLUDE "trackconst_brandshatch.asm"
        INCLUDE "trackcode.asm"
        DEPHASE
