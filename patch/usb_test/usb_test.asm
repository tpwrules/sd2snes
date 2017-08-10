org !SS_CODE
print "USB Bank Starting at: ", pc

.text
init:
    %ai16()
    %save_registers()
    lda init
    sta.l start
    %usb_init()
    %load_registers()

start:
print "USB start at: ", pc
    bra init
    %save_registers()
    
    %usb_sendq_full() : beq + ; skip if queue is full
    lda #$0000
    %a8() : lda.l $7EF357 : beq + ; moon pearl
    %a16() : tay
    lda.l .U_TEST : bne + ; temp flag
    inc
    sta.l .U_TEST
    ; send moon pearl to other clients
    lda #$357<<4|!USBNET_OPCODE_8BIT|!USBNET_OPCODE_WRITE
    %usb_sendq_enqueue()
    
; +   lda.l .U_TEST2 : bne +
    ; %a8() : ldx #$357 : lda.l !USBNET_DATA_BANK|!USBNET_DATA, x : beq +
    ; sta.l $7EF357
    ; %a16() : lda.l .U_TEST2 : inc : sta.l .U_TEST2

print "USB RecvQ at: ", pc

+   %a16()
    %usb_recvq_empty() : bne ++ : jmp +
++  %usb_recvq_deque()
print "USB ReqcQ Exe at: ", pc
    %usb_exe()
    ; also force the item in memory
    sta.l $7EF000, x
    
+   %ai16() : %load_registers()
.exit
    jmp.l hook_return
    
; DATA
.data
.U_TEST         dw $0000
	
print "USB Bank Ending at: ", pc
