All of this code is intended to used with an ATmega328P and is coded in AVR

The microwave simulation should have 5 states

0 is start-up, should display time of day on 14 segment display(can be set in the rtcds1307.asm file) and leave the light/cooker off
1 is idle, should display time of day on 14 segment display
2 is dataentry, should allow you to increment or decrement timer by 10 seconds and display that result on the 14 segment display
3 is cooks, should count down the timer, display it on the 14 segment display, and enter idle state when timer reaches 0
4 is suspends, should freeze the timer and display it on the 14 segment display, continues to cook if door is closed and start key is pressed

if the door is open the state should always be 4, the door open is indicated by the white LED.
