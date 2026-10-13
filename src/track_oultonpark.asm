; Oulton Park for the tracks tape: a module of the build (src/revs.lst)
; with two sections, the track file for the track slot and the track
; code for TRACKCODE (z80asm writes each to its own file).

        INCLUDE "memmap.asm"
        INCLUDE "tracklink.asm"

        SECTION track_oultonpark
        org TRACK
        PHASE TRACK
        INCLUDE "trackdata_oultonpark.asm"
        DEPHASE

        SECTION trackcode_oultonpark
        org TRACKCODE
        PHASE TRACKCODE
        INCLUDE "trackconst_oultonpark.asm"
        INCLUDE "trackcode.asm"
        DEPHASE
