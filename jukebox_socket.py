#!/usr/bin/python

import  RPi.GPIO as GPIO
import time
import sys, os
import socket
import select

# Socket tinkering based on https://www.geeksforgeeks.org/socket-programming-python/
# And https://pymotw.com/2/select/
# set up socket
s = socket.socket()
s.setblocking(0)
port = 49123
socket_timeout = 1
s.bind(('', port))
print "Created listening socket on port %s " %(port)
s.listen(1)

inputs = [ s ]
outputs = [ ]
### To-Do
#  Make killcodes client-specific
# Combine pushbutton and LIRC modes in one script w/commmand line switch

#  Done: Need to test.) Shutdown more gracefully : http://raspi.tv/2013/rpi-gpio-basics-3-how-to-exit-gpio-programs-cleanly-avoid-warnings-and-protect-your-pi
#  Done (in separate script): Add LIRC?  Not sure how to interrupt those 'waits' with button presses.

# The hardware side is 2 buttons (one play/skip, one stop) and one LED:
#     off = STOP, on = PLAY, fast-blink = command received, slow-blink = waiting for current song to end to stop and await further instructions.

LEDPin = 23 # Physical #16  Was 15 #15 or 27?
StopPin = 27 # Physical # 13  Was 17
PlayPin = 22 # Physical 13  Was 18
   # Groud is any ground but now physical 14 makes sense

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

def check_buttons(socket_command):
# Some useful constants:
    long= 5
    short = 3
    flash = 1
    fast = .1
    slow = .5
    stop_flag=0
    play_command = "~/bin/myplayer.pl -cj &"
    #stop_command = "~/bin/myplayer.pl -a"
    stop_command = "~/bin/killmyplayer.pl"
    stop_button = not GPIO.input(StopPin)	# Use 'not' b/c the are pull-down switches
    if (socket_command == 's'):
        stop_button = 1
    play_button = not GPIO.input(PlayPin)
    if (socket_command == 'p'):
        play_button = 1
    if (socket_command == 'k'):
        kill_me_now = 1
    else:
        kill_me_now = 0

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
        elif (play_button or kill_me_now):  	# Optional: read 'play' and skip current song?
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

# Here we go!
print "Waiting to do something . . . "
try:
    while True:		   # Main loop
        check_buttons(None)
        # Establish connection with client.
        readable, writable, exceptional = select.select(inputs, outputs, inputs, socket_timeout)
        if not (readable or writable or exceptional):
        #    print >>sys.stderr, '  timed out, do some other work here'
            continue
        for in_s in readable:
            if in_s is s:
                #Readable socket is ready
                connection, client_address = in_s.accept()
                connection.setblocking(0)
                inputs.append(connection)
            #    message_queues[connection] = Queue.Queue()
            else:
                data = in_s.recv(1)
                if data in ('p','s','k'):
                    print "Received a command from ", client_address, ": ", data
                    check_buttons(data)
                else:
                    # Interpret empty result as closed connection
                    print >>sys.stderr, 'closing', client_address, 'after reading no data'
                    # Stop listening for input on the connection
                    if in_s in outputs:
                        outputs.remove(in_s)
                    inputs.remove(in_s)
                    in_s.close()
    # Handle "exceptional conditions"
    for in_s in exceptional:
        print >>sys.stderr, 'handling exceptional condition for', in_s.getpeername()
        # Stop listening for input on the connection
        inputs.remove(in_s)
        if in_s in outputs:
            outputs.remove(in_s)
        in_s.close()

#        c, addr = s.accept()
#        rec_command = c.recv(1)
#        if not rec_command:
#            c.close()
#            break
#        else:
#            print "Got command:"
#            print rec_command
        # Check buttons
        check_buttons(None)

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
    s.close
    GPIO.cleanup() # this ensures a clean exit
