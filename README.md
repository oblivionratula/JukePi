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

jukebox.py is the main script. Anything else is jsut my hacking/testing, etc. 

I don't know that I'll maintain this, but if you want to submit pull requests, I guess I'll try to figure out how to handle that. 

For now, this does what I want, but I may also be looking to add an LIRC component.

Testing:  I think I need to more gracefully exit (keyboard interrupt or something) and release the GPIO pins? Because currently I get "Already in use" warnings, but things work.

Enjoy/don't laugh too hard.

