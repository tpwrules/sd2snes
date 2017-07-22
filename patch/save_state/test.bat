mv test.bin test_old.bin
touch test.bin
cp save.asm save_hirom.asm
.\xkas.exe main.asm test.bin
