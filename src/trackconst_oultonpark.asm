; Oulton Park: constants of the Z80 track code (src/trackcode.asm), imported
; from the C64 track code by tools/gen_trackcode.py

TC_SECTIONFROM  EQU TRACK + $605       ; C64 $5905
TC_YAWALO       EQU TRACK + $546       ; C64 $5846
TC_YAWLO        EQU TRACK + $0FA       ; C64 $53FA
TC_YAWAHI       EQU TRACK + $564       ; C64 $5864
TC_YAWHI        EQU TRACK + $0FB       ; C64 $53FB
TC_TSLOPE       EQU TRACK + $528       ; C64 $5828
TC_SLOPE        EQU TRACK + $0FC       ; C64 $53FC
TC_SUBCONFIG    EQU TRACK + $582       ; C64 $5882
TC_SUBSECTION   EQU TRACK + $0F8       ; C64 $53F8
TC_SUBSEG       EQU TRACK + $0FD       ; C64 $53FD
TC_YAWDLO       EQU TRACK + $228       ; C64 $5528
TC_YAWDHI       EQU TRACK + $128       ; C64 $5428
TC_SLOPED       EQU TRACK + $328       ; C64 $5628
TC_XCURVE       EQU TRACK + $4BF       ; C64 $57BF
TC_ZCURVE       EQU TRACK + $5BF       ; C64 $58BF
TC_WIDTH        EQU $80
TC_SUBSIZE      EQU TRACK + $428       ; C64 $5728
TC_SUBCOUNT     EQU TRACK + $0F9       ; C64 $53F9
TC_STEERING     EQU TRACK + $5A0       ; C64 $58A0
TC_SIGNZ        EQU TRACK + $462       ; C64 $5762
TC_SIGNY        EQU TRACK + $362       ; C64 $5662
TC_SIGNX        EQU TRACK + $262       ; C64 $5562
TC_SIGNDATA     EQU TRACK + $162       ; C64 $5462
TC_BRAKE        EQU $4B
TC_FIX          EQU $01
TC_ABSWIDTH     EQU $00
TC_SLOPEJUMP    EQU $01
TC_HAIRPIN      EQU $24
TC_HPTOP        EQU $04
TC_HPBOTTOM     EQU $0B
TC_HPTOP0       EQU $00
TC_HPBOTTOM0    EQU $03
