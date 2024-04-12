INCLUDE "hardware.inc"

SECTION "Screen functions", ROM0

; Wait for next VBlank, skipping any in-progress VBlank.
WaitForNextVBlank::
	; Ensure we don't start drawing mid-VBlank.
	ld a, [rLY]
	cp a, 144
	jr nc, WaitForNextVBlank
.wait
	ld a, [rLY]
	cp a, 144
	jr c, .wait
	ret

