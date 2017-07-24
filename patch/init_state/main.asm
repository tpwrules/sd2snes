flat
ips

; --- Savestate code ---
incsrc macros.asm ; Useful macros
incsrc cfg.asm ; Savestate code configuration

; include save state
;org $F00000
;incbin save.ss0

incsrc init.asm ; Savestate code


; include save state
org $F00000
incbin save.ss0


incsrc hook.asm ; hook (needs to be last to work on sd2snes)
