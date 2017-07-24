ORG $D00000
FORCEPC $002A90
print "Hook Bank Starting at: ", pc

hook:
    jmp.l !SS_CODE
hook_return:
    rts ; FW puts this in for us already, but do it for safety anyway
    
print "Hook Bank Ending at: ", pc

; hook:
    ; %a8()
; .hook_one_shot
    ; bra .hook_init
; .hook_start
    ; jmp.l !SS_CODE
        
; .hook_init
    ; sta .hook_one_shot+1

    ; lda $00FFD5 ; load byte that may correspond to ROM mode
    ; bit #$C8 ; handle contra and other ROMs that put a string in the mode spot.  assume they are LOROM
    ; bne .hook_one_shot
    ; bit #$01 ; test for HIROM bit
    ; beq .hook_one_shot
    ; ; hirom
    ; %a16()
    ; lda #start_hirom
    ; sta .hook_start+1
    ; %a8()
    ; bra .hook_one_shot

; hook_return:
    ; rts ; FW puts this in for us already, but do it for safety anyway
