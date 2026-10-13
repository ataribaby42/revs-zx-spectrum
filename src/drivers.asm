; Drivers: speeds, order and positions (C64 versions)

; ---------------------------------------------------------------------------
; SetDriverSpeed: give driver setSpeedForDriver a new random speed relative
; to the class base speed, then move setSpeedForDriver to the next driver.
; Returns C = the new setSpeedForDriver.

SetDriverSpeed:
        call Random
        ld b, a                         ; bit 7 = sign of the speed offset
        and $7F
        ld e, 14
@f1:
        cp 5
        jr c, @f3
        sub 5
        dec e
        jr nz, @f1
        ld e, 7
@f2:
        cp 8
        jr c, @f3
        sub 8
        dec e
        jr nz, @f2
@f3:
        bit 7, b
        jr z, @f4
        neg
@f4:
        add a, a
        ld b, a
        ld a, (setSpeedForDriver)
        ld c, a
        add a, DRIVER_GRIDROW % 256
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, b
        sub (hl)
        ld (T), a
        ld b, a
        ld a, (raceClass)
        dec a
        jr z, @f5                       ; Amateur
        ld a, b
        jp m, @novice
        ccf                             ; Professional: 6502 ROL T with carry =
        ld hl, T                        ; no borrow, then ROR A (signed halve)
        rl (hl)
        rra
        jr @f5b
@novice:
        add a, a
        jr @f5b
@f5:
        ld a, b
@f5b:
        ld hl, baseSpeed
        add a, (hl)
        ld b, a
        ld a, DRIVER_SPEED % 256
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld (hl), b
        call GetPositionAhead
        ld a, c
        ld (setSpeedForDriver), a
        ret

; GetPositionAhead / GetPositionBehind: C = position, wrapping 0..19
GetPositionAhead:
        dec c
        ret p
        ld c, 19
        ret

GetPositionBehind:
        inc c
        ld a, c
        cp 20
        ret c
        ld c, 0
        ret

; ---------------------------------------------------------------------------
; SetPlayerPositions: currentPosition, positionAhead, positionBehind of
; currentPlayer in driversInOrder

SetPlayerPositions:
        ld a, (currentPlayer)
        ld hl, DRIVERS_IN_ORDER + 19
        ld c, 19
@p1:
        cp (hl)
        jr z, @p2
        dec hl
        dec c
        jp p, @p1
@p2:
        ld a, c
        ld (currentPosition), a
        call GetPositionBehind
        ld a, c
        ld (positionBehind), a
        ld a, (currentPosition)
        ld c, a
        call GetPositionAhead
        ld a, c
        ld (positionAhead), a
        ret

