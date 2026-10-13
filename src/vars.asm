; Game variables
;
; Names follow the BBC Micro source (Mark Moxon's annotations) so that the
; code can be read side by side with the original; semantics follow the C64
; version. Single variables live here; arrays are page-aligned (memmap.asm).

; ---------------------------------------------------------------------------
; Track file layout (TRACK = C64 $5300)

trackSectionData        EQU TRACK + $000        ; +8*section: data
xTrackSectionIHi        EQU TRACK + $001
yTrackSectionIHi        EQU TRACK + $002
zTrackSectionIHi        EQU TRACK + $003
xTrackSectionOHi        EQU TRACK + $004
trackSectionTurn        EQU TRACK + $005
zTrackSectionOHi        EQU TRACK + $006
trackDriverSpeed        EQU TRACK + $007
xTrackSignVector        EQU TRACK + $0D0
zTrackSignVector        EQU TRACK + $0E0
yTrackSignVector        EQU TRACK + $0F0
xTrackSegmentI          EQU TRACK + $100        ; 256-entry segment vector tables
yTrackSegmentI          EQU TRACK + $200
zTrackSegmentI          EQU TRACK + $300
xTrackSegmentO          EQU TRACK + $400
zTrackSegmentO          EQU TRACK + $500
trackSectionFlag        EQU TRACK + $600        ; +8*section: flags
xTrackSectionILo        EQU TRACK + $601
yTrackSectionILo        EQU TRACK + $602
zTrackSectionILo        EQU TRACK + $603
xTrackSectionOLo        EQU TRACK + $604
trackSectionFrom        EQU TRACK + $605
zTrackSectionOLo        EQU TRACK + $606
trackSectionSize        EQU TRACK + $607
trackSteering           EQU TRACK + $6D0
trackSignData           EQU TRACK + $6EA
trackSectionCount       EQU TRACK + $6FA        ; number of sections * 8
trackVectorCount        EQU TRACK + $6FB
trackLength             EQU TRACK + $6FC        ; word
trackStartLine          EQU TRACK + $6FE        ; word
trackLapTimeSec         EQU TRACK + $700
trackLapTimeMin         EQU TRACK + $703
trackGearRatio          EQU TRACK + $706
trackGearPower          EQU TRACK + $70D
trackBaseSpeed          EQU TRACK + $714
trackStartPosition      EQU TRACK + $717
trackCarSpacing         EQU TRACK + $718
trackTimerAdjust        EQU TRACK + $719
trackRaceSlowdown       EQU TRACK + $71A
trackHalfwaySection     EQU TRACK + $728        ; C64 only: section*8 that sets pastHalfway

; ---------------------------------------------------------------------------
; Track segment buffer (SEG_LO/SEG_HI pages, index = segment*3 + axis)

xSegmentCoordI          EQU 0                   ; offsets within SEG_LO / SEG_HI
ySegmentCoordI          EQU 1
zSegmentCoordI          EQU 2
xSegmentCoordO          EQU $78
ySegmentCoordO          EQU $79
zSegmentCoordO          EQU $7A
xHelmetCoord            EQU $F4
xCoord1                 EQU $FA
xCoord2                 EQU $FD

segmentVector           EQU SEGDATA + 0         ; +segment*3
segmentSteering         EQU SEGDATA + 1
segmentFlags            EQU SEGDATA + 2

; ---------------------------------------------------------------------------
; Per-object arrays (24 entries) and per-driver arrays (20 entries).
; Address them with IX = OBJ_PAGE + OBJ_BIAS + index, (IX + field)
; and IY = CAR_PAGE + OBJ_BIAS + index, (IY + field).

OBJ_BIAS                EQU 128
objectStatus            EQU 0 - OBJ_BIAS        ; IX offsets
objYawAngleLo           EQU 24 - OBJ_BIAS
objYawAngleHi           EQU 48 - OBJ_BIAS
objectPitchAngle        EQU 72 - OBJ_BIAS
objectSize              EQU 96 - OBJ_BIAS
objTrackSection         EQU 120 - OBJ_BIAS
objSectionSegmt         EQU 144 - OBJ_BIAS
objectSegmentLo         EQU 168 - OBJ_BIAS
objectSegmentHi         EQU 192 - OBJ_BIAS

carStatus               EQU 0 - OBJ_BIAS        ; IY offsets
carSteering             EQU 20 - OBJ_BIAS
driverSpeed             EQU 40 - OBJ_BIAS
driversInOrder          EQU 60 - OBJ_BIAS
carSpeedHi              EQU 80 - OBJ_BIAS
carProgress             EQU 100 - OBJ_BIAS
carRacingLine           EQU 120 - OBJ_BIAS
carSectionSpeed         EQU 140 - OBJ_BIAS
carSpeedLo              EQU 160 - OBJ_BIAS
driverGridRow           EQU 180 - OBJ_BIAS
driverLapNumber         EQU 200 - OBJ_BIAS
totalRaceMinutes        EQU 220 - OBJ_BIAS

; Absolute addresses of the arrays (for whole-array loops and the test harness)
OBJ_STATUS              EQU OBJ_PAGE + OBJ_BIAS + objectStatus
OBJ_YAWLO               EQU OBJ_PAGE + OBJ_BIAS + objYawAngleLo
OBJ_YAWHI               EQU OBJ_PAGE + OBJ_BIAS + objYawAngleHi
OBJ_PITCH               EQU OBJ_PAGE + OBJ_BIAS + objectPitchAngle
OBJ_SIZE                EQU OBJ_PAGE + OBJ_BIAS + objectSize
OBJ_SECTION             EQU OBJ_PAGE + OBJ_BIAS + objTrackSection
OBJ_SEGMT               EQU OBJ_PAGE + OBJ_BIAS + objSectionSegmt
OBJ_SEGLO               EQU OBJ_PAGE + OBJ_BIAS + objectSegmentLo
OBJ_SEGHI               EQU OBJ_PAGE + OBJ_BIAS + objectSegmentHi
CAR_STATUS              EQU CAR_PAGE + OBJ_BIAS + carStatus
CAR_STEERING            EQU CAR_PAGE + OBJ_BIAS + carSteering
DRIVER_SPEED            EQU CAR_PAGE + OBJ_BIAS + driverSpeed
DRIVERS_IN_ORDER        EQU CAR_PAGE + OBJ_BIAS + driversInOrder
CAR_SPEEDHI             EQU CAR_PAGE + OBJ_BIAS + carSpeedHi
CAR_PROGRESS            EQU CAR_PAGE + OBJ_BIAS + carProgress
CAR_RACINGLINE          EQU CAR_PAGE + OBJ_BIAS + carRacingLine
CAR_SECTIONSPEED        EQU CAR_PAGE + OBJ_BIAS + carSectionSpeed
CAR_SPEEDLO             EQU CAR_PAGE + OBJ_BIAS + carSpeedLo
DRIVER_GRIDROW          EQU CAR_PAGE + OBJ_BIAS + driverGridRow
DRIVER_LAPNUMBER        EQU CAR_PAGE + OBJ_BIAS + driverLapNumber
TOTAL_RACE_MINUTES      EQU CAR_PAGE + OBJ_BIAS + totalRaceMinutes

; Per-driver timing and points tables (DRV_PAGE, same bias). Times and points
; are BCD. The clock entries follow the 20 best-lap entries as on the BBC
; (index 20 = clock, 21 = lap timer).
bestLapTenths           EQU 0 - OBJ_BIAS
clockTenths             EQU 20 - OBJ_BIAS
lapTenths               EQU 21 - OBJ_BIAS
bestLapSeconds          EQU 24 - OBJ_BIAS
clockSeconds            EQU 44 - OBJ_BIAS
lapSeconds              EQU 45 - OBJ_BIAS
bestLapMinutes          EQU 48 - OBJ_BIAS
clockMinutes            EQU 68 - OBJ_BIAS
lapMinutes              EQU 69 - OBJ_BIAS
totalRaceTenths         EQU 72 - OBJ_BIAS
totalRaceSeconds        EQU 92 - OBJ_BIAS
totalPointsLo           EQU 112 - OBJ_BIAS
totalPointsHi           EQU 132 - OBJ_BIAS
totalPointsTop          EQU 152 - OBJ_BIAS
driversInOrder2         EQU 172 - OBJ_BIAS

DRV_BASE                EQU DRV_PAGE + OBJ_BIAS
BEST_LAP_TENTHS         EQU DRV_BASE + bestLapTenths
CLOCK_TENTHS            EQU DRV_BASE + clockTenths
BEST_LAP_SECONDS        EQU DRV_BASE + bestLapSeconds
CLOCK_SECONDS           EQU DRV_BASE + clockSeconds
BEST_LAP_MINUTES        EQU DRV_BASE + bestLapMinutes
CLOCK_MINUTES           EQU DRV_BASE + clockMinutes
TOTAL_RACE_TENTHS       EQU DRV_BASE + totalRaceTenths
TOTAL_RACE_SECONDS      EQU DRV_BASE + totalRaceSeconds
TOTAL_POINTS_LO         EQU DRV_BASE + totalPointsLo
TOTAL_POINTS_HI         EQU DRV_BASE + totalPointsHi
TOTAL_POINTS_TOP        EQU DRV_BASE + totalPointsTop
DRIVERS_IN_ORDER2       EQU DRV_BASE + driversInOrder2
POSITION_NUMBER         EQU CAR_STATUS          ; shares carStatus, as on the BBC/C64

; Three-axis vector used by GetSegmentVector / AddVectors / HalveCoordinate.
; BBC keeps the low bytes in T,U,V and the high bytes in SS,TT,UU.
vecX:                   dw 0
vecY:                   dw 0
vecZ:                   dw 0

; Race set-up (BBC $8xxx workspace)
raceClass:              db 0            ; 0 Novice, 1 Amateur, 2 Professional
qualifyingTime:         db 0            ; bit 7 set: race, else qualifying minutes
baseSpeed:              db 0            ; trackBaseSpeed for the race class
sectionSteering:                        ; per section: bit 7 flag, bits 0-6 steering
        REPT 10                         ; (up to 29 sections + the one after the
        db 0, 0, $FF, $FF               ; last, which GetSegmentSteering reads:
        ENDR                            ; initial C64 RAM $8520-$8547)
