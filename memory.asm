SECTION "Memory functions", ROM0

; Copy data from one location to another
; @param de: Source
; @param hl: Destination
; @param bc: Length
Memcopy::
	ld  a, [de]
	ld  [hli], a
	inc de
	dec bc
	ld  a, b
	or  a, c
	jp  nz, Memcopy
	ret
