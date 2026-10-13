; The main program symbols that the track code (src/trackcode.asm, in the
; track modules src/track_<track>.asm) uses: defined in main.asm (the
; patched places as aliases of their local labels), external in the track
; modules.

        GLOBAL BuildEdges, GetTrackSegment, Multiply8x8, MultiplyHeight
        GLOBAL U, UpdateCurveVector, UpdateVectorNumber, W
        GLOBAL directionFacing, frontSegmentIndex, horizonLine, horizonListIndex
        GLOBAL horizonTrackWidth, objPartTab, playerSpeedHi, segmentListPointer
        GLOBAL segmentListRight, thisSectionFlags, thisVectorNumber, trackSignData
        GLOBAL trackSteering, xTrackSignVector, yTrackSignVector, zTrackSignVector
        GLOBAL ApplyElevation_tcSlope, BuildCarObjects_tcHeightCap, BuildRoadSign_tcSignHi, BuildRoadSign_tcSignLo
        GLOBAL BuildRoadSign_tcSignX, BuildRoadSign_tcSignY, BuildRoadSign_tcSignZ, DrawObject_tcCutoff
        GLOBAL GetFirstSegment_tcSite, GetSectionAngles_gsec3, GetSectionAngles_tcHorizon, GetSectionAngles_tcSkip
        GLOBAL GetSectionCoords_tcSite, GetSectionSteering_tcSteering, GetTrackAndMarkers_t3b, GetTrackAndMarkers_tcTail
        GLOBAL GetTrackSegment_tcSite, MainDrivingLoop_tcEdges, ProcessOvertaking_tcBrake, TurnPlayerAround_tcSite
