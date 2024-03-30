INCLUDE "hardware.inc"

DEF WIDTH  EQU 160
DEF HEIGHT EQU 144

SECTION "Display buffer", WRAM0
	wBuffer: ds 32*18

SECTION "Header", ROM0[$0100]
	jp Entrypoint
	ds $150-@, 0	; Make room for header

Entrypoint:
	; Wait on first _full_ VBlank
	ld a, [rLY]
	cp a, 144
	jp c, Entrypoint

	; Turn off LCD
	ld a, 0
	ld [rLCDC], a

	; Initialize tiles and tilemap
	ld de, Tiles
	ld hl, $9000
	ld bc, TilesEnd - Tiles
	call Memcopy

	ld de, Tilemap
	ld hl, $9800
	ld bc, TilemapEnd - Tilemap
	call Memcopy
	
	ld de, Tilemap
	ld hl, wBuffer
	ld bc, TilemapEnd - Tilemap
	call Memcopy

	; Turn LCD on
	ld a, LCDCF_ON | LCDCF_BGON
	ld [rLCDC], a
Main:
	call WaitForNextVBlank
	
	ld bc, $0102
	call NextGenerationForCell
	
	call WaitForNextVBlank

.blit	; Blit to screen
	ld  de, wBuffer
	ld hl, $9800
	ld bc, TilemapEnd - Tilemap
	call Memcopy

	jp Main

; Wait for next VBlank, skipping any in-progress VBlank.
WaitForNextVBlank:
	; Ensure we don't start drawing mid-VBlank.
	; Gives maximal time to execute copy.
	ld a, [rLY]
	cp a, 144
	jr nc, WaitForNextVBlank
.wait
	ld a, [rLY]
	cp a, 144
	jr c, .wait
	ret
	
; Calculate next generation into wBuffer
; @param b: X
; @param c: Y
NextGenerationForCell:
	push af
	call ScreenToTile
	ld   a, [hl]
	dec  a
	jp   z, .alive

	; dead
	call CountNeighbors
	cp   a, 3
	jp   z, .birth
	jp   .knownret		; already dead, no need to kill
.alive
	call CountNeighbors
	cp   a, 2		; 2 lives
	jp   z, .knownret	; already alive, no need to birth
	cp   a, 3		; 3 lives
	jp   z, .knownret	; already alive, no need to birth
	; fallthrough
.death
	ld   [hl], $00
	jp   .knownret
	
.birth
	ld   [hl], $01
	; fallthrough 
.knownret
	pop  af
	ret

; Check if position is within board
; @param b: X
; @param c: Y
; @return C (flag): set when position invalid
CheckValidPosition:
	push af

	; Check X in bounds. Works for left and right edges.
	; X=-1(255); +235 causes overflow
	; X=21; +235 still causes overflow
	ld a, b
	add a, 235
	jp c, .invalid

	; Check Y in bounds. 
	ld a, c
	add a, 237
.invalid
	pop af
	ret

; Count live neighbors for position.
; @param b: X
; @param c: Y
; @return a: count live neighbors
CountNeighbors:
	push hl
	push de
	ld   a, 0

	; (X-1, Y-1)
	dec  b
	dec  c
	call CheckValidPosition
	jp   c, .two
	call ScreenToTile
	ld   d, [hl]
	dec  d
	call z, .plusone
.two
	; (X, Y-1)
	inc b
	call CheckValidPosition
	jp   c, .three
	call ScreenToTile
	ld   d, [hl]
	dec  d
	call z, .plusone
.three
	; (X+1, Y-1)
	inc b
	call CheckValidPosition
	jp   c, .four
	call ScreenToTile
	ld   d, [hl]
	dec  d
	call z, .plusone
.four
	; (X-1, Y)
	dec  b
	dec  b
	inc  c
	call CheckValidPosition
	jp   c, .six
	call ScreenToTile
	ld   d, [hl]
	dec  d
	call z, .plusone
.six
	; (X+1, Y)
	inc  b
	inc  b
	call CheckValidPosition
	jp   c, .seven
	call ScreenToTile
	ld   d, [hl]
	dec  d
	call z, .plusone
.seven
	; (X-1, Y+1)
	dec  b
	dec  b
	inc  c
	call CheckValidPosition
	jp   c, .eight
	call ScreenToTile
	ld   d, [hl]
	dec  d
	call z, .plusone
.eight
	; (X, Y+1)
	inc  b
	call CheckValidPosition
	jp   c, .nine
	call ScreenToTile
	ld   d, [hl]
	dec  d
	call z, .plusone
.nine
	; (X+1, Y+1)
	inc  b
	call CheckValidPosition
	jp   c, .knownret
	call ScreenToTile
	ld   d, [hl]
	dec  d
	call z, .plusone
	jp   .knownret
.plusone
	inc a
	ret
.knownret
	pop de
	pop hl
	ret

; Get tile at screen coords. Uses BC internally.
; @param b: x-coord
; @param c: y-coord
; @return hl: tile address
;
; NOTE: based on the unbricked tutorial
ScreenToTile:
    	push af
    	push bc
    	
    	; Convert Y to absolute offset by multiplying by 32 (row size)
    	ld a, c
    	ld l, a
    	ld h, 0
    	add hl, hl ; position * 2
    	add hl, hl ; position * 4
    	add hl, hl ; position * 8
    	add hl, hl ; position * 16
    	add hl, hl ; position * 32
    	
    	; X is already an offset
    	ld a, b
    	
    	; Add the two offsets together.
    	add a, l
    	ld  l, a
    	adc a, h
    	sub a, l
    	ld  h, a
    	
    	; Add the offset to the tilemap's base address, and we are done!
    	ld bc, wBuffer
    	add hl, bc
    	
    	pop bc
    	pop af
    	ret

; Copy data from one location to another
; @param de: Source
; @param hl: Destination
; @param bc: Length
Memcopy:
	ld a, [de]
	ld [hli], a
	inc de
	dec bc
	ld a, b
	or a, c
	jp nz, Memcopy
	ret

Tiles:
	; dead
	dw `00000000
	dw `00000000
	dw `00000000
	dw `00000000
	dw `00000000
	dw `00000000
	dw `00000000
	dw `00000000
	
	; alive
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33333333
	dw `33333333
TilesEnd:

Tilemap:
	db $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $01, $01, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
TilemapEnd:
