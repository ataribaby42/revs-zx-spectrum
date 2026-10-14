; 3D projection: yaw and pitch angles of a point relative to a reference
;
; Exact port of the C64 logarithmic projection ($1CDA GetObjYawAngle and
; $1F17 GetObjPitchAngle). The C64 replaces the BBC's divisions by table
; lookups: a 16-bit value is reduced to an 8-bit mantissa fraction M and an
; exponent code e (number of leading zeros; +8 when the high byte is zero),
; log(value) = LOG[M] - 1024*e, and the ratio of two values comes from an
; exponential table indexed by the log difference. The tables are copied
; from the C64 binary (tools/gen_c64data.py).

P_ANGLO         EQU PROJ_TABLES + $000  ; C64 $BC00 arctangent, low byte
P_ANGHI         EQU PROJ_TABLES + $100  ; C64 $BD00 arctangent, high byte
P_MANT          EQU PROJ_TABLES + $200  ; C64 $BE00 mantissa fraction of 1..255
P_EXPC          EQU PROJ_TABLES + $300  ; C64 $CB00 leading zeros of 1..255
P_LOGLO         EQU PROJ_TABLES + $400  ; C64 $CA00 log of 1.M, low byte
P_LOGHI         EQU PROJ_TABLES + $500  ; C64 $BF00 log of 1.M, high byte
P_LOG2LO        EQU PROJ_TABLES + $600  ; C64 $C800 log variant for heights
P_LOG2HI        EQU PROJ_TABLES + $700  ; C64 $C900
P_EXPTAB        EQU PROJ_TABLES + $800  ; C64 $C000-$C7FF ratio from log difference
P_SCALE         EQU PROJ_TABLES + $1000 ; C64 $6640-$66BF scale factor (128 bytes)

; Projection temporaries (own layout; BBC names in comments)
absDx:          dw 0            ; PP / SS
absDz:          dw 0            ; RR / UU
absDy:          dw 0            ; QQ / TT

