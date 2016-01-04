# Emstrument Setup Guide

##### Preface
Emstrument is currently only implemented for OS X. If there is enough interest,
it can be ported to Linux and Windows, but there needs to be _real_ interest
from musicians, not just "why is this not on [my favorite OS]?", or else it's a
waste of time, since the audience for this is probably small. If you have any 
C audio programming expertise on other platforms, feel free to fork the project and 
port it yourself; there are only a few sections of code that need to be replaced which are highlighted by comments in the code.

There are other options for MIDI in Lua (such as binding C++ MIDI
functions), but you will need to set that up yourself, and because most MIDI
libraries are lower-level than Emstrument you will need to handle things like
timing and keeping track of note-on and note-off pairs in your scripts. Plus
the sample scripts would need to be ported as well.

This guide assumes you have familiarity with using the command line interface.

##### Step 1:
Install Homebrew. Homebrew is an open-source software distribution platform for
OS X. Detailed instructions and information about Homebrew can be found at
[http://brew.sh](http://brew.sh). This may take awhile if you haven't installed the OS X command
line tools, which will be automatically installed (with your permission) when
you install Homebrew.

##### Step 2:
Install modified FCEUX via Homebrew (includes Lua5.1)

>$ brew install homebrew/games/fceux


##### Step 3:
Download `emstrument.so`, or download the source file and compile it yourself
(if you prefer).

This release package: [link](https://github.com/ben-signalnarrative/emstrument/releases/tag/0.1) includes the pre-built library, as well as sample
scripts and projects for Logic Pro X (which only use the stock instruments and
effects). If Ableton is willing to give me a free copy of Live Standard or above 
I'd be happy to recreate these projects for Live.

The pre-built library has been tested on OS X 10.10 and OS 10.11.

If you choose to build it yourself, use this command:

> `gcc -bundle -flat_namespace -undefined suppress -o emstrument.so emstrument.c -I/usr/include/liblua5.1 -llua5.1 -framework CoreMIDI`

This build requires Lua 5.1, which can be installed with brew if you didn't get it with FCEUX:

> $ brew install lua51

##### Step 4:
Install `emstrument.so` in one of the places Lua looks for external libraries:
`./emstrument.so` (the current directory, or one of the directories in $PATH)
 or `/usr/local/lib/lua/5.1/emstrument.so`. You can drag and drop it, or use the `cp` command in the terminal.

##### Step 5:
Open your MIDI-compatible DAW or other audio application.

##### Step 6:
Open FCEUX:

> $ fceux

open an Emstrument Lua script in FCEUX, and open the corresponding ROM.

##### Step 7:
Emstrument should now output MIDI to your MIDI software via FCEUX. Have fun
building your new audiovisual gaming experiences!

Note: During testing on OS X 10.10.5, Ableton Live 9.2 and 9.5 have had issues where virtual
MIDI sources like Emstrument failed to send MIDI to Ableton (it's receiving
something, as the indicator light is flashing, but it doesn't have any effect).
This issue can be resolved by restarting the system.
