; Main workspace variables
;
; ZPAGE mirrors the BBC zero page $00-$8F byte for byte (names and aliases are
; generated from the BBC symbol table into build/gen/zp.asm), so routines that
; clear or reuse ranges of it behave exactly like the original. On the C64,
; playerMoving and thisSectionFlags moved to $90/$91; here they stay at
; offsets 0 and 1.
;
; BLK62 holds the variables that the original keeps in the 128-byte block at
; BBC $6280 (C64 $66C0), which ResetVariables zeroes. The order differs from
; the original where the Z80 code benefits (24-bit coordinates are stored
; lo, hi, top; the physics blocks are contiguous).

ZPAGE:                                  ; (the names first: zp.asm)
        INCLUDE "zp.asm"
        ds $90

; ---------------------------------------------------------------------------

BLK62:

; Player coordinates, 24-bit little endian (BBC xPlayerCoordLo/Hi/Top etc.).
; The projection uses the upper 16 bits (Hi, Top) as reference.
playerCoordX:           db 0, 0, 0
playerCoordY:           db 0, 0, 0
playerCoordZ:           db 0, 0, 0
roadSignCoordX:         db 0, 0         ; BBC xRoadSignCoordLo/Hi
roadSignCoordY:         db 0, 0
roadSignCoordZ:         db 0, 0
objectPalette:          ds 4
mirrorContents:         ds 6
markerListIndex:        ds 3
markerData:             ds 3
xMarkerLo:              ds 3
xMarkerHi:              ds 3
vergeEdgeRight:         ds 4

; Driving-model state
sinYawAngleLo:          db 0            ; index 0
cosYawAngleLo:          db 0            ; index 1
steeringLo:             db 0            ; index 2 (bit 0 = steering sign)
sinYawAngleHi:          db 0
cosYawAngleHi:          db 0
steeringHi:             db 0
tyreSqueal:             ds 2
wingSetting:            ds 2
wingForce:              ds 2
wingForce95:            ds 2

; The physics code indexes these blocks with offsets (physics.asm). The Hi and
; Top blocks are parallel 16-entry arrays: entry i of the Hi block is the low
; byte and entry i of the Top block the high byte of a 16-bit value (or the
; middle and top bytes of a 24-bit value whose low byte is in physLo).
physLo:
xPlayerSpeedLo:         db 0
zPlayerSpeedLo:         db 0
spinYawAngleLo:         db 0

physHi:
xPlayerSpeedHi:         db 0    ; 0
zPlayerSpeedHi:         db 0    ; 1
spinYawAngleHi:         db 0    ; 2
xAccelerationLo:        db 0    ; 3
zAccelerationLo:        db 0    ; 4
spinYawDeltaLo:         db 0    ; 5
xPlayerAccelLo:         db 0    ; 6
zPlayerAccelLo:         db 0    ; 7
xVelocityLo:            db 0    ; 8
zVelocityLo:            db 0    ; 9
xTyreForceNoseLo:       db 0    ; 10
xTyreForceRearLo:       db 0    ; 11
zTyreForceNoseLo:       db 0    ; 12
zTyreForceRearLo:       db 0    ; 13
xSteeringForceLo:       db 0    ; 14
mainLoopCounterHi:      db 0    ; 15

physTop:
xPlayerSpeedTop:        db 0
zPlayerSpeedTop:        db 0
spinYawAngleTop:        db 0
xAccelerationHi:        db 0
zAccelerationHi:        db 0
spinYawDeltaHi:         db 0
xPlayerAccelHi:         db 0
zPlayerAccelHi:         db 0
xVelocityHi:            db 0
zVelocityHi:            db 0
xTyreForceNoseHi:       db 0
xTyreForceRearHi:       db 0
zTyreForceNoseHi:       db 0
zTyreForceRearHi:       db 0
xSteeringForceHi:       db 0
firstLapStarted:        db 0

soundBuffer:            ds 6
liftFromTorque:         db 0
wingBalance:            db 0
playerSideways:         db 0
thisObjectType:         db 0
thisDriverNumber:       db 0
newSectionFetched:      db 0
crashedIntoFence:       db 0
irqCounter:             db 0
updateLapTimes:         db 0
previousSignNumber:     db 0
tyreTravel:             db 0
playerDrift:            db 0
horizonTrackWidth:      db 0
lowestTrackLine:        db 0
updateDriverInfo:       db 0
zTyreForceBoth:         db 0
BLK62_END:

; ---------------------------------------------------------------------------
; Variables outside the zeroed block

frontWingSetting:       db 20           ; set on the options screen
rearWingSetting:        db 20
leftSurface:            db 0            ; $FF when the left front tyre is on grass
rightSurface:           db 0
