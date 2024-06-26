INCLUDE "hardware.inc"

DEF ROWLEN EQU 20
DEF ROWS   EQU 18

SECTION "Display buffer", WRAM0
wBuffer:  ds 32*18
wBuffer2: ds 32*18

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
	
	ld de, Tilemap
	ld hl, wBuffer2
	ld bc, TilemapEnd - Tilemap
	call Memcopy

	; Turn LCD on
	ld a, LCDCF_ON | LCDCF_BGON
	ld [rLCDC], a
Main:
	; prepare secondary back buffer for calculation
	; using a single back buffer would corrupt cell state mid-generation
	ld de, wBuffer
	ld hl, wBuffer2
	ld bc, TilemapEnd - Tilemap
	call Memcopy
	
	call NextGeneration
	call WaitForNextVBlank
	
	; Turn off LCD
	ld a, 0
	ld [rLCDC], a

	; Blit to screen
	ld  de, wBuffer
	ld hl, $9800
	ld bc, TilemapEnd - Tilemap
	call Memcopy

	; Turn LCD on
	ld a, LCDCF_ON | LCDCF_BGON
	ld [rLCDC], a

	jp Main

; Calculate next generation for entire back buffer (wBuffer)
NextGeneration:
	push bc

	ld   a, ROWLEN		; cells per row
	ld   bc, $0000		; (0, 0)
.loop
	call NextGenerationForCell
	inc  b		      	; move to next cell horizontally
	dec  a			; one cell down
	jp   nz, .loop
	inc  c			; just finished a row

	ld   a, c
	cp   ROWS
	jp   z, .knownret	; exit loop if all rows processed
	
	ld   a, ROWLEN		; reset loop counter 
	ld   b, $00		; X = 0
	jp   .loop

.knownret
	pop  bc
	ret
	
; Calculate next generation for single cell and update in wBuffer2
; @param b: X
; @param c: Y
NextGenerationForCell:
	push af
	push de

	call GetTileOffset
	ld   d, h
	ld   e, l		; DE = tile offset
	ld   hl, wBuffer2	; add offset to read-only back buffer
	add  hl, de

	; Check current status of cell
	ld   a, [hl]
	dec  a
	jp   z, .alive

	; dead
	call CountNeighbors
	cp   a, 3
	jp   z, .birth
	;; jp   .knownret		; already dead, no need to kill
	jp .death
.alive
	call CountNeighbors
	cp   a, 2		; 2 lives
	;; jp   z, .knownret	; already alive, no need to birth
	jp   z, .birth
	cp   a, 3		; 3 lives
	;; jp   z, .knownret	; already alive, no need to birth
	jp   z, .birth
	; fallthrough
.death
	ld   hl, wBuffer	; load cell address in write-only back buffer
	add  hl, de
	ld   [hl], $00		; kill it
	jp   .knownret
	
.birth
	ld   hl, wBuffer	; load cell address in write-only back buffer
	add  hl, de
	ld   [hl], $01		; alive it
	; fallthrough 
.knownret
	pop  de
	pop  af
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
	; reset to origin (X, Y)
	dec b
	dec c
	
	pop de
	pop hl
	ret

; Get tile offset in tilemap. Offsets valid for back buffers or VRAM.
; @param b: X
; @param c: Y
; @return hl: tile offset
GetTileOffset:
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

	pop bc
	pop af
	ret

; Get tile at screen coords, using wBuffer2.
; @param b: x-coord
; @param c: y-coord
; @return hl: tile address
;
; NOTE: based on the unbricked tutorial
ScreenToTile:
    	push bc

	call GetTileOffset
    	
    	; Add the offset to the tilemap's base address, and we are done!
    	ld bc, wBuffer2
    	add hl, bc
    	
    	pop bc
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
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $01, $00, $00, $00, $00, $00, $01, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $01, $00, $00, $00, $01, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $01, $01, $01, $00, $00, $00, $00, $01, $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $01, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $01, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $01, $01, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, 0,0,0,0,0,0,0,0,0,0,0,0
TilemapEnd:
