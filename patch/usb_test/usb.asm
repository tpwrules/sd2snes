; USB Defines

!USBNET_OPCODE_WRITE          = #$0
!USBNET_OPCODE_ADD            = #$1
!USBNET_OPCODE_SUB            = #$2
!USBNET_OPCODE_MIN            = #$3
!USBNET_OPCODE_MAX            = #$4
!USBNET_OPCODE_AND            = #$5
!USBNET_OPCODE_EOR            = #$6
!USBNET_OPCODE_CAS            = #$7
!USBNET_OPCODE_FLUSH          = #$F
!USBNET_OPCODE_8BIT           = #$0
!USBNET_OPCODE_16BIT          = #$8

!USBNET_DATA_BANK             = $1E0000
!USBNET_REG_BANK              = $1E0000
!USBNET_QUEUE_BANK            = $1F0000
!USBNET_DATA                  = $5000
!USBNET_REG                   = $5FF0
!USBNET_SENDQ_QUEUE           = $5000
!USBNET_RECVQ_QUEUE           = $5800

; REGISTERS
; 16b pointers
!USBNET_REG_SENDQ_HEADPTR     = $0
!USBNET_REG_SENDQ_TAILPTR     = $2
!USBNET_REG_RECVQ_HEADPTR     = $4
!USBNET_REG_RECVQ_TAILPTR     = $6

; USB Macros

; setup memory - a=16,i=16
macro usb_init()
    phb
    ; FIXME: this takes a long time which can cause problems with interrupts
    ; data/regs
    lda #$0000
    sta.l !USBNET_DATA_BANK|!USBNET_DATA
    lda #$0FFE
    ldx #$5000
    txy : iny
    mvn $1E1E
    ; queues
    ;lda #$0000
    ;sta.l !USBNET_QUEUE_BANK|!USBNET_SENDQ_QUEUE
    ;lda #$0FFE
    ;ldx #$5000
    ;txy : iny
    ;mvn $1F1F
    plb
endmacro

; check queue full. - a=16,i=16
; NOTE: wastes an entry to differentiate from empty without count or other state
macro usb_sendq_full()
    lda.l !USBNET_REG_BANK|!USBNET_REG|!USBNET_REG_SENDQ_TAILPTR : inc #4 : and #$7FC
    cmp.l !USBNET_REG_BANK|!USBNET_REG|!USBNET_REG_SENDQ_HEADPTR
    ; if equal then queue is full
endmacro
    
; send command - a=16,i=16
; A = address | command
; X = [temp for queue index]
; Y = data
macro usb_sendq_enqueue()
    phb : pea $1E00 : plb : plb
    ldx !USBNET_REG|!USBNET_REG_SENDQ_TAILPTR
    sta.l !USBNET_QUEUE_BANK|!USBNET_SENDQ_QUEUE, x : inx #2 : tya : sta.l !USBNET_QUEUE_BANK|!USBNET_SENDQ_QUEUE, x : inx #2
    cpx #$0800
    bne ?qe_end
    ldx #$0000
?qe_end:
    stx !USBNET_REG|!USBNET_REG_SENDQ_TAILPTR
    plb
endmacro

; check recv queue emtpy - a=16,i=16
macro usb_recvq_empty()
    lda.l !USBNET_REG_BANK|!USBNET_REG|!USBNET_REG_RECVQ_HEADPTR
    cmp.l !USBNET_REG_BANK|!USBNET_REG|!USBNET_REG_RECVQ_TAILPTR
endmacro

; receive command - a=16,i=16
; A <- address | command
; Y <- data
macro usb_recvq_deque()
    phb : pea $1E00 : plb : plb
    ldx !USBNET_REG|!USBNET_REG_RECVQ_HEADPTR
    lda.l !USBNET_QUEUE_BANK|!USBNET_RECVQ_QUEUE+2, x : tay : lda.l !USBNET_QUEUE_BANK|!USBNET_RECVQ_QUEUE+0, x : inx #4
    cpx #$0800
    bne ?qe_end
    ldx #$0000
?qe_end:
    stx !USBNET_REG|!USBNET_REG_RECVQ_HEADPTR
    plb
endmacro

; execute command - a=16,i=16
; A = address | command
; Y = data
macro usb_exe()
    ; test for precision
    pha : lsr #4 : tax : pla
    bit.w !USBNET_OPCODE_16BIT
    bne ?p16
    sep #$20
    and.b #$07
    bra ?p
?p16:
    and.w #$0007
?p:
    bne ?1
    ;!USBNET_OPCODE_WRITE          = #$0
    tya
    bra ?op
?1: dec ;cmp !USBNET_OPCODE_ADD
    bne ?2
    tya
    clc
    adc.l !USBNET_DATA_BANK|!USBNET_DATA, x
    bra ?op
?2: dec ;cmp !USBNET_OPCODE_SUB
    bne ?3
    tya
    ; twos complement
    clc
    sbc.l !USBNET_DATA_BANK|!USBNET_DATA, x
    eor #$FFFF
    bra ?op
?3: dec ;cmp !USBNET_OPCODE_MIN
    bne ?4
    tya
    cmp.l !USBNET_DATA_BANK|!USBNET_DATA, x
    bcs ?done
    bra ?op
?4: dec ;cmp !USBNET_OPCODE_MAX
    bne ?5
    tya
    cmp.l !USBNET_DATA_BANK|!USBNET_DATA, x
    bcc ?done
    bra ?op
?5: dec ;cmp !USBNET_OPCODE_AND
    bne ?6
    tya
    and.l !USBNET_DATA_BANK|!USBNET_DATA, x
    bra ?op
?6: dec ;cmp !USBNET_OPCODE_EOR
    bne ?7
    tya
    eor.l !USBNET_DATA_BANK|!USBNET_DATA, x
    bra ?op
?7: dec ;;!USBNET_OPCODE_CAS ; only opcode left
    rep #$20
    tya
    xba
    sep #$20
    cmp.l !USBNET_DATA_BANK|!USBNET_DATA, x
    bne ?done
    xba
?op:
    sta.l !USBNET_DATA_BANK|!USBNET_DATA, x
?done:
endmacro