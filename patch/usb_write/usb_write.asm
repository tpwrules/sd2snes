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
    
    ; ldx #$0340
; send: 
    ; %usb_sendq_full() : bne cont : jmp recv; skip if queue is full
; cont:
    ; lda.l $7EF000, x : cmp.l !USBNET_DATA_BANK|!USBNET_DATA, x : bne lower
; next:
    ; inx #2 : cpx #$035C : bne send
    ; jmp recv
; single:
    ; %a16() : dex : bra next
    
    ; ; check lower 8b
; lower:
    ; %a8()
    ; lda.l $7EF000, x : cmp.l !USBNET_DATA_BANK|!USBNET_DATA, x : beq upper
    ; sta.l !USBNET_DATA_BANK|!USBNET_DATA, x ; update data bank to avoid spamming before broadcast
    ; %a16() : and #$00FF : tay ; move data to y
    ; phx : txa : asl #4 : ora !USBNET_OPCODE_8BIT|!USBNET_OPCODE_MAX
    ; %usb_sendq_enqueue()
    ; plx
    ; %usb_sendq_full() : beq recv
    ; ; check upper 8b
; upper:
    ; %a8()
    ; inx
    ; cpx #$0343 : beq single ; ignore bombs
    ; lda.l $7EF000, x : cmp.l !USBNET_DATA_BANK|!USBNET_DATA, x : beq single
    ; sta.l !USBNET_DATA_BANK|!USBNET_DATA, x ; update data bank to avoid spamming before broadcast
    ; %a16() : and #$00FF : tay ; swap to upper 8b
    ; phx : txa : asl #4 : ora !USBNET_OPCODE_8BIT|!USBNET_OPCODE_MAX
    ; %usb_sendq_enqueue()
    ; plx
    ; jmp single
    
print "USB RecvQ at: ", pc

recv:
    %a16()
    %usb_recvq_empty() : bne ++ : jmp +
++  %usb_recvq_deque()
print "USB RecvQ Exe at: ", pc
    %usb_write()
    ; also force the item in memory
    ;sta.l $7EF000, x
    
+   %ai16() : %load_registers()
.exit
    jmp.l hook_return
    
; DATA
.data
; .U_TEST         dw $0000
	
print "USB Bank Ending at: ", pc
