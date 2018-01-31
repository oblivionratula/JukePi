# JukePi

Just learning python/GPIO hacking.
And I'm still learning GitHub.
Hopefully this is useful/amusing to someone.

This is a Raspberry Pi-based controller for a software-based MP3 player. 
Pay attention to the GPIO pins assigned and adjust accordingly.
This is ONLY the controller. It calls other software (to be added?) that does the heavy lifting. If can be edited to do anything.
This is surely not the best way to do things, but it's what I've figured out.

The hardware side is 2 buttons (one play/skip, one stop) and one LED:
    off = STOP, on = PLAY, fast-blink = command received (not universal), slow-blink = waiting for current song to end to stop and await further instructions.

Will add hardware diagram and/or pics when able.

Main scripts:
jukebox.py is the pushbutton (original) version.
irjuke.py is a version that enbles remote control via lirc. It does not use any physical buttons, but still has the LED for status. LIRC takes a bit of set-up, but I'll try to document specifics or point to general resources.  My IR receiver is hacked from an old Sony rear projection TV, but components are very cheap (as long as you're ordering something else at the time. A cheap DSO-138 digital oscilloscope was ciritcal in me troubleshooting the IR receiver.
I could probably make this one script with a command line switch, but for now, it is two. And may stay that way. We'll see.

IR setup (in progress/incomplete):
First, on a Pi, edit (sudo) /boot/config.txt with the following line (at the end is fine):
dtoverlay=lirc-rpi,gpio_in_pin=2 

Also, edit (sudo again) /etc/modules and add:
lirc_dev
lirc_rpi gpio_in_pin=2
 
Set the pin number to wherever your IR signal line is going.  I don't know if that redundance is needed, but it's what works for me. You can set an out pin, too, if you're making an IR blaster, but that's not at all handled here.

Reboot after changes.

Also need to:
sudo apt-get install python-lirc

There is an example lircd.conf file, but it only works with my specific remote - you'd need to use irrecord to grab your version of the truth (once you confrm you can see IR action with: mode2 -d /dev/lirc0
E.g.: /etc/ini.d/lirc stop
	irrecord -d /dev/lirc0 ~/.lircd.conf
You need to at least grab recordings of keys KEY_PLAY and KEY_STOP. Others are optional (since KEY_NEXTSONG is just a duplicate of PLAY right now and KEY_PAUSE is unimplemented.)
That file gets copied to /etc/lirc

/etc/lirc/hardware.conf needs configured/copied as well. I've included mine for reference.
Commenting out the LIRCD_ARGS line goes against a lot of suggetions in other docs, but this is what worked for me.

lircrc should reside as ~/.lircrc or as in a system-wide location if more than one user needs it.  This file is what translates received button presses into program calls. It's critical. It should work for our purposes here as-is, but if you want to/already do control other things, you'll meed to merge this in.
use irw for troubleshooting (man irw)

### Got to run, leaving off here, but hopefully this gets someone started.
### A few URLs I used:
http://www.lirc.org/html/configure.html#lircd.conf_format
https://www.raspberrypi.org/forums/viewtopic.php?t=7798&start=100
https://www.raspberrypi.org/forums/viewtopic.php?t=159035
https://github.com/tompreston/python-lirc/blob/4091fe918f3eed2513dad008828565cace408d2f/README.md
And of course for picking pins (for the IR version, I got 4 in a square so i could use a 2x2 header): https://www.raspberrypi.org/documentation/usage/gpio-plus-and-raspi2/README.md


Any other files are just my hacking/testing, etc. 

I don't know that I'll maintain this, but if you want to submit pull requests, I guess I'll try to figure out how to handle that. 

For now, this does what I want, but I may also be looking to add an LIRC component.

Done:  I think I need to more gracefully exit (keyboard interrupt or something) and release the GPIO pins? Because currently I get "Already in use" warnings, but things work.

Enjoy/don't laugh too hard.
