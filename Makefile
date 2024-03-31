main.gb: main.o
	rgblink -o conway.gb main.o 
	rgbfix -v -p 0xFF conway.gb

main.o: main.asm
	rgbasm -L -o main.o main.asm
	rgblink -n main.sym main.o
