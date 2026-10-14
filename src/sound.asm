; Beeper sound, played from the interrupt handler: the engine as a buzz of
; clicks per TV frame (more clicks and a shorter spacing at higher revs),
; random clicks for squealing tyres, for contact or crashes and (briefly) for
; a gear change, and pops for the starter.

SPEAKER         EQU %00010000           ; port $FE bit 4 (border stays black)

soundOn:        db 1                    ; toggled with N (controls.asm)
noiseFrames:    db 0                    ; frames of contact / crash / gear noise
starterFrames:  db 0                    ; frames of starter sound (set per step)
soundSeed:      db $5B
soundLive:      db 0                    ; frames left of the tyre, engine and
                                        ; starter sounds: every main loop
SOUND_LIVE      EQU 12                  ; iteration sets it, so they stop when
                                        ; the game stands (menus, pits, the
                                        ; CRASHED pause: only the impact sounds)

; SoundTick: called once per TV frame by the interrupt handler
SoundTick:
        ld a, (soundOn)
        or a
        ret z
        ld a, (noiseFrames)
        or a
        jr z, @s0
        dec a
        ld (noiseFrames), a
        ld b, 30
        call @noise
@s0:
        ld hl, soundLive
        ld a, (hl)
        or a
        ret z
        dec (hl)
@s1:
        ld a, (tyreSqueal)
        ld hl, tyreSqueal + 1
        or (hl)
        jp p, @engine
        ld b, 10
        call @noise
@engine:
        ld a, (engineStatus)
        or a
        jr z, @starter
        ld a, (revCount)                ; clicks = 1 + revs / 64
        ld c, a
        rlca
        rlca
        and 3
        inc a
        ld b, a
        ld a, c                         ; spacing shrinks with the revs:
        cp 128                          ; 21 - revs / 8 loops, 6 from 120
        ld a, 6                         ; on (128 and above too)
        jr nc, @sp
        ld a, c
        cpl
        rrca
        rrca
        rrca
        and $0F
        add a, 6
@sp:
        ld c, a
@e1:
        ld a, SPEAKER
        out ($FE), a
        ld a, c
@e2:
        dec a
        jr nz, @e2
        xor a
        out ($FE), a
        dec b
        ret z                           ; (no wait after the last click)
        ld a, c
@e3:
        dec a
        jr nz, @e3
        jp @e1
@starter:                               ; the starter, as the user's ZX
        ld hl, starterFrames            ; version: while ProcessEngineStart
        ld a, (hl)                      ; cranks and T is still held, sparse
        or a                            ; irregular pops (one frame in 8) of
        ret z                           ; three decaying pulses
        dec (hl)
        ld a, $FB                       ; T: read directly, so the cranking
        in a, ($FE)                     ; stops as soon as T is released
        and %00010000
        ret nz
        ld a, (soundSeed)
        add a, a
        jr nc, @st1
        xor $1D
@st1:
        ld (soundSeed), a
        ld c, a
        and 7
        ret nz
        ld a, c
        rrca
        and 63
        add a, 96
        ld c, a                         ; first pulse: 96-159 loops
        ld d, 3
@st2:
        ld a, SPEAKER
        out ($FE), a
        ld b, c
@st3:
        djnz @st3
        xor a
        out ($FE), a
        ld b, c
@st4:
        djnz @st4
        srl c
        dec d
        jr nz, @st2
        ret
@noise:                                 ; B random clicks
        ld a, (soundSeed)
        ld c, a
@n1:
        ld a, c                         ; 8-bit LFSR
        add a, a
        jr nc, @n2
        xor $1D
@n2:
        ld c, a
        and SPEAKER
        out ($FE), a
        ld a, c
        and $1F
        add a, 4
@n3:
        dec a
        jr nz, @n3
        djnz @n1
        ld a, c
        ld (soundSeed), a
        xor a
        out ($FE), a
        ret

; MakeSound: A = sound (BBC numbering: 4 = contact / crash)
MakeSound:
        cp 4
        ret nz
        ld a, 8
        ld (noiseFrames), a
        ret

FlushSoundBuffers:
        xor a
        ld (noiseFrames), a
        ret

