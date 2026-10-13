; Race logic: starting lights, road signs, contact, crashes, finishing
; (C64 versions)

; ---------------------------------------------------------------------------
; ShowStartingLights: race start sequence. raceStarting counts down:
; $80 = waiting for the engine, $D7..$B6 lights off, $B5..$A0 blue, then a
; random wait, 40..1 green, 0 = race running. (C64 constants; the BBC uses
; 240, 192 and a 63-iteration random wait.) The colours are the BBC's, as in
; the user's ZX version.

LIGHTS_OFF      EQU 0
LIGHTS_BLUE     EQU 1
LIGHTS_GREEN    EQU 2

ShowStartingLights:
        ld a, (raceStarted)
        or a
        ret p
        ld a, (raceStarting)
        ld c, a
        or a
        ret z
        jp p, @star2
        cp $80
        jr nz, @star2
        ld a, (engineStatus)
        or a
        jp p, @star1
        ld c, $D7
@star1:
        ld a, LIGHTS_OFF
        jr @star6
@star2:
        ld a, c
        cp $A0
        jr z, @star4
        dec c
        jp p, @star5
        ld a, c
        cp $B6
        jr nc, @star1
@star3:
        ld a, LIGHTS_BLUE
        jr @star6
@star4:
        ld a, (mainLoopCounterLo)
        and $1F
        jr nz, @star3
        ld c, $28
@star5:
        ld a, LIGHTS_GREEN
@star6:
        ld b, a
        ld a, c
        ld (raceStarting), a
        ld a, b
        jp DrawStartingLights

; ---------------------------------------------------------------------------
; BuildRoadSign: project the road sign for the player's current section
; (or the next sign once it has been passed) into object 23

BuildRoadSign:
        ld a, (currentPlayer)
        add a, OBJ_SECTION % 256
        ld l, a
        ld h, OBJ_SECTION / 256
        ld l, (hl)
        ld h, trackSectionData / 256
        ld a, (hl)
        rrca
        rrca
        rrca
        rrca
        and $0F
        ld (thisSignNumber), a
        ld hl, previousSignNumber
        cp (hl)
        jr nz, @sign1
        inc a                           ; already passed: the next sign
        and $0F
@sign1:
        ld c, a                         ; C = sign number
        ld a, 2
        ld (W), a
@tcSignZ:                               ; (track code: the track's tables)
        ld hl, zTrackSignVector         ; sign base = player - vector / 2^n
        call @vector
        ld b, 2
        call AddScaledVector
        ld de, (playerCoordZ + 1)
        call @base
        ld (roadSignCoordZ), hl
@tcSignY:
        ld hl, yTrackSignVector
        call @vector
        ld b, 4
        call AddScaledVector
        ld de, (playerCoordY + 1)
        call @base
        ld (roadSignCoordY), hl
@tcSignX:
        ld hl, xTrackSignVector
        call @vector
        ld b, 2
        call AddScaledVector
        ld de, (playerCoordX + 1)
        call @base
        ld (roadSignCoordX), hl
@tcSignLo:
        ld a, trackSignData % 256
        add a, c
        ld l, a
@tcSignHi:
        ld h, trackSignData / 256
        ld a, (hl)
        and 7
        add a, 7
        ld (objectType), a
        ld a, (hl)
        and $F8
        ld b, a
        ld c, xCoord2
        call GetSectionCoord
        call UseSignReference
        ld c, xCoord2
        call GetObjYawAngle
        ld a, (II)
        ld (OBJ_YAWLO + 23), a
        ld a, (JJ)
        ld (OBJ_YAWHI + 23), a
        ld hl, playerYawAngleHi
        sub (hl)
        call Abs8
        cp $40
        jr c, @sign2
        ld b, a
        ld a, (thisSignNumber)          ; behind us: move on to the next
        ld (previousSignNumber), a
        ld a, b
@sign2:
        ld b, $25
        cp $6E
        jr c, @sign3
        ld b, $50
@sign3:
        ld a, 23
        ld (colourScheme), a
        call CheckForContactB
        ld c, xCoord2
        call GetObjPitchAngle
        push af
        call UsePlayerReference
        pop af
        jp SetObjectDetails

@vector:                                ; A = vector entry C of table HL
        ld a, l
        add a, c
        ld l, a
        ld a, (hl)
        ret
@base:                                  ; HL = DE - (U T)
        ex de, hl
        ld a, (T)
        ld e, a
        ld a, (U)
        ld d, a
        or a
        sbc hl, de
        ret

; AddScaledVector: (U T) = signed A * 256 / 2^B (BBC edgePixel = V)
AddScaledVector:
        ld h, a
        ld l, 0
        ld e, l
        or a
        jp p, @a1
        dec e
@a1:
        srl e
        rr h
        rr l
        djnz @a1
        ld a, e
        ld (V), a
        ld a, l
        ld (T), a
        ld a, h
        ld (U), a
        ld hl, W
        dec (hl)
        ret

; ---------------------------------------------------------------------------
; ProcessContact: the player has touched car collisionDriver: push it off
; the track if hit hard (race only), adjust its speed and spin the player

ProcessContact:
        ld a, (processContact)
        or a
        ret z
        xor a
        ld (processContact), a
        ld hl, V
        scf
        rr (hl)
        ld a, (objectDistanceLo)
        ld b, a
        ld a, $25
        sub b
        jr nc, @cont1
        ld a, 5
@cont1:
        add a, a
        ld (U), a
        ld b, a
        ld a, (collisionDriver)
        ld c, a
        ld a, b
        cp $28
        jr c, @cont2
        ld a, (raceStarted)
        or a
        call m, PushCarOffTrack
@cont2:
        ld a, OBJ_YAWHI % 256
        add a, c
        ld l, a
        ld h, OBJ_YAWHI / 256
        ld a, (hl)
        ld hl, playerYawAngleHi
        sub (hl)
        add a, a
        add a, a
        push af                         ; sign: which side the car is on
        ld a, (currentPlayer)
        add a, CAR_SPEEDHI % 256
        ld l, a
        ld h, CAR_PAGE / 256
        ld e, (hl)                      ; player speed
        ld a, c
        cp 20
        ld a, e
        jr nc, @cont4
        ld a, CAR_SPEEDHI % 256
        add a, c
        ld l, a
        ld a, e
        cp (hl)
        jr c, @c3
        add a, 12                       ; the car is pushed along
        ld (hl), a
        jr @cont4
@c3:
        ld a, (hl)
@cont4:
        call Multiply8x8
        cp $10
        jr c, @c5
        ld a, $10
@c5:
        ld b, a
        pop af
        ld a, b
        call m, Negate16
        ; fall through

; SquealTyres: spinYawAngleTop = A, squeal both tyres
SquealTyres:
        ld (spinYawAngleTop), a
        ld a, $80
        ld (tyreSqueal), a
        ld (tyreSqueal + 1), a
        ld a, 4
        jp MakeSound

; PushCarOffTrack: car C leaves the race
PushCarOffTrack:
        ld a, c
        cp 20
        ret nc
        CAR_INDEX
        ld a, (iy + carRacingLine)
        and $7F
        or $45
        ld (iy + carSteering), a
        ld (iy + carStatus), $91
        ; fall through

; ClearTotalRaceTime: car C has retired (no race time if it has not finished)
ClearTotalRaceTime:
        ld a, OBJ_STATUS % 256
        add a, c
        ld l, a
        ld h, OBJ_STATUS / 256
        ld (hl), $C0
        ld a, DRIVER_LAPNUMBER % 256
        add a, c
        ld l, a
        ld h, CAR_PAGE / 256
        ld a, (numberOfLaps)
        cp (hl)
        ret c
        ld a, TOTAL_RACE_MINUTES % 256
        add a, c
        ld l, a
        ld (hl), $C0
        ret

; ---------------------------------------------------------------------------
; CheckForCrash: hitting the fence at a steep angle stops the car

CheckForCrash:
        ld a, (edgeDistanceHi)
        cp 2
        ret c
        ld a, (edgeYawAngle)
        call Abs8
        cp $60
        jr nc, @crash
        ld a, (spinYawAngleTop)
        or a
        ld a, 20
        jp p, SquealTyres
        neg
        jr SquealTyres
@crash:
        ld hl, crashedIntoFence
        dec (hl)
        ld hl, horizonLine
        inc (hl)
        call DrawFence
        call FlushSoundBuffers
        ld a, 4
        call MakeSound
        ld hl, physHi                   ; stop: speeds, forces (not
        ld b, 31                        ; firstLapStarted)
        xor a
@c1:
        ld (hl), a
        inc hl
        djnz @c1
        ld (engineStatus), a
        ld (yGravityDelta), a
        ld (soundRevCount), a
        ld (soundRevTarget), a
        ld (heightAboveTrack), a        ; no crane: the original lifts the car
        ld a, $1F                       ; to 127 (the user's choice)
        ld (oddsOfEngineStart), a
        ret

; DrawFence (C64 $3D5C): the fence we crash into, a diamond mesh repeating
; every 4 track lines (C64 $3D78: 4 mc pixels, here 8 pixels), black wires
; over the sky above the horizon and over the grass below it, in all rows
; of the view buffer. objTopRow = 0, so this frame's view copy takes all
; rows to the screen and the view is composed again afterwards. (The static
; sky band above the buffer stays: it is kept for hidden storage.)
DrawFence:
        xor a
        ld (playerMoving), a
        ld (objTopRow), a
        ld hl, VIEW_BUF
        ld c, VIEW_ROWS - 1             ; C = track line of the row
@f1:
        ld a, c                         ; the wires
        inc a
        rra
        ld a, %00110011
        jr nc, @f2
        bit 1, c
        ld a, %11000000
        jr z, @f2
        ld a, %00001100
@f2:
        ld b, a
        ld a, (horizonLine)
        cp c
        jr c, @f3                       ; above the horizon: sky
        jr z, @f3
        ld a, c                         ; below it: over the grass
        and 1
        add a, CP_PATGRASS
        ld e, a
        ld d, COMPOSE_PAGE / 256
        ld a, (de)
        or b
        ld b, a
@f3:
        ld a, b
        ld b, 32
@f4:
        ld (hl), a
        inc hl
        djnz @f4
        dec c
        jp p, @f1
        ret

