# Emstrument

Emstrument [emulator + instrument] is an experimental open-source Lua module
which can be used to be convert retro games into new musical instruments or
interactive musical compositions. Using an emulator that supports Lua scripting, in-game 
events can be used as triggers for notes and controls to manipulate sounds.
It's basically a mod for your virtual game console that adds connectors for your audio gear.
Emstrument outputs standard MIDI for simple integration with existing digital music workflows
(or even MIDI-compatible DJ software).

If this is hard to understand, watch the demo video for a more intuitive look at
what Emstrument is designed to do: [signalnarrative.com/emstrument](http://www.signalnarrative.com/emstrument)

Emstrument is currently only implemented for OS X, with ports for Windows and
Linux possible if there is enough interest from musicians/developers. If you
want to make a port, fork away!

### Emstrument != Chiptune

Emstrument is the inverse of the "chiptune" genre of music. Chiptune
music is produced by taking the sounds from a game and arranging them using
traditional musical interfaces (keyboard, sequencer, etc), which
means the game is taken out of the musical equation at an early stage. By
contrast, Emstrument uses the user 
interaction, algorithms and design of the game as a musical interface to control _any_
kind of sound, highlighting the game itself. However, they are not mutually exclusive;
Emstrument can be used to generate chiptune sounds, bringing the whole game-music 
relationship full circle.

### New musical instruments

Emstrument allows musicians to use games as a new kind of instrument, using interactions 
and algorithms/data from the game to manipulate sound in new ways that cannot be 
recreated with traditional musical interfaces. The visual component also adds a new
dimension to the music, which allows non-musicians to better understand the
musical concepts at play. These instruments create a new kind of gameplay where
you not only have to succeed at the game, but play "musically" (follow a rhythm, play in 
key, etc).

Emstrument also allows developers interested in making music-based games to
develop or prototype on top of recognizable classic games, instead of having 
to build or rebuild existing games from the ground up.

### Interactive algorithmic compositions

Emstrument is not limited to controlling one instrument at a time; it can be used to create
interactive full musical compositions that are
influenced by the player's in-game choices. These compositions can be standalone 
audiovisual pieces, or can be a replacement for the primitive scores and sound effects 
found in retro games, creating a new way to experience an existing game.

These compositions fit into a new category of generative music called
inter-algorithmic composition (IAC), since the composer creates algorithms that
interface with the algorithms already present in the game. For example, in a
composition built on top of Pac-Man, the actual notes being played might be
triggered by the movements of the ghosts, which are controlled by the
well-documented algorithms for each ghost, which were written decades ago.

### Ease of use

Emstrument is a module for Lua, a simple scripting language that is easy
to learn for anyone with coding experience. It deals with MIDI hassles like
timing and avoiding redundant messages under the hood to let users concentrate
more on the music. The actual source code is written in C and should be
fairly easy to modify and build.

Scripts that convert a game into a musical instrument can be written in well under 100
lines of code, and a generative score for a game can be done in a few
hundred lines. Examples can be found in the repository under [scripts/](scripts/).

Scripts are not limited to what's in the game, since emulators with Lua support
generally have a Lua API for drawing on the screen, loading save states, etc. which can be used
for augmented visuals or for loop-based music, respectively.

Emstrument has been tested with Logic Pro X, Ableton Live and GarageBand, and
should be compatible with any CoreMIDI-compatible software.

Final note: It would be really cool if someone wrote a script that uses LSDj or 
a similar chiptune tracker to act as a tracker for non-chiptune sounds...





