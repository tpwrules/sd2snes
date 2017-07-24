ORG $000000
FORCEPC $008000
print "Hook Bank Starting at: ", pc

hook:
    ; set native mode
    clc : xce
    ; set data bank
    phk : plb
    ; clear decimal flag
    cld
    ; disable interrupts
    ;sei

    %a8() : %i16()
    ; setup D
    ldx #$0000 : tcd
    ; setup temporary stack
    ldx #$01FF : txs

    ; setup PPU to generate a NMI
    ;;lda #$8F : sta $2100
    ; sta $2100
    ; lda #$00
    ; ldx #$2101
; -   sta $00,x
    ; inx
    ; cpx #$2133
    ; bne -

    ; lda #$07 : sta $2105 
    ; lda #$17 : sta $212C
    ; lda #$00 : sta $213E : sta $2133
    ; lda #$0F : sta $2100

    ;;lda #$00 : sta $4200
    ;lda #$FF : sta $4201

    ; ldx #$4202
; -   sta $00,x
    ; inx
    ; cpx #$410D
    ; bne -

    ;;lda #$80 : sta $4200
    ;;lda $4210
    ldx #$BBAA
-   cpx $2140
    bne -
    
    lda #$81 : sta $4200
    
    ;cli
    ; wait for interrupt
;-   bra -
    wai
    
; NOTE: this really starts at $2A90
;ORG $002A90
ORG $D00000
FORCEPC $002A90
    jmp.l start
hook_return:
    ; one shot
    %a8() : lda #$60 : sta $002A90
    rts