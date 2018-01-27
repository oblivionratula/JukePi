#!/usr/bin/python

import  RPi.GPIO as GPIO
import time
import sys, os
import lirc

sockid = lirc.init("jukebox_ctrl", blocking=False)
### To-Do
#  (Done? Need to test.) Shutdown more gracefully : http://raspi.tv/2013/rpi-gpio-basics-3-how-to-exit-gpio-programs-cleanly-avoid-warnings-and-protect-your-pi
# Add LIRC?  Not sure how to interrupt those 'waits' with button presses.

#in basement ONLY, check for ZOOM before playing (figure out how to check hostname):
#zoom=os.system("lsusb |grep ZOOM")
#
#print ("Zoom:")
#print (zoom)

# The hardware side is IR receiver and one LED:
#     off = STOP, on = PLAY, fast-blink = command received, slow-blink = waiting for current song to end to stop and await further instructions.


LEDPin = 3 # 3 for IR rig, 15 for pushbutton rig?

GPIO.setmode(GPIO.BCM)
GPIO.setup(LEDPin, GPIO.OUT)

play_command = "~/bin/myplayer.pl -cj &"
stop_command = "~/bin/myplayer.pl -a"
stop_flag=0

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
        play_button = 0
        stop_button = 0
        ir = lirc.nextcode()
        if (len(ir)==1):
            ir = str(ir[0])
        else:
            ir = ''
#        print ir        
        if (ir == 'play'):
            play_button = 1
            print "In here"
        elif (ir == 'stop'):
            stop_button = 1
        elif (ir == 'skip'):
            play_button = 1
#        stop_button = not GPIO.input(StopPin)
#        play_button = not GPIO.input(PlayPin)
        ps=os.system("ps aux |grep 'myplayer.pl -cj' |grep -v grep >/dev/null")
        if (ps==0):   #Playing (reverse logic, here, ps returns 0 if process found, 256 if not.
            if (stop_flag == 1):
                blink(slow,flash)
            else: 
                ledon()
            if (stop_button):
                blink(fast,long)
                print("Stop button pressed.")
                if (stop_flag == 1):
                    print ("Already put the brakes on, waiting for this song to end, hold on to your horses!")
                else:
                    print("Stopping after this song finishes.")
#                    ledoff()
                    os.system(stop_command)
                    stop_flag = 1
                    blink(slow,flash)
    #            time.sleep(2)
            elif (play_button):  # Optional: read 'play' and skip current song?
                print("Killing current song!")
                blink(fast,flash)
                os.system('killall mpg123')
        else:  # NOT playing
            ledoff()
            if (stop_flag==1):
                print("Fully stopped.")
                stop_flag = 0
#            else:
#                blink(2,flash)
            if (play_button):
                print("Play button pressed.")
                print("Starting jukebox . . . ")
                blink(fast,flash)
                os.system(play_command)
                blink(fast,flash)
    #            time.sleep(5)

        time.sleep(.1) # Need so there's time to catch keyboard interrupt???
        
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
    lirc.deinit()
    