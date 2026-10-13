; Extra controls (as in the user's original ZX version) and the C64 Revs+
; computer assisted steering (cold code)
;
;   N  sound on/off          M  cars in the wing mirrors on/off
;   C  CAS on/off            H  pause (press H again to resume)
;   X  hold the clutch (the gear-key clutch, without changing gear)
;   J  joystick: Sinclair joystick 1 (keys 6-0) or Kempston

casOn:          db 0                    ; $80: CAS on (C64 $9C43); starts off
mirrorsOn:      db $FF                  ; 0: no cars in the wing mirrors
keyLatchN:      db 0
keyLatchM:      db 0
keyLatchC:      db 0
keyLatchH:      db 0
keyLatchJ:      db 0
sessionKey:     db 0                    ; Caps Shift + 1/2/3 just pressed
sessionKeysOld: db 0

; KeyToggled: A = key code, HL = latch. NZ once per press.
KeyToggled:
        push hl
        call KeyDown
        pop hl
        jr z, @up
        ld a, (hl)
        ld (hl), 1
        xor 1
        ret
@up:
        ld (hl), 0
        ret

; ControlKeys: N, M, C, J and H (after ReadKeys); ends notices after 0.5 s.
; sessionKey: Caps Shift + 1/2/3 just pressed (bits 0-2), for the main loop.
ControlKeys:
        call NoticeTick
        ld a, (keyRows)                 ; Caps Shift
        rrca
        sbc a, a
        ld b, a
        ld a, (keyRows + 3)             ; 1, 2, 3
        and b
        and 7
        ld b, a
        ld a, (sessionKeysOld)
        cpl
        and b
        ld (sessionKey), a
        ld a, b
        ld (sessionKeysOld), a
        ld a, KEY_N
        ld hl, keyLatchN
        call KeyToggled
        jr z, @c1
        ld a, (soundOn)
        xor 1
        ld (soundOn), a
        ld hl, noticeSoundOn
        jr nz, @n1
        ld hl, noticeSoundOff
@n1:
        call ShowNotice
@c1:
        ld a, KEY_M
        ld hl, keyLatchM
        call KeyToggled
        jr z, @c2
        ld a, (mirrorsOn)
        cpl
        ld (mirrorsOn), a
        or a
        ld hl, noticeMirrorsOn
        jr nz, @n2
        ld hl, noticeMirrorsOff
@n2:
        call ShowNotice
@c2:
        ld a, KEY_C
        ld hl, keyLatchC
        call KeyToggled
        jr z, @c3
        ld a, (casOn)
        xor $80
        ld (casOn), a
        call DrawCasIndicator
@c3:
        ld a, KEY_J
        ld hl, keyLatchJ
        call KeyToggled
        jr z, @c4
        ld a, (joystickType)
        xor 1
        ld (joystickType), a
        ld hl, noticeSinclair
        jr z, @n3
        ld hl, noticeKempston
@n3:
        call ShowNotice
@c4:
        ld a, KEY_H
        ld hl, keyLatchH
        call KeyToggled
        ret z
        ; fall through

; PauseGame: everything stops (interrupts off: no view copies, sound or
; frame count) until H is released, pressed and released again
PauseGame:
        di
        xor a                           ; speaker off, black border
        out ($FE), a
        ld hl, pauseText
        call ShowNotice
        call @release
@p2:
        call ReadKeys
        ld a, KEY_H
        call KeyDown
        jr z, @p2
        call @release
        call RedrawHud
        ei
        ret
@release:
        call ReadKeys
        ld a, KEY_H
        call KeyDown
        jr nz, @release
        ret
pauseText:      db "PAUSED", 0
; notice texts as in the user's version
noticeSoundOn:  db "SOUND ON", 0
noticeSoundOff: db "Sound OFF", 0
noticeMirrorsOn: db "Mirrors ON", 0
noticeMirrorsOff: db "Mirrors OFF", 0
noticeSinclair: db "Sinclair", 0
noticeKempston: db "Kempston", 0

; ClutchKey: X holds the clutch as a held gear key does (after
; ProcessDrivingKeys)
ClutchKey:
        ld a, KEY_X
        call KeyDown
        ret z
        ld a, $FF
        ld (gearChangeKey), a
        ret

; ---------------------------------------------------------------------------
; AssistSteering: the C64 Revs+ CAS ($9D06-$9D88), for a held steering key
; while facing forwards. A = V = 2 (left) or 1 (right). The steering is
; pulled towards the verge 9 entries ahead on that side, with a gain that
; grows as the speed falls and a minimum from the segment's steering.
; Returns the steering change in (U T) (sign: bit 0 of T, as the original
; keyboard steering).

AssistSteering:
        ld c, 49                        ; left: xVergeLeft entry 9
        cp 2
        jr z, @a1
        ld c, 9                         ; right: xVergeRight entry 9
@a1:
        ld a, (steeringLo)              ; (W V) = signed steering
        ld (V), a
        rrca                            ; carry = bit 0 (left)
        ld a, (steeringHi)
        jr nc, @a2
        ld a, (V)
        neg
        ld (V), a
        ld a, 0
        ld hl, steeringHi
        sbc a, (hl)
@a2:
        add a, 1                        ; W = high + 1, or - 1 for the left
        ld b, a
        ld a, c
        cp 49
        ld a, b
        jr nz, @a3
        sub 2
@a3:
        ld (W), a
        ld h, VERGE_XLO / 256            ; (A T) = verge yaw - (W V)
        ld l, c
        ld a, (hl)
        ld hl, V
        sub (hl)
        ld (T), a
        ld h, VERGE_XHI / 256
        ld l, c
        ld a, (hl)
        ld hl, W
        sbc a, (hl)
        push af                         ; (sign)
        call Abs16
        ld (V), a                       ; (V T) = |difference|
        ld a, (playerSpeedHi)           ; gain U = 2 * max(0, 80 - speed) + 32
        ld b, a
        ld a, $50
        sub b
        jp p, @a4
        xor a
@a4:
        add a, a
        adc a, $20
        ld (U), a
        ld a, (playerSegmentIndex)      ; at least 16 * the segment steering
        add a, 0 + (SEGDATA + 1) % 256        ; amount (0..7, 3 if bit 6 is set)
        ld l, a
        ld h, SEGDATA / 256
        ld a, (hl)
        and $7F
        cp $40
        jr c, @a5
        ld a, 3
@a5:
        cp 8
        jr c, @a6
        ld a, 7
@a6:
        add a, a
        add a, a
        add a, a
        add a, a
        ld hl, U
        cp (hl)
        jr c, @a7
        ld (hl), a
@a7:
        call Multiply8x16               ; (U T) = U * (V T) / 256
        pop bc                          ; B bit 7: difference negative
        ld a, (U)
        bit 7, b
        call nz, Negate16
        ld (U), a
        ld a, (T)
        and $FE
        ld (T), a
        ld a, (steeringLo)
        rrca
        ret c
        call Negate16U
        ld (U), a
        ret
