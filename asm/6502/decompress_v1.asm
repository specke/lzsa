; -----------------------------------------------------------------------------
; Decompress raw LZSA1 block. Create one with lzsa -r <original_file> <compressed_file>
;
; in:
; * LZSA_SRC_LO and LZSA_SRC_HI contain the compressed raw block address
; * LZSA_DST_LO and LZSA_DST_HI contain the destination buffer address
;
; out:
; * LZSA_DST_LO and LZSA_DST_HI contain the last decompressed byte address, +1
; -----------------------------------------------------------------------------
;
;  Copyright (C) 2019 Emmanuel Marty
;
;  This software is provided 'as-is', without any express or implied
;  warranty.  In no event will the authors be held liable for any damages
;  arising from the use of this software.
;
;  Permission is granted to anyone to use this software for any purpose,
;  including commercial applications, and to alter it and redistribute it
;  freely, subject to the following restrictions:
;
;  1. The origin of this software must not be misrepresented; you must not
;     claim that you wrote the original software. If you use this software
;     in a product, an acknowledgment in the product documentation would be
;     appreciated but is not required.
;  2. Altered source versions must be plainly marked as such, and must not be
;     misrepresented as being the original software.
;  3. This notice may not be removed or altered from any source distribution.
; -----------------------------------------------------------------------------

DECOMPRESS_LZSA1
   LDY #$00

DECODE_TOKEN
   JSR GETSRC                           ; read token byte: O|LLL|MMMM
   PHA                                  ; preserve token on stack

   AND #$70                             ; isolate literals count
   BEQ NO_LITERALS                      ; skip if no literals to copy
   CMP #$70                             ; LITERALS_RUN_LEN?
   BNE EMBEDDED_LITERALS                ; if not, count is directly embedded in token

   JSR GETSRC                           ; get extra byte of variable literals count
                                        ; the carry is always set by the CMP above
                                        ; GETSRC doesn't change it
   SBC #$F9                             ; (LITERALS_RUN_LEN)
   BCC PREPARE_COPY_LITERALS
   BEQ LARGE_VARLEN_LITERALS            ; if adding up to zero, go grab 16-bit count

   JSR GETSRC                           ; get single extended byte of variable literals count
   INY                                  ; add 256 to literals count
   BCS PREPARE_COPY_LITERALS            ; (*like JMP PREPARE_COPY_LITERALS but shorter)

LARGE_VARLEN_LITERALS                   ; handle 16 bits literals count
                                        ; literals count = directly these 16 bits
   JSR GETLARGESRC                      ; grab low 8 bits in X, high 8 bits in A
   TAY                                  ; put high 8 bits in Y
   BCS PREPARE_COPY_LITERALS_HIGH       ; (*like JMP PREPARE_COPY_LITERALS_HIGH but shorter)

EMBEDDED_LITERALS
   LSR A                                ; shift literals count into place
   LSR A
   LSR A
   LSR A

PREPARE_COPY_LITERALS
   TAX
PREPARE_COPY_LITERALS_HIGH
   INY

COPY_LITERALS
   JSR GETPUT                           ; copy one byte of literals
   DEX
   BNE COPY_LITERALS
   DEY
   BNE COPY_LITERALS
   
NO_LITERALS
   PLA                                  ; retrieve token from stack
   PHA                                  ; preserve token again
   BMI GET_LONG_OFFSET                  ; $80: 16 bit offset

   JSR GETSRC                           ; get 8 bit offset from stream in A
   TAX                                  ; save for later
   LDA #$0FF                            ; high 8 bits
   BNE GOT_OFFSET                       ; go prepare match
                                        ; (*like JMP GOT_OFFSET but shorter)

SHORT_VARLEN_MATCHLEN
   JSR GETSRC                           ; get single extended byte of variable match len
   INY                                  ; add 256 to match length

PREPARE_COPY_MATCH
   TAX
PREPARE_COPY_MATCH_Y
   INY

COPY_MATCH_LOOP
   LDA $AAAA                            ; get one byte of backreference
   INC COPY_MATCH_LOOP+1
   BEQ GETMATCH_INC_HI
GETMATCH_DONE
   JSR PUTDST                           ; copy to destination
   DEX
   BNE COPY_MATCH_LOOP
   DEY
   BNE COPY_MATCH_LOOP
   BEQ DECODE_TOKEN                     ; (*like JMP DECODE_TOKEN but shorter)

GETMATCH_INC_HI
   INC COPY_MATCH_LOOP+2
   BNE GETMATCH_DONE                    ; (*like JMP GETMATCH_DONE but shorter)

GET_LONG_OFFSET                         ; handle 16 bit offset:
   JSR GETLARGESRC                      ; grab low 8 bits in X, high 8 bits in A

GOT_OFFSET
   STA OFFSHI                           ; store high 8 bits of offset
   TXA

   CLC                                  ; add dest + match offset
   ADC PUTDST+1                         ; low 8 bits
   STA COPY_MATCH_LOOP+1                ; store back reference address
OFFSHI = *+1
   LDA #$AA                             ; high 8 bits

   ADC PUTDST+2
   STA COPY_MATCH_LOOP+2                ; store high 8 bits of address
   
   PLA                                  ; retrieve token from stack again
   AND #$0F                             ; isolate match len (MMMM)
   CLC
   ADC #$03
   CMP #$12                             ; MATCH_RUN_LEN?
   BNE PREPARE_COPY_MATCH               ; if not, count is directly embedded in token

   JSR GETSRC                           ; get extra byte of variable match length
                                        ; the carry is always set by the CMP above
                                        ; GETSRC doesn't change it
   SBC #$EE                             ; add MATCH_RUN_LEN and MIN_MATCH_SIZE to match length
   BCC PREPARE_COPY_MATCH
   BNE SHORT_VARLEN_MATCHLEN

                                        ; Handle 16 bits match length
   JSR GETLARGESRC                      ; grab low 8 bits in X, high 8 bits in A
   TAY                                  ; put high 8 bits in Y
                                        ; large match length with zero high byte?
   BNE PREPARE_COPY_MATCH_Y             ; if not, continue
                                        ; (*like JMP PREPARE_COPY_MATCH_Y but shorter)
DECOMPRESSION_DONE
   RTS

GETPUT
   JSR GETSRC
PUTDST
LZSA_DST_LO = *+1
LZSA_DST_HI = *+2
   STA $AAAA
   INC PUTDST+1
   BEQ PUTDST_INC_HI
PUTDST_DONE
   RTS
PUTDST_INC_HI
   INC PUTDST+2
   RTS

GETLARGESRC
   JSR GETSRC                           ; grab low 8 bits
   TAX                                  ; move to X
                                        ; fall through grab high 8 bits

GETSRC
LZSA_SRC_LO = *+1
LZSA_SRC_HI = *+2
   LDA $AAAA
   INC GETSRC+1
   BEQ GETSRC_INC_HI
GETSRC_DONE
   RTS
GETSRC_INC_HI
   INC GETSRC+2
   RTS
