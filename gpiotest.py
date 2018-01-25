#!/usr/bin/python

import  RPi.GPIO as GPIO
import time

GPIO.setmode(GPIO.BCM)
GPIO.setup(2, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(3, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(4, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(17, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(27, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(22, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(10, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(9, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(11, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(14, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(18, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(15, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(24, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(23, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(8, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(7, GPIO.IN,pull_up_down=GPIO.PUD_UP)
GPIO.setup(25, GPIO.IN,pull_up_down=GPIO.PUD_UP)

print "Waiting to do something . . . "
while True:
    in2 = GPIO.input(2)
    in3 = GPIO.input(3)
    in4 = GPIO.input(4)
    in17 = GPIO.input(17)
    in27 = GPIO.input(27)
    in22 = GPIO.input(22)
    in10 = GPIO.input(10)
    in9 = GPIO.input(9)
    in11 = GPIO.input(11)
    in14 = GPIO.input(14)
    in18 = GPIO.input(18)
    in15 = GPIO.input(15)
    in24 = GPIO.input(24)
    in23 = GPIO.input(23)
    in8 = GPIO.input(8)
    in7 = GPIO.input(7)
    in25 = GPIO.input(25)
    
    if (in2 == False):
        print("Pin 2")
    if (in3 == False):
        print("Pin 3")
    if (in4 == False):
        print("Pin 4")
    if (in17 == False):
        print("Pin 17")
    if (in27 == False):
        print("Pin 27")
    if (in22 == False):
        print("Pin 22")
    if (in10 == False):
        print("Pin 10")
    if (in9 == False):
        print("Pin 9")
    if (in11 == False):
        print("Pin 11")
    if (in14 == False):
        print("Pin 14")
    if (in18 == False):
        print("Pin 18")
    if (in15 == False):
        print("Pin 15")
    if (in24 == False):
        print("Pin 24")
    if (in23 == False):
        print("Pin 23")
    if (in8 == False):
        print("Pin 8")
    if (in7 == False):
        print("Pin 7")
    if (in25 == False):
        print("Pin 25")

    time.sleep(1)
    