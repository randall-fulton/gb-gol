SECTION "Cell grid functions", ROM0

; Check if position is within board
; @param b: X
; @param c: Y
; @return C (flag): set when position invalid
CheckValidPosition::
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
