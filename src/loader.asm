; The BASIC loader of the game tape (the user's loader): the first two
; blocks of output/revs.tap, assembled as they lie on the tape (TAP: block
; length, flag, data, checksum), the header ("REVS", a program that starts
; at line 10) and the program:
;
;   10 BORDER 0: PAPER 0: INK 0: CLEAR VAL "24575": BORDER 0:
;      LOAD "" SCREEN$: POKE VAL "23739",VAL "111": LOAD "" CODE: CLS:
;      RANDOMIZE USR VAL "32768"
;
; CLEAR also clears the screen (in the black of PAPER 0: INK 0). The POKE
; points the output of channel S (CHANS + 5) at a RET in the ROM ($096F),
; so the CODE header's "Bytes: " message does not print over the loading
; screen; CLS then clears it in black before the game starts.

        INCLUDE "memmap.asm"
        ASSERT LOAD_START - 1 == 24575 && CODE_START == 32768   ; (the numbers above)

        SECTION loader
        org 0
        PHASE 0

PROG_LEN        EQU 92                  ; the program (line 10, checked below)
LINE_LEN        EQU PROG_LEN - 4        ; its text, from the first token to ENTER

; BASIC tokens
T_SCREEN        EQU $AA
T_CODE          EQU $AF
T_VAL           EQU $B0
T_USR           EQU $C0
T_INK           EQU $D9
T_PAPER         EQU $DA
T_BORDER        EQU $E7
T_LOAD          EQU $EF
T_POKE          EQU $F4
T_RANDOMIZE     EQU $F9
T_CLS           EQU $FB
T_CLEAR         EQU $FD

; TB b: a byte of a tape block, counted in its checksum (CHK)
CHK     DEFL 0
TB      MACRO b
        db b
CHK     DEFL CHK ^ (b)
        ENDM

; ZERO: the number 0 (its digit, then its hidden five-byte form)
ZERO    MACRO
        REPTI b, '0', $0E, 0, 0, 0, 0, 0
        TB b
        ENDR
        ENDM

; VALS "digits": VAL "digits"
VALS    MACRO s
        TB T_VAL
        TB '"'
        REPTC c, s
        TB c
        ENDR
        TB '"'
        ENDM

; ---------------------------------------------------------------------------
; The header

        dw 19                           ; (block length)
CHK     DEFL 0
        TB $00                          ; flag: header
        TB 0                            ; a program
        REPTC c, "REVS      "
        TB c
        ENDR
        TB PROG_LEN % 256               ; length
        TB PROG_LEN / 256
        TB 10                           ; LINE 10
        TB 0
        TB PROG_LEN % 256               ; the program alone (no variables)
        TB PROG_LEN / 256
        db CHK

; ---------------------------------------------------------------------------
; The program

        dw PROG_LEN + 2                 ; (block length)
CHK     DEFL 0
        TB $FF                          ; flag: data
ProgStart:
        TB 0                            ; line 10 (high byte first)
        TB 10
        TB LINE_LEN % 256
        TB LINE_LEN / 256
        TB T_BORDER                     ; BORDER 0:
        ZERO
        TB ':'
        TB T_PAPER                      ; PAPER 0:
        ZERO
        TB ':'
        TB T_INK                        ; INK 0:
        ZERO
        TB ':'
        TB T_CLEAR                      ; CLEAR VAL "24575":
        VALS "24575"
        TB ':'
        TB T_BORDER                     ; BORDER 0:
        ZERO
        TB ':'
        REPTI b, T_LOAD, '"', '"', ' ', T_SCREEN, ':'   ; LOAD "" SCREEN$:
        TB b
        ENDR
        TB T_POKE                       ; POKE VAL "23739",VAL "111":
        VALS "23739"
        TB ','
        VALS "111"
        TB ':'
        REPTI b, T_LOAD, '"', '"', ' ', T_CODE, ':'     ; LOAD "" CODE:
        TB b
        ENDR
        TB T_CLS                        ; CLS:
        TB ':'
        TB T_RANDOMIZE                  ; RANDOMIZE USR VAL "32768"
        TB T_USR
        VALS "32768"
        TB $0D                          ; ENTER
ProgEnd:
        ASSERT ProgEnd - ProgStart == PROG_LEN
        db CHK

        DEPHASE
