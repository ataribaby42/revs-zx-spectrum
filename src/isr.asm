; Interrupt mode 2 set-up and the 50 Hz interrupt handler
;
; The handler copies a finished view buffer to the screen at the start of
; the next TV frame (before the beam reaches the view), so the view never
; tears. The main loop sets viewReady after composing the buffer and must not
; touch the buffer again until the handler has cleared the flag.

SetupIM2:
        ld a, $C3                       ; JP Isr at $FFF4
        ld (IM2_JP), a
        ld hl, Isr
        ld (IM2_JP + 1), hl
        ld a, $18                       ; JR at $FFFF (offset $F3 = the ROM
        ld ($FFFF), a                   ; byte at $0000): to $FFF4
        ld a, IM2_PAGE
        ld i, a
        im 2
        ret

Isr:
        push af
        push bc
        push de
        push hl
        ld hl, frameCounter
        inc (hl)
        ld a, (viewReady)
        or a
        jr z, @done
        ld a, (viewCopyStart)
        call ViewCopyFrom
        xor a
        ld (viewReady), a
@done:
        call AnimateTyres
        call SoundTick
        pop hl
        pop de
        pop bc
        pop af
        ei
        reti

; AnimateTyres: move the tyre tread as the BBC does from its interrupt, at
; half its rate (as the user's version): tyreTravel += (playerSpeedHi + 48)
; / 2 (the 9-bit sum), flip the tread on overflow (if moving)
AnimateTyres:
        ld a, (playerSpeedHi)
        add a, 48
        rra
        ld hl, tyreTravel
        add a, (hl)
        ld (hl), a
        ret nc
        ld a, (playerMoving)
        or a
        ret z
        ld hl, tyreTab
        ld b, TYRE_BYTES
@t1:
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld a, (de)
        xor (hl)
        ld (de), a
        inc hl
        djnz @t1
        ret

; WaitView: wait until the previous view buffer has been shown
WaitView:
        ld a, (viewReady)
        or a
        ret z
        halt
        jr WaitView

frameCounter:   db 0
viewReady:      db 0
viewCopyStart:  db 0                    ; first view row to copy (rows above: sky)

        INCLUDE "viewcopy.asm"
