#!/usr/bin/python

import  RPi.GPIO as GPIO
import time
import sys, os

#in basement ONLY, check for ZOOM before playing (figure out how to check hostname):
#zoom=os.system("lsusb |grep ZOOM")
#
#print ("Zoom:")
#print (zoom)

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

def fastblink():
    for x in range(0,5):
        GPIO.output(LEDPin, GPIO.HIGH)
        time.sleep(.1)
        GPIO.output(LEDPin, GPIO.LOW)
        time.sleep(.1)

def slowblink():
    for x in range(0,2):
        GPIO.output(LEDPin, GPIO.HIGH)
        time.sleep(.5)
        GPIO.output(LEDPin, GPIO.LOW)
        time.sleep(.5)

def ledon():
    GPIO.output(LEDPin, GPIO.HIGH)
def ledoff():
    GPIO.output(LEDPin, GPIO.LOW)


print "Waiting to do something . . . "
while True:
    stop = GPIO.input(StopPin)
    play = GPIO.input(PlayPin)
    ps=os.system("ps aux |grep 'myplayer.pl -cj' |grep -v grep >/dev/null")
    if (ps==0):   #Playing  # Optional: read 'play' and skip current song?
        if (stop_flag == 1):
            slowblink()
        else: 
            ledon()
        if (stop == False):
            print("Stop button pressed.")
            if (stop_flag == 1):
                print ("Already put the brakes on, waiting for this song to end, hold on to your horses!")
            else:
                print("Stopping after this song finishes.")
                ledoff()
                os.system(stop_command)
                stop_flag = 1
                slowblink()
#            time.sleep(2)
        elif (play == False):
            print("Killing current song!")
            fastblink()
            os.system('killall mpg123')
            
    else:
#        playing = 0
        ledoff()
        if (stop_flag==1):
            print("Fully stopped.")
            stop_flag = 0
        if (play == False):
            print("Play button pressed.")
            print("Starting jukebox . . . ")
            os.system(play_command)
            fastblink()
#            time.sleep(5)
    time.sleep(.1)
    