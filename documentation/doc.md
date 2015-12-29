# Emstrument: Documentation

### Basic Concepts:
Emstrument [emulator + instrument] is a Lua module for use alongside an emulator
or game that supports Lua scripting. It can be used to convert a game into a
virtual musical instrument or to create interactive musical compositions.
Possible uses include educating non-musicians on musical concepts in a framework
they can easily understand, creating adaptive soundtracks to replace the
simplistic music found in many older games, or creating an audiovisual element for
live music performance.

When initialized, Emstrument creates a virtual MIDI source - think of it as a
MIDI keyboard/controller that only exists inside the user's computer. Using
Emstrument's MIDI commands is like pressing keys and adjusting knobs on that
virtual keyboard. The virtual MIDI source is automatically connected to any active software MIDI
instrument, which uses those commands to generate sound. The MIDI commands can 
be sent to external hardware, but only through digital audio workstation 
software, not directly (which should be more convenient for most musicians
working with MIDI hardware who have established workflows in their DAW).

Emstrument can be used by any game or emulator that support running Lua scripts at 
regular intervals (usually once per video frame). The API queues up MIDI commands and then 
processes and sends them all at the same time (usually once at the end of the script's 
per-frame loop iteration). This allows for more precise timing (all the
notes are sent at nearly the same time), and allows Emstrument to intelligently remove
duplicate/redundant MIDI messages and perform bookkeeping to prevent ambiguous
cases like having the same note playing twice at the same time (which is allowed
by MIDI, but can sometimes cause stuck notes and various other ambiguities).

### MIDI Concepts:
MIDI is a much more extensive subject than can be covered here, but here's some
basic information which is useful to know before using Emstrument.

 - *Channel* - MIDI supports output on 16 channels (1 through 16). Emstrument
 sends all MIDI messages on channel 1 by default, but relevant functions have an
 optional argument that allows the channel to be specified manually. Using
 different channels, notes and control changes can be sent to different
 instruments. Most digital audio workstation (DAW) software supports some form
 of routing to virtual instruments based on channel, allowing Emstrument to
 control several instruments independently. 
 - *Note* - Notes passed to
 Emstrument functions are integers in the range of 0 through 127 (inclusive),
 with 0 being the lowest playable note and 127 being the highest. The function
 MIDI.notenumber() takes a string indicating a note based on key and octave and
 returns the corresponding note's number. Not all MIDI instruments will be able
 to play the full range of notes (for example, a piano usually has only 88 keys)
 - *Velocity* - An integer in the range of 1 (soft) to 127 (loud) indicating how
 hard a virtual key was pressed. Warning: A velocity of 0 results in no action
 being taken - MIDI specifies that velocity 0 is equivalent to a note-off
 message, but Emstrument does not send any message with velocity 0 in order to
 prevent ambiguity. 
 - *Control change (CC)* - A way to control instruments'
 parameters to change what notes sound like. There are 120 different controls, in the range
 0 through 119. The most commonly used is control 1, modulation/mod wheel. An
 official full list can be found at
 [midi.org/techspecs/midimessages.php](http://www.midi.org/techspecs/midimessages.php) [see table 3]. Each control
 takes an integer in range 0 through 127. Note that pitch bend is not a control
 change, although a user could map pitch bend-like changes to a control change
 in their MIDI instrument.
 - *Pitch bend* - A parameter that lets instruments
 smoothly change between notes. Emstrument takes a decimal number between -1.0
 and 1.0 which are mapped to maximum pitch bend down and up, respectively.
 The MIDI instrument's configuration determines the range of the pitch bend 
 (in semitones)



### API Documentation:

#### `MIDI.init()`
Takes no arguments. Sets up Emstrument's MIDI functions and internal data
structures. This function must be called once before any other MIDI functions can be
used (or else an error is raised).


#### `MIDI.configuretiming(duration_units, [note_on_delay])`
Sets the values of duration units and note-on delay, in milliseconds (e.g 0.005 seconds = 5
milliseconds). By default, durations in Emstrument are specified in 60ths of a
second, to match the typical 60hz framerate used by most games/emulators.
However, this can be changed to match 50Hz PAL games (20ms), or to any other
value that suits the current Emstrument script.

Note-on delay is a special optional parameter that controls how long Emstrument
waits before sending a note-on message after sending a note-off message for the
same note. This was introduced to address a problem encountered during
development where both the note-on and note-off messages had the same timestamp
and the DAW re-ordered them to turn the note-on before turning it off, causing
no sound to be generated.

Note-on delay is zero by default, since DAW software usually correctly
interprets the 2 messages. However, a small delay (in the order of a few
milliseconds) should be introduced if notes that instantaneously turn off are
observed when re-triggering the same note.


#### `MIDI.notenumber(note_name)`
Returns the number of the MIDI note for note_name (a string). note_name is a
string of 2 to 4 characters formatted as follows: `"KAO"` 

- `K`: Key. Can be
A,B,C,D,E,F,G or a,b,c,d,e,f,g 
- `A`: Accidental (optional). Can be '#' (sharp)
or 'b' (flat). Double sharps, etc. are not supported. 
- `O`: Octave. Ranges from
-2 to 8. Each octave starts at C, so "B5" is above "C5", and "A3" is above "G3",
etc.

The highest note supported by MIDI (but not necessarily every MIDI instrument)
is "G8", the lowest is "C-2". Emstrument treats "C3" as Middle C (note number
60).

Valid note names: `"C4"`, `"g#-1"`, `"Ab6"` Invalid note names: `"C 4"`,
`"Ax3"`, `"Ebb2"`, `"Ab8"` (too high), `"F-3"` (too low)

Emstrument does not explicitly support transposition, so any sequence of notes
written in the key of C will play in the key of C. However, because notes are
eventually represented as numbers, simply subtracting or adding the same number
will result in transposition. This wrapper function could be used to transpose
notes:

    function transpose(note_name, semitones) 
        note_number = MIDI.notenumber(note_name); 
        transposed_note_number = note_number + semitones
        if ((transposed_note_number > 127) or (transposed_note_number < 0)) then 
            -- either throw an error or clamp the transposed note number 
        end;
    return transposed_note_number;
    end


#### `MIDI.noteon(note_number, velocity, [channel])`
Queues a note-on command, to be sent when `MIDI.sendmessages()` is called.

Arguments: 

- *note_number*: integer in range [0,127] 
- *velocity*: integer
in range [1,127] 
- *channel*: optional integer in range [1,16]. Value is 1 if no
channel is specified

Once the note-on message is sent, the note will continue playing until one of
the following: 

- `MIDI.noteoff()` is called with the same note and channel,
preceding a call to `MIDI.sendmessages()` 
- `MIDI.allnotesoff()` is called with the same
channel, preceding a call to `MIDI.sendmessages()` 
- The same note is turned on again,
preceding a call to `MIDI.sendmessages()`.

If this function, or MIDI.noteonwithduration() is called more than once with the
same note and channel preceding `MIDI.sendmessages()`, all but the most recent
note-on command will be cleared from the queue. If this function is called while
the specified note is already playing on the channel, that note will be turned
off by `MIDI.sendmessages()` before being turned on again.

Velocity can be set to 0, but this will result in nothing happening. To turn off
a note without retriggering it, `MIDI.noteoff()` or `MIDI.allnotesoff()` must be
used. If the script ends before a note is turned off, it must be manually turned
off by the user of the MIDI instrument.


#### `MIDI.noteonwithduration(note_number, velocity, duration, [channel])`
Queues a note-on command, to be sent when `MIDI.sendmessages()` is called. The
length of the note is specified by the duration parameter.

Arguments: 

- *note_number*: integer in range [0,127] 
- *velocity*: integer in range [1,127] 
- *duration*: integer greater than 0. The duration is measured by default in 60ths
of a second, this can be changed by using MIDI.configuretiming(). 
- *channel*:
optional integer in range [1,16]. Value is 1 if no channel is specified

Once the note-on message is sent, the note will play for the time specified by
the duration parameter, or until one of the following:

- `MIDI.noteoff()` is
called with the same note and channel, preceding a call to `MIDI.sendmessages()` 
- `MIDI.allnotesoff()` is called with the same channel, preceding a call to
`MIDI.sendmessages()` 
- The same note is turned on again, preceding a call to
`MIDI.sendmessages()`.

If this function is called and the same note/channel is not played again with
MIDI.noteon() or MIDI.noteonwithduration(), after the time specified by
'duration', a note-off message will be sent to turn off the note. However, if
the same note is played before that scheduled note-off message is sent, that scheduled note-off
message is canceled so that the new note will play for as long as is appropriate.

If this function, or MIDI.noteon() is called more than once with the same note
and channel preceding `MIDI.sendmessages()`, all but the most recent note-on
command will be cleared from the queue. If this function is called while the
specified note is already playing on the channel, that note will be turned off
by `MIDI.sendmessages()` before being turned on again. Velocity can be set to 0,
but this will result in nothing happening. To turn off a note without
retriggering it, `MIDI.noteoff()` or `MIDI.allnotesoff()` must be used. If the
script ends before a note is turned off, it must be manually turned off by the
user of the MIDI instrument.


#### `MIDI.noteoff(note_number, [channel])`
Queues a note-off command, to be send when `MIDI.sendmessages()` is called.

Arguments: 

- *note_number*: integer in range [0,127] 
- *channel*: optional
integer in range [1,16]. Value is 1 if no channel is specified

If a note-on command with the same note and channel is queued before a note-off
command before `MIDI.sendmessages()` is called, the note-on command is cleared
from the queue, since it would have been turned off instantly.


#### `MIDI.allnotesoff([channel])`
Queues an "all notes off" command, which turns off all notes playing on a
channel when `MIDI.sendmessages()` is called.

Arguments: 

- *channel*: optional
integer in range [1,16]. Value is 1 if no channel is specified

If a note-on command with the same channel is queued before an "all notes off"
command before `MIDI.sendmessages()` is called, the note-on command is cleared
from the queue, since it would have been turned off instantly.

This command will only turn off notes currently turned on by Emstrument. If notes are
being triggered outside of Emstrument, they will not be turned off, as
Emstrument has no way of knowing that they exist.

Emstrument does not explicitly turn off all 127 notes, because that requires a
high volume of MIDI messages which can get backed up and add latency. This command does not use
control change 123 (all notes off), since it is not enabled by all MIDI implementations.


#### `MIDI.CC(cc_number, cc_value, [channel])`
Queues a CC command, to be sent when `MIDI.sendmessages()` is called.

Arguments: 

- *cc_number*: integer in range [0,120] 
- *cc_value*: integer in
range [0,127] 
- *channel*: optional integer in range [1,16]. Value is 1 if no
channel is specified

If more than one CC command is queued with the same cc_number and channel, all
but the most recent is cleared from the queue.

Note: There is no command in Emstrument to reset all CCs to their original
state, because Emstrument does not have any way to know what those values were
before it started. Control change 121 (reset all controllers) will reset to arbitrary values and also is not enabled by all MIDI implementations.


#### `MIDI.pitchbend(bend_value, [channel])`
Queues a pitchbend command, to be sent when `MIDI.sendmessages()` is called.

Arguments: 

- *bend_value*: decimal number in range [-1.0, 1.0]

If more than one pitchbend command is queued with the same channel, all but the
most recent is cleared from the queue.

#### `MIDI.sendmessages()`
Processes all queued commands to remove duplicates and redundancies, and sends
them out as MIDI messages. This along with `MIDI.init()` is one of the key functions which are required for anything to happen. Usuall this function is called once at the end of each per-frame loop iteration in a script.












