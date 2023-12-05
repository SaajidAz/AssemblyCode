; Constants

; Port Pins
.equ	LIGHT	= 7		; Door Light WHITE LED PORTD pin 7
.equ	TTABLE	= 6		; Turntable PORTD pin 6 PWM
.equ	BEEPER	= 5		; Beeper PORTD pin 5
.equ	CANCEL	= 4		; Cancel switch PORTD pin 4
.equ	DOOR	= 3		; Door latching switch PORTD pin 3
.equ	STSP	= 2		; Start/Stop switch PORTD pin 2
.equ	HEATER	= 0		; Heater RED LED PORTB pin 0

; General Constants
.equ	CLOSED	= 0
.equ	OPEN	= 1
.equ	ON	= 1
.equ	OFF	= 0
.equ	YES	= 1
.equ	NO	= 0
.equ	JCTR	= 125	; Joystick centre value

; States
.equ	STARTS		= 0
.equ	IDLES		= 1
.equ	DATAS		= 2
.equ	COOKS		= 3
.equ	SUSPENDS	= 4




; Device constants
.nolist
.include "m328pdef.inc" ; Define device ATmega328P
.list

;           S R A M
.dseg
.org SRAM_START
cstate:	.byte 1			; Current State
inputs: 	.byte 1			; Current input settings
joyx:		.byte 1			; Raw joystick x-axis
joyy:		.byte 1			; Raw joystick y-axis
joys:		.byte 1			; Joystick status bits 0-not centred,1- centred
seconds:	.byte 2			; Cook time in seconds 16-bit
sec1:		.byte 1			; minor tick time (100 ms)
tascii: .byte 8


;         C O D E
	.cseg
	.org 0x0000


	jmp	start



; Start after interrupt vector table
	.org	0xF6
  joymsg:		.db " Joystick X:Y ",0,0
cmsg1:	.db "Time: ",0,0
cmsg2:	.db " Cook Time: ",0,0
cmsg3:	.db " State: ",0,0



; .asm include statements
.include "iopins.asm"
.include "util.asm"
.include "serialio.asm"
.include "adc.asm"
.include "i2c.asm"
.include "rtcds1307.asm"
.include "andisplay.asm"

start:
	ldi	r16,HIGH(RAMEND)	; Initialize the stack pointer
	out	SPH,r16
	ldi	r16,LOW(RAMEND)
	out	SPL,r16
  call initPorts
  call initUSART0
  call initADC
  call initI2C
  call initDS1307
  call initAN
  jmp startstate

loop:
call	updateTick		; Check the time
; Check the inputs here



;	If Door Open jump to suspend
sbis	PIND,DOOR
jmp	suspend
cbi PORTD, LIGHT
;	Cancel Key Pressed  jump to idle
	sbis	PIND,CANCEL
	jmp	idle

;	Start Stop Key Pressed
  lds r16, cstate
 	sbic	PIND,STSP
	jmp	joy0				; If Start/Stop key not pressed loop


   cpi r16, COOKS
   breq suspend
   cpi r16, IDLES
   breq cook
   cpi r16, SUSPENDS
   breq cook
   cpi r16, STARTS
   breq cook

   jmp loop


   joy0:
        call joystickinputs
         cpi r16, COOKS
         breq loop
         cpi r25, 1
         breq loop
         jmp dataentry


  ; When checking the Start/Stop key get the current state (cstate) in a register.
  ;If the Start/Stop key is not pressed jump to the top of the loop.
  ; If the Start/Stop key has been pressed and


  ;the current state is COOKS branch to suspend.

  ;the current state is IDLES,SUSPENDS, or temporarily STARTS branch to cook.

  ;otherwise loop.






startstate:				; start state tasks
	ldi	r24,STARTS		; Start state
	sts	cstate,r24
  call setDS1307
  ldi r16, 0
  sts seconds, r16
  sts seconds+1, r16
  sts sec1, r16

    cbi  PORTD, HEATER                    ;turn off heater and light
    cbi PORTD, LIGHT

  ldi r16, 0
  out OCR0A, r16

 jmp	loop

idle:
	ldi	r24,IDLES			; Set state variable to Idle
	sts	cstate,r24

   cbi PORTD, HEATER                 ;<-heater off
   cbi PORTD, LIGHT                 ;<-light off
  ldi r16, 0
  sts seconds, r16
  sts seconds+1, r16                   ;<-seconds = 0

  ldi r16, 0
  out OCR0A, r16
  sbi PORTD, BEEPER
  call delay100ms


	jmp	loop

; Cook State
cook:	ldi	r24,COOKS			; Set state variable to Cook
	sts	cstate,r24			; Do cook state tasks


     sbi PORTD, HEATER                 ;turn on heater
     cbi PORTD, LIGHT                  ;turn off light

  ldi r16, 0x23
  out OCR0A, r16
	jmp	loop

; Suspend State
suspend:					; suspend state tasks
	ldi	r24,SUSPENDS			; Set state variable to Suspend
	sts	cstate,r24			; Do suspend state tasks


   cbi PORTD, HEATER                      ;turn off heater
   sbi PORTD, LIGHT                      ;turn on light


  ldi r16, 0
  out OCR0A, r16

	jmp	loop

dataentry:						; data entry state tasks
	ldi	r24,DATAS			; Set state variable to Data Entry
	sts	cstate,r24
  cbi PORTD, HEATER                    ;turn off heater and light
  cbi PORTD, LIGHT
  ldi r16, 0
  out OCR0A, r16
	lds	r26,seconds			; Get current cook time
	lds	r27,seconds+1
	lds	r21,joyx
	cpi	r21,135				; Check for time increment
	brsh	de1
	cpi	r27,0				; Check upper byte for 0
	brne	de0
	cpi	r26,0				; Check lower byte for 0
	breq	de2
de0:
	sbiw	r27:r26,10			; Decrement cook time by 10 seconds
	jmp	de2
de1:
	adiw	r27:r26,10			; Increment cook time by 10 seconds
de2:
	sts	seconds,r26			; Store time
	sts	seconds+1,r27
	call	displayState
	call	delay1s
	call	joystickInputs
	lds	r21,joys
	cpi	r21,0
	breq	dataentry			; Do data entry until joystick centred
	ldi	r24,SUSPENDS
	sts	cstate,r24


	jmp	loop








; Time Tasks
updateTick:
	call	delay100ms
	cbi	PORTD,BEEPER	; Turn off beeper
	lds	r22,sec1		; Get minor tick time
	cpi	r22,10			; 10 delays of 100 ms done?
	brne	ut2
	ldi	r22,0			; Reset minor tick
	sts	sec1,r22		; Do 1 second interval tasks

	lds	r23,cstate		; Get current state
	cpi	r23,COOKS
	brne	ut1
	lds	r26,seconds		; Get current cook time
	lds	r27,seconds+1
	inc	r26
	sbiw	r27:r26,1		; Decrement cook time by 1 second
	brne	ut3
	jmp	idle
ut3:	sbiw	r27:r26,1		; Decrement/store cook time
	sts	seconds,r26
	sts	seconds+1,r27
ut1:	call	displayState
ut2:	lds	r22,sec1
	inc	r22
	sts	sec1,r22
	ret










; Save Most Significant 8 bits of Joystick X,Y
; To the global variables joyx and joyy
; Set joys if the joystick is centred.
joystickInputs:
	ldi	r24,0x00		; Read ch 0 Joystick Y
	call	readADCch
	swap	r25
	lsl	r25
	lsl	r25
	lsr	r24
	lsr	r24
	or	r24,r25
	sts	joyy,r24
	ldi	r24,0x01		; Read ch 1 Joystick X
	call	readADCch
	swap	r25
	lsl	r25
	lsl	r25
	lsr	r24
	lsr	r24
	or	r24,r25
	sts	joyx,r24
	ldi	r25,0			; Not centred
	cpi	r24,115
	brlo	ncx
	cpi	r24,135
	brsh	ncx
	ldi	r25,1			; Centred
ncx:
	sts	joys,r25
ret




displayState:
call newline
ldi zl,low(cmsg1<<1)
ldi zh,high(cmsg1<<1)
ldi r16,1
call putsUSART0


        call DisplayTOD

ldi zl,low(cmsg2<<1)
ldi zh,high(cmsg2<<1)
ldi r16,1
call putsUSART0


            call displayCookTime



ldi zl,low(cmsg3<<1)
ldi zh,high(cmsg3<<1)
ldi r16,1
call putsUSART0


lds r16,cstate
ori r16,0x30
call putchUSART0

ldi zl,low(joymsg<<1)
ldi zh,high(joymsg<<1)
ldi r16,1
call putsUSART0


lds    r17,joyx                  ;x value
    call    byteToHexASCII
    mov    r16,r17
    call    putchUSART0
    mov    r16,r18
    call    putchUSART0


    ldi    r16,0x3A          ; put in the ":"
    call    putchUSART0


lds    r17,joyy                  ;y value
   call    byteToHexASCII
    mov    r16,r17
    call    putchUSART0
    mov    r16,r18
    call    putchUSART0





ret


DisplayTOD:
ldi		r25,HOURS_REGISTER
	call	ds1307GetDateTime
	mov		r17,r24
                   ;code for clock
     call    pBCDtoASCII
    mov    r16,r17
    call    putchUSART0
    mov    r16,r18
    call    putchUSART0



     ldi    r16,0x3A                               ; ":"
    call    putchUSART0

        ldi		r25,MINUTES_REGISTER
	call	ds1307GetDateTime
	mov		r17,r24
                   ;code for clock
     call    pBCDtoASCII
    mov    r16,r17
    call    putchUSART0
    mov    r16,r18
    call    putchUSART0





    ldi    r16,0x3A                               ; ":"
    call    putchUSART0



    ldi		r25,SECONDS_REGISTER
	call	ds1307GetDateTime
	mov		r17,r24

     call    pBCDtoASCII
    mov    r16,r17
    call    putchUSART0
    mov    r16,r18
    call    putchUSART0

      lds r16, cstate
      cpi r16, IDLES
   breq alpha                    ;where to go next
      cpi r16, COOKS
   breq finish
   cpi r16, SUSPENDS
   breq finish
   cpi r16, DATAS
   breq finish

 alpha:
                             ;alphanumeric stuff
    ldi		r25,HOURS_REGISTER
	call	ds1307GetDateTime
  mov		r17,r24
  call    pBCDtoASCII
  mov r25,r18
  mov r16, r17
  ldi r17, 0
  call   anWriteDigit

   mov r16, r25
  ldi r17, 1
  call   anWriteDigit



 ldi		r25,MINUTES_REGISTER
	call	ds1307GetDateTime
  mov		r17,r24
  call    pBCDtoASCII
  mov r25,r18
  mov r16, r17
  ldi r17, 2
  call   anWriteDigit

   mov r16, r25
  ldi r17, 3
  call   anWriteDigit


    finish:


    ret

  displayCookTime:
           ;serial io
  lds r16, seconds
                    lds r17, seconds+1
                    call itoa_short

                    ldi r16, 0
                    sts tascii+5, r16
                    sts tascii+6, r16
                    sts tascii+7, r16
                     ldi zl, low(tascii)
                     ldi zh, high(tascii)
                    call putsUSART0

      lds r16, cstate
       cpi r16, STARTS
   breq finish2
      cpi r16, IDLES
   breq finish2                    ;where to go next
      cpi r16, COOKS
   breq aalpha
   cpi r16, SUSPENDS
   breq aalpha
   cpi r16, DATAS
   breq aalpha





  aalpha:            ;alphanumeric
	lds	r16,seconds		; Get current timer seconds
	lds	r17,seconds+1
	ldi	r18,60			; 16-bit Divide by 60 seconds to get mm:ss
	ldi	r19,0			; answer = mm, remainder = ss
	call	div1616
	mov	r4,r0			; Save mm in r4
	mov	r5,r2			; Save ss in r5
	mov	r16,r4			; Divide minutes by 10
	ldi	r18,10
	call	div88
	ldi	r16,'0'			; Convert to ASCII
	add	r16,r0			; Division answer is 10's minutes
	ldi	r17,0
	call	anWriteDigit	; Write 10's minutes digit
	ldi	r16,'0'			; Convert ASCII
	add	r16,r2			; Division remainder is 1's minutes
	ldi	r17,1
	call	anWriteDigit	; Write 1's minutes digit
	mov	r16,r5			; Divide seconds by 10
	ldi	r18,10
	call	div88
	ldi	r16,'0'			; Convert to ASCII
	add	r16,r0			; Division answer is 10's seconds
	ldi	r17,2
	call	anWriteDigit	; Write 10's seconds digit
	ldi	r16,'0'			; Convert to ASCII
	add	r16,r2			; Division remainder is 1's seconds
	ldi	r17,3
	call	anWriteDigit	; Write 1's seconds digit

  finish2:
	ret

