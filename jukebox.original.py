#!/usr/bin/python

import  RPi.GPIO as GPIO
import time
import sys, os

GPIO.setmode(GPIO.BCM)
GPIO.setup(17, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(18, GPIO.IN,pull_up_down=GPIO.PUD_UP)

play_command = "~/bin/myplayer.pl -cj &"
stop_command = "~/bin/myplayer.pl -a"
running = 0

print "Waiting to do something . . . "
while True:
    stop = GPIO.input(17)
    play = GPIO.input(18)
    ps=os.system("ps |grep 'myplayer.pl -cj' >/dev/null")
    # ps == 0 means mpg123 is running  else, stopped
    # running -1 means stop was given, but we're still waiting for the song to end.
    if (ps==256 and running != 0):
        print("Fully stopped.")
        running = 0
    if (play == False):
        print("Button press Play")
        if (running == 0 and ps==256):
            print("Starting jukebox . . . ")
            os.system(play_command)
            running = 1
        else:
            print ("Jukebox already running . . . ")
        time.sleep(5)
    elif (stop == False):
        if (ps == 0):
            if (running == -1):
                print ("Already stopped, waiting for this song to end, hold on to your horses!")
            elif (running == 1):
                print("Button press Stop")
                os.system(stop_command)
                running = -1
        else:
            print("Not running, what are you trying to stop???")
        time.sleep(5)
    time.sleep(.1)
    