conway: main.o grid.o memory.o screen.o
	rgblink -n $@.sym -o $@.gb $^
	rgbfix -v -p 0xFF $@.gb

main.o: main.asm
	rgbasm -L -o $@ $^

grid.o: grid.asm
	rgbasm -L -o $@ $^

memory.o: memory.asm
	rgbasm -L -o $@ $^

screen.o: screen.asm
	rgbasm -L -o $@ $^
