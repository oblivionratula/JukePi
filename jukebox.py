#!/usr/bin/python

import  RPi.GPIO as GPIO
import time
import sys, os

### To-Do
#  Make killcodes client-specific
# Combine pushbutton and LIRC modes in one script w/commmand line switch

#  Done: Need to test.) Shutdown more gracefully : http://raspi.tv/2013/rpi-gpio-basics-3-how-to-exit-gpio-programs-cleanly-avoid-warnings-and-protect-your-pi
#  Done (in separate script): Add LIRC?  Not sure how to interrupt those 'waits' with button presses.

# The hardware side is 2 buttons (one play/skip, one stop) and one LED:
#     off = STOP, on = PLAY, fast-blink = command received, slow-blink = waiting for current song to end to stop and await further instructions.

play_command = "~/bin/myplayer.pl -cj &"
#stop_command = "~/bin/myplayer.pl -a"
stop_command = "~/bin/killmyplayer.pl"

LEDPin = 15 #15 or 27?
StopPin = 17
PlayPin = 18
GPIO.setmode(GPIO.BCM)
GPIO.setup(LEDPin, GPIO.OUT)
GPIO.setup(StopPin, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(PlayPin, GPIO.IN,pull_up_down=GPIO.PUD_UP)

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

# Some useful constants:
long= 5 
short = 3
flash = 1
fast = .1
slow = .5

stop_flag=0
# Here we go!
print "Waiting to do something . . . "
try:
    while True:		   # Main loop
        stop_button = not GPIO.input(StopPin)	# Use 'not' b/c the are pull-down switches
        play_button = not GPIO.input(PlayPin)
        # Find out if we  (or someone else?) is already playing.
        # Reverse logic here, ps returns 0 if process found, 256 if not.
        ps=os.system("ps aux |grep 'myplayer.pl -cj' |grep -v grep >/dev/null")     
        if (ps==0):   			# Yes, playing
            if (stop_flag == 1):	# But got we got asked to stop
                blink(slow,flash)	# So we slow blink until song ends.
            else: 
                ledon()			# Steady LED if playing unabated.
            if (stop_button):		# Stop command received
                blink(fast,long)	# Show we got a command
                print("Stop button pressed.")
                if (stop_flag == 1):	# We already know . . . Not really needed, just barfs 'status.'
                    print ("Already put the brakes on, waiting for this song to end, hold on to your horses!")
                else:
                    print("Stopping after this song finishes.")
#                    ledoff()
                    os.system(stop_command) # System call to actually plant kill seed. Need a way to make this client-specific.
                    stop_flag = 1
                    blink(slow,flash)
            elif (play_button):  	# Optional: read 'play' and skip current song?
                print("Killing current song!")
                blink(fast,flash)
                os.system('killall mpg123')
        else:  				# NOT playing
            ledoff()			# No LED while full-stopped
            if (stop_flag==1):
                print("Fully stopped.")
                stop_flag = 0		# Clear the brakes after full-stop
            if (play_button):		# But now getting pressed into action again!
                print("Play button pressed.")
                print("Starting jukebox . . . ")
                blink(fast,flash)	# Acknowledge button press
                os.system(play_command)	# System call.
                blink(fast,flash)	# Confirm again w/ fast flash because play call can be slow on old Pi

        time.sleep(.1) 			# Need so there's time to catch keyboard interrupt???
        
except KeyboardInterrupt:  
    # here you put any code you want to run before the program   
    # exits when you press CTRL+C  
    print "Exiting gracefully.\n" # Print something on exit.
  
except:  
    # this catches ALL other exceptions including errors.  
    #MEM note: This does not catch 'killall' (defautl sig. 9?)
    # You won't get any error messages for debugging  
    # so only use it once your code is working  
    print "Other error or exception occurred!"  
  
finally:  
    GPIO.cleanup() # this ensures a clean exit
