#!/usr/bin/python

import  RPi.GPIO as GPIO
import time
import sys, os

### To-Do
#  (Done? Need to test.) Shutdown more gracefully : http://raspi.tv/2013/rpi-gpio-basics-3-how-to-exit-gpio-programs-cleanly-avoid-warnings-and-protect-your-pi
# Add LIRC?  Not sure how to interrupt those 'waits' with button presses.

#in basement ONLY, check for ZOOM before playing (figure out how to check hostname):
#zoom=os.system("lsusb |grep ZOOM")
#
#print ("Zoom:")
#print (zoom)

# The hardware side is 2 buttons (one play/skip, one stop) and one LED:
#     off = STOP, on = PLAY, fast-blink = command received, slow-blink = waiting for current song to end to stop and await further instructions.


LEDPin = 15 #15 or 27?
StopPin = 17
PlayPin = 18

GPIO.setmode(GPIO.BCM)
GPIO.setup(LEDPin, GPIO.OUT)
GPIO.setup(StopPin, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(PlayPin, GPIO.IN,pull_up_down=GPIO.PUD_UP)

play_command = "~/bin/myplayer.pl -cj &"
stop_command = "~/bin/myplayer.pl -a"
stop_flag=0

def ledon():
    GPIO.output(LEDPin, GPIO.HIGH)
def ledoff():
    GPIO.output(LEDPin, GPIO.LOW)

def fastblink(fr):
    for x in range(0,fr):
        ledon
        time.sleep(.1)
        ledoff
        time.sleep(.1)

def slowblink(sr):
    for x in range(0,sr):
        ledon
        time.sleep(.5)
        ledoff
        time.sleep(.5)

long= 5 # # of blinks constants
short = 3
flash = 1

print "Waiting to do something . . . "
try:
    while True:
        stop_button = not GPIO.input(StopPin)
        play_button = not GPIO.input(PlayPin)
        ps=os.system("ps aux |grep 'myplayer.pl -cj' |grep -v grep >/dev/null")
        if (ps==0):   #Playing (reverse logic, here, ps returns 0 if process found, 256 if not.
            if (stop_flag == 1):
                slowblink(flash)
            else: 
                ledon()
            if (stop_button):
                fastblink(long)
                print("Stop button pressed.")
                if (stop_flag == 1):
                    print ("Already put the brakes on, waiting for this song to end, hold on to your horses!")
                else:
                    print("Stopping after this song finishes.")
#                    ledoff()
                    os.system(stop_command)
                    stop_flag = 1
                    slowblink(flash)
    #            time.sleep(2)
            elif (play_button):  # Optional: read 'play' and skip current song?
                print("Killing current song!")
                fastblink(flash)
                os.system('killall mpg123')
        else:
    #        playing = 0
            ledoff()
            if (stop_flag==1):
                print("Fully stopped.")
                stop_flag = 0
            if (play_button):
                print("Play button pressed.")
                print("Starting jukebox . . . ")
                fastblink(flash)
                os.system(play_command)
                fastblink(flash)
    #            time.sleep(5)
#Need this? time.sleep(.1)
        
except KeyboardInterrupt:  
    # here you put any code you want to run before the program   
    # exits when you press CTRL+C  
    print "Exiting gracefully.\n" # Print something on exit.
  
except:  
    # this catches ALL other exceptions including errors.  
    # You won't get any error messages for debugging  
    # so only use it once your code is working  
    print "Other error or exception occurred!"  
  
finally:  
    GPIO.cleanup() # this ensures a clean exit
