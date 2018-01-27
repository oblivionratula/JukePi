#!/usr/bin/python

import  RPi.GPIO as GPIO
import time
import sys, os

LEDPin = 3 # 3 for IR rig, 15 for pushbutton rig?

GPIO.setmode(GPIO.BCM)
GPIO.setup(LEDPin, GPIO.OUT)

def ledon():
    GPIO.output(LEDPin, GPIO.HIGH)
def ledoff():
    GPIO.output(LEDPin, GPIO.LOW)

def blink(rate,repeats):
    for x in range(0,repeats):
        ledon()
        time.sleep(rate)
        ledoff()
        time.sleep(rate)

long= 5 # # of blinks constants
short = 3
flash = 1
fast = .1
slow = .5

print "Waiting to do something . . . "
try:
    while True:
        print("Blinking")
        blink(fast,long)        
        time.sleep(.1) # Need so there's time to catch keyboard interrupt???
        print("Long on")
        blink(5,1)
except KeyboardInterrupt:  
    # here you put any code you want to run before the program   
    # exits when you press CTRL+C  
    print "Exiting gracefully.\n" # Print something on exit.
  
except:  
    # this catches ALL other exceptions including errors.  #MEM note: This does not seem to catch 'killall'
    # You won't get any error messages for debugging  
    # so only use it once your code is working  
    print "Other error or exception occurred!"  
  
finally:  
    GPIO.cleanup() # this ensures a clean exit
