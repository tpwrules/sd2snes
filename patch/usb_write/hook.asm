ORG $002A90 : ipsoffset $D00000
print "Hook Bank Starting at: ", pc

hook:
    jmp.l start
hook_return:
    rts ; FW puts this in for us already, but do it for safety anyway
    
print "Hook Bank Ending at: ", pc
