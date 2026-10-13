; Silverstone for the tracks tape: a module of the build (src/revs.lst)
; with two sections, the track file for the track slot and the track
; code for TRACKCODE (z80asm writes each to its own file).

        INCLUDE "memmap.asm"
        INCLUDE "tracklink.asm"

        SECTION track_silverstone
        org TRACK
        PHASE TRACK
        INCLUDE "trackdata_silverstone.asm"
        DEPHASE

        SECTION trackcode_silverstone
        org TRACKCODE
        PHASE TRACKCODE
        dw TRACKCODE + 2                ; no track code: an empty patch list
        db 0
        DEPHASE
