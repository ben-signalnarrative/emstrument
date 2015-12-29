// Emstrument LUA module
// OS X build command (requires lua5.1 installation, change paths as necessary):
// gcc -bundle -flat_namespace -undefined suppress -o emstrument.so emstrument.c -I/usr/include/liblua5.1 -llua5.1 -framework CoreMIDI

#include <stdio.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <CoreMIDI/CoreMIDI.h>

// These functions actually send the MIDI messages, functions beginning with midi_ queue the messages
// which are processed and sent in midi_sendMessages()
static void sendNoteOn(int ch, int note, int vel);
static void sendNoteOnWithDuration(int ch, int note, int vel, int duration, float offset);
static void sendNoteOff(int ch, int note);
static void sendCC(int ch, int CC, int value);
static void sendPitchBend(int ch, int msb, int lsb);
static void sendResetNotes(int ch);

// defines how long '1' is for duration arguments
#define DEFAULT_DURATION_UNIT 16; // roughly 1/60sec by default (in ms)
// defines how long to wait between sending a note off and a note on message for the same note
#define DEFAULT_OFFSET 0 // off by default, can be enabled if users are having timestamp issues

static double duration_unit = DEFAULT_DURATION_UNIT;
static double late_note_offset = DEFAULT_OFFSET;

// For anyone interested in porting Emstrument, these pointers need to be modified to use 
// different libraries than GCD and CoreMIDI.
static MIDIClientRef luaMIDIClient = 0; // these are typedef-ed UInt32s rather than pointers
static MIDIEndpointRef luaMIDIEndpoint = 0;
static dispatch_queue_t luaMIDIQueue = NULL;

// Keep track of whether a note is playing (128 notes on 16 channels)
static bool notePlaying[16][128];

// Keep track of the last note played for each note on each channel so we can 'cancel'
// the timed note-off event if a the same note has been played again since then.
// Note: As a uint8_t, this will fail if a note is played with a duration, and the same note is 
// played exactly a multiple of 256 times between then and the end of its duration.
// Can be avoided to some extent by using a larger-sized uint data type
static uint8_t lastNoteIDs[16][128];

typedef enum  {
    kInvalid = -1,
    kNoteOn,
    kNoteOnWithDuration,
    kNoteOff,
    kCC,
    kPitchBend,
    kResetNotes
} commandType;

typedef struct {
    commandType type;
    int channel;
    // using unions for fake polymorphism
    union {
        int note;       // for note commands: note
        int CC;         // for CC commands: CC
        int MS7b;       // for pitch bend commands: most significant 7 bits
    };
    union {
        int velocity;   // for note on commands: velocity
        int value;      // for CC commands: value
        int LS7b;       // for pitch bend commands: least significant 7 bits
    };
    union {
        int duration;   // duration for note on with duration
    };
} command;

static command *commandQueue = NULL; // Lua API calls add commands to queue.
static uint32_t commandQueueAllocatedSize; // keep track of queue's dynamically allocated size.
static int commandQueueIndex; // points to first free entry in commandQueue.
#define CMD_BLOCK 64 // default size of queue and queue expansions

// Adds command, expanding commandQueue if necessary
static void queueCommand(command c) {
    if (commandQueueIndex == commandQueueAllocatedSize) {
        // expand
        commandQueueAllocatedSize += CMD_BLOCK;
        commandQueue = realloc(commandQueue, commandQueueAllocatedSize * sizeof(command));
    }
    commandQueue[commandQueueIndex] = c;
    commandQueueIndex++;
}

// Called in various functions to make sure everything is in place.
// For anyone interested in porting Emstrument, this function needs to be modified accordingly.
static inline bool initcheck() {
    return (luaMIDIClient && luaMIDIEndpoint && luaMIDIQueue && commandQueue);
}

/******** API calls ********/

// MIDI.init()
// No arguments
// Sets up CoreMIDI objects and other bookkeeping/timing data structures
// For anyone interested in porting Emstrument, this function needs to be modified to use 
// different libraries than GCD and CoreMIDI.
static int midi_init(lua_State *L)
{
    if (!luaMIDIClient && !luaMIDIEndpoint && !luaMIDIQueue) {
        MIDIClientCreate(CFSTR("EnstrumentMIDIClient"), NULL, NULL, &luaMIDIClient);
        MIDISourceCreate(luaMIDIClient, CFSTR("EmstrumentMIDISource"), &luaMIDIEndpoint);
        luaMIDIQueue = dispatch_queue_create("emstrument.lua.midiqueue", DISPATCH_QUEUE_CONCURRENT);
    }
    
    if (!commandQueue) {
        commandQueue = malloc(CMD_BLOCK * sizeof(command));
        commandQueueAllocatedSize = CMD_BLOCK; 
        // initial size = CMD_BLOCK, add CMD_BLOCK more if more commands are queued than capacity.
    }
    commandQueueIndex = 0;

    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 128; j++) {
            notePlaying[i][j] = false;
        }
    }
    
    return 0;
}

// MIDI.configuretiming(durationunit, [noteondelay])
// durationunit: integer, unit of duration in milliseconds (for MIDI.noteonwithduration())
// noteondelay (optional): integer, delay in ms between turning a note off and on again
// If the note-on delay is 0 some applications will write the 2 events at the same timestamp,
// and the note on and note off will cancel each other out
static int midi_configuretiming(lua_State *L)
{
    int args = lua_gettop(L);
    if ((args < 1) || (args > 2)) {
        return luaL_error(L, "Invalid number of arguments to MIDI.configuretiming()");
    }
    
    duration_unit = luaL_checknumber(L, 1);
    if (args == 2) {
        late_note_offset = luaL_checknumber(L, 2);
        printf("Set late note offset to %f\n", late_note_offset);
    }
    
    return 0;
}

// MIDI.notenumber(notename)
// notename is a short string with value "[note][octave]", e.g "c#3" or "Fb-2"
// Octaves go from -2 to 8, C3 is middle C
// Will return nothing (nil) for an invalid note string
static int midi_noteNumber(lua_State *L)
{
    int args = lua_gettop(L);
    if (args != 1)  {
        return luaL_error(L, "Invalid number of arguments to MIDI.notenumber()");
    }
    
    size_t length = 0;
    const char *noteString = lua_tolstring(L, 1, &length);
    
    // no string or bad string
    if (noteString == NULL) {
        return 0;
    }
    // string is too long or short to be valid
    if ((length < 2) || (length > 4)) {
        return 0;
    }
    
    int note = 0;
    char letter = noteString[0];
    switch(letter) {
        case 'C':
        case 'c':
            note = 0;
            break;
        case 'D':
        case 'd':
            note = 2;
            break;
        case 'E':
        case 'e':
            note = 4;
            break;
        case 'F':
        case 'f':
            note = 5;
            break;
        case 'G':
        case 'g':
            note = 7;
            break;
        case 'A':
        case 'a':
            note = 9;
            break;
        case 'B':
        case 'b':
            note = 11;
            break;
        default:
            return 0; // invalid note letter
    }
    
    int strIndex = 1;
    if (noteString[strIndex] == '#') {
        note++;
        strIndex++;
    }
    if (noteString[strIndex] == 'b') {
        note--;
        strIndex++;
    }
    
    // string didn't have an octave number
    if (strIndex >= length) {
        return 0;
    }
    
    int octaveMultiplier = 1;
    if (noteString[strIndex] == '-') {
        octaveMultiplier = -1;
        strIndex++;
    }
    
    // string didn't have an octave number
    if (strIndex >= length) {
        return 0;
    }
    
    char octaveChar = noteString[strIndex];
    int octave = octaveMultiplier * (octaveChar - '0');
    
    int finalnote = 12 * (2 + octave) + note;
    if ((finalnote > 127) || (finalnote < 0)) {
        return 0; // note is too high or low
    }
    
    lua_pushinteger(L, finalnote);
    return 1;
}

// MIDI.noteon(notenumber, velocity, [channel = 1])
// notenumber: integer 0-127
// velocity: integer 1-127
// channel (optional): integer 1-16
static int midi_noteon(lua_State *L)
{
    int args = lua_gettop(L);
    if ((args < 2) || (args > 3)) {
        return luaL_error(L, "Invalid number of arguments to MIDI.noteon()");
    }
    
    if (!initcheck()) {
        return luaL_error(L, "Must call MIDI.init() before MIDI.noteon()");
    }
    
    int note = luaL_checkinteger(L, 1) & 0x7F; // keep note in 0-127 range
    int vel = luaL_checkinteger(L, 2) & 0x7F; // keep velocity in 0-127 range
    // 0 velocity = no-op (might otherwise act as a note off)
    if (vel == 0) {
        return 0;
    }
    
    int channel = 0;
    if (args == 3) {
        channel = luaL_checkinteger(L, 3);
        // Channel argument is in range 1-16, subtract 1 for zero-indexed channel.
        // Argument of '0' will still go to zero-indexed channel 0.
        channel--;
        if (channel < 0) channel = 0;
        if (channel > 15) channel = 15;
    }
    
    command noteOnCommand;
    noteOnCommand.type = kNoteOn;
    noteOnCommand.channel = channel;
    noteOnCommand.note = note;
    noteOnCommand.velocity = vel;
    queueCommand(noteOnCommand);
        
    return 0;
}

// MIDI.noteoff(notenumber, [channel = 1])
// notenumber: integer 0-127
// channel (optional): integer 1-16
static int midi_noteoff(lua_State *L)
{
    int args = lua_gettop(L);
    if ((args < 1) || (args > 2)) {
        return luaL_error(L, "Invalid number of arguments to MIDI.noteoff()");
    }
    
    if (!initcheck()) {
        return luaL_error(L, "Must call MIDI.init() before MIDI.noteoff()");
    }
    
    int note = luaL_checkinteger(L, 1) & 0x7F; // keeps note in 0-127 range
    
    int channel = 0;
    if (args == 2) {
        channel = luaL_checkinteger(L, 2);
        // Channel argument is in range 1-16, subtract 1 for zero-indexed channel.
        // Argument of '0' will still go to zero-indexed channel 0.
        channel--;
        if (channel < 0) channel = 0;
        if (channel > 15) channel = 15;
    }
    
    command noteOffCommand;
    noteOffCommand.type = kNoteOff;
    noteOffCommand.channel = channel;
    noteOffCommand.note = note;
    queueCommand(noteOffCommand);
    
    return 0;
}

// MIDI.noteonwithduration(notenumber, velocity, duration, [channel = 1])
// notenumber: integer 0-127
// velocity: integer 1-127
// duration: integer in 60ths of a second (or a user-set value)
// channel (optional): integer 1-16
static int midi_noteonwithduration(lua_State *L)
{
    int args = lua_gettop(L);
    if ((args < 3) || (args > 4)) {
        return luaL_error(L, "Invalid number of arguments to MIDI.noteonwithduration()");
    }
    
    if (!initcheck()) {
        return luaL_error(L, "Must call MIDI.init() before MIDI.noteonwithduration()");
    }
    
    int note = luaL_checkinteger(L, 1) & 0x7F; // keeps note in 0-127 range
    int vel = luaL_checkinteger(L, 2) & 0x7F; // keeps velocity in 0-127 range
    // do nothing for 0 velocity
        if (vel == 0) {
        return 0;
    }
    int duration = luaL_checkinteger(L, 3);
    // do nothing for 0 or negative duration
    if (!(duration > 0)) {
        return 0;
    }
    
    int channel = 0;
    if (args == 4) {
        channel = luaL_checkinteger(L, 4);
        // Channel argument is in range 1-16, subtract 1 for zero-indexed channel.
        // Argument of '0' will still go to zero-indexed channel 0.
        channel--;
        if (channel < 0) channel = 0;
        if (channel > 15) channel = 15;
    }
    
    command noteOnCommand;
    noteOnCommand.type = kNoteOnWithDuration;
    noteOnCommand.channel = channel;
    noteOnCommand.note = note;
    noteOnCommand.velocity = vel;
    noteOnCommand.duration = duration;
    queueCommand(noteOnCommand);
    
    return 0;
}

// MIDI.CC(CC, value, [channel = 1])
// CC: integer 0-120
// value: integer 0-127
// channel (optional): integer 1-16
static int midi_CC(lua_State *L)
{
    int args = lua_gettop(L);
    if ((args < 2) || (args > 3)) {
        return luaL_error(L, "Invalid number of arguments to MIDI.CC()");
    }
    
    if (!initcheck()) {
        return luaL_error(L, "Must call MIDI.init() before MIDI.CC()");
    }
    
    int CC = luaL_checkinteger(L, 1); 
    // keep CC in 0-119 range
    if (CC < 0) {
        CC = 0;
    }
    if (CC > 119) {
        CC = 119;
    }
    
    int value = luaL_checkinteger(L, 2) & 0x7F; // keeps value in 0-127 range
    int channel = 0;
    
    if (args == 3) {
        channel = luaL_checkinteger(L,3);
        // Channel argument is in range 1-16, subtract 1 for zero-indexed channel.
        // Argument of '0' will still go to zero-indexed channel 0.
        channel--;
        if (channel < 0) channel = 0;
        if (channel > 15) channel = 15;
    }
    
    command ccCommand;
    ccCommand.type = kCC;
    ccCommand.channel = channel;
    ccCommand.CC = CC;
    ccCommand.value = value;
    queueCommand(ccCommand);
    
    return 0;
}

// MIDI.pitchbend(bend, [channel = 1])
// bend: float, -1 to 1 (min and max pitch bend, respectively)
// channel (optional): integer 1-16
static int midi_pitchbend(lua_State *L)
{
    int args = lua_gettop(L);
    if ((args < 1) || (args > 2)) {
        return luaL_error(L, "Invalid number of arguments to MIDI.pitchbend()");
    }
    
    if (!initcheck()) {
        return luaL_error(L, "Must call MIDI.init() before MIDI.pitchbend()");
    }
    
    float value = luaL_checknumber(L, 1);
    if (value > 1.0) {
        value = 1.0;
    }
    if (value < -1.0) {
        value = -1.0;
    }
    
    int channel = 0;
    if (args == 2) {
        channel = luaL_checkinteger(L, 2);
        // Channel argument is in range 1-16, subtract 1 for zero-indexed channel.
        // Argument of '0' will still go to zero-indexed channel 0.
        channel--;
        if (channel < 0) channel = 0;
        if (channel > 15) channel = 15;
    }
    
    // pitch value is a 14 bit value, center is 0x2000 = 8192 = (1 << 13)
    int delta14b = roundf(8191.0 * value);
    int pbvalue14b = 8192 + delta14b;
    int pbvalueL7b = (pbvalue14b & 0x7F);
    int pbvalueM7b = ((pbvalue14b >> 7) & 0x7F);
    
    //printf("14 bits: %d\tLSB: %d\tMSB: %d\n", pbvalue14b, pbvalueL7b, pbvalueM7b);
        
    command pitchBendCommand;
    pitchBendCommand.type = kPitchBend;
    pitchBendCommand.channel = channel;
    pitchBendCommand.MS7b = pbvalueM7b;
    pitchBendCommand.LS7b = pbvalueL7b;
    queueCommand(pitchBendCommand);
    
    return 0;
}

// MIDI.allnotesoff([channel = 1])
// channel (optional): integer 1-16 
static int midi_allnotesoff(lua_State *L)
{
    int args = lua_gettop(L);
    if (args > 1) {
        return luaL_error(L, "Invalid number of arguments to MIDI.allnotesoff()");
    }
    
    if (!initcheck()) {
        return luaL_error(L, "Must call MIDI.init() before MIDI.allnotesoff()");
    }
    
    int channel = 0;
    if (args == 1) {
        channel = luaL_checkinteger(L, 1);
        // Channel argument is in range 1-16, subtract 1 for zero-indexed channel.
        // Argument of '0' will still go to zero-indexed channel 0.
        channel--;
        if (channel < 0) channel = 0;
        if (channel > 15) channel = 15;
    }
    
    command resetNotesCommand;
    resetNotesCommand.type = kResetNotes;
    resetNotesCommand.channel = channel;
    queueCommand(resetNotesCommand);
        
    return 0;
}

// MIDI.sendmessages()
// No arguments
static int midi_sendMessages(lua_State *L)
{
    if (!initcheck()) {
        return luaL_error(L, "Must call MIDI.init() before MIDI.sendmessages()");
    }
    
    int messagesSent = commandQueueIndex; // for debugging    
    
    // Used to remove redundant (possibly contradictory) events
    uint16_t noteOns[128];
    uint16_t noteOffs[128];
    uint16_t CCs[128];
    
    memset(noteOns, 0, 128 * sizeof(uint16_t));
    memset(noteOffs, 0, 128 * sizeof(uint16_t));
    memset(CCs, 0, 128 * sizeof(uint16_t));
    uint16_t notesReset = 0; // remove all note on commands before reset notes command
    uint16_t pitchBends = 0; // remove all but the last pitch bend command for each channel
    
    // how many notes need to be sent slightly later due to concurrent note off commands?
    int laterNotes = 0;
    
    // 1: Run through backwards, remove superfluous commands
    for (int i = commandQueueIndex - 1; i >= 0; i--) {
        int ch = commandQueue[i].channel;
        switch(commandQueue[i].type) {
            case kNoteOn:
            case kNoteOnWithDuration:
            {
                int note = commandQueue[i].note;
                if (((noteOffs[note] >> ch) & 1) == 1) {
                    // note off exists later in queue, remove me
                    commandQueue[i].type = kInvalid;
                    messagesSent--;
                    break;
                }
                if (((noteOns[note] >> ch) & 1) == 1) {
                    // note on already exists later in the queue, remove me
                    commandQueue[i].type = kInvalid;
                    messagesSent--;
                    break;
                }
                if (((notesReset >> ch) & 1) == 1) {
                    // reset notes command exists later in the queue, remove me
                    commandQueue[i].type = kInvalid;
                    messagesSent--;
                    break;
                }
                noteOns[note] |= (1 << ch);
                if (notePlaying[ch][note]) {
                    laterNotes++;
                }
                break;
            }
            case kNoteOff:
            {
                int note = commandQueue[i].note;
                noteOffs[note] |= (1 << ch);
                break;
            }
            case kCC:
            {
                int cc = commandQueue[i].CC;
                if (((CCs[cc] >> ch) & 1) == 1) {
                    commandQueue[i].type = kInvalid;
                    messagesSent--;
                    break;
                }
                CCs[cc] |= (1 << ch);
                break;
            }
            case kPitchBend:
                if (((pitchBends >> ch) & 1) == 1) {
                    commandQueue[i].type = kInvalid;
                    messagesSent--;
                    break;
                }
                pitchBends |= (1 << ch);
                break;
            case kResetNotes:
                notesReset |= (1 << ch);
                break;
            default:
                break;
        }
    }
    
    // 2: Run through commands, move note on commands for already-playing notes to a delayed list.
    // This may be necessary because if a note off is sent at the same time as a note on, it ends 
    // up having the same timestamp as the note on event, and they might cancel each other out, as the
    // order of events with the same timestamp apparently can vary.
    command *delayedCommands = malloc(laterNotes * sizeof(command));
    int delayedCommandsIndex = 0;
    for (int i = 0; i < commandQueueIndex; i++) {
        if ((commandQueue[i].type == kNoteOn) || (commandQueue[i].type == kNoteOnWithDuration)) {
            int ch = commandQueue[i].channel;
            int note = commandQueue[i].note;
            if (notePlaying[ch][note]) {
                delayedCommands[delayedCommandsIndex] = commandQueue[i];
                delayedCommandsIndex++;
                // We need to turn off the note since it's already playing
                commandQueue[i].type = kNoteOff;
            }
        }
    }
    
    // 3. Send messages for events remaining in commandQueue
    for (int i = 0; i < commandQueueIndex; i++) {
        switch (commandQueue[i].type) {
            case kNoteOn:
                sendNoteOn(commandQueue[i].channel, commandQueue[i].note, commandQueue[i].velocity);
                break;
            case kNoteOnWithDuration:
                sendNoteOnWithDuration(commandQueue[i].channel, commandQueue[i].note, 
                            commandQueue[i].velocity, commandQueue[i].duration, 0);
                break;
            case kNoteOff:
                sendNoteOff(commandQueue[i].channel, commandQueue[i].note);
                break;
            case kCC:
                sendCC(commandQueue[i].channel, commandQueue[i].CC, commandQueue[i].value);
                break;
            case kPitchBend:
                sendPitchBend(commandQueue[i].channel, commandQueue[i].MS7b, commandQueue[i].LS7b);
                break;
            case kResetNotes:
                sendResetNotes(commandQueue[i].channel);
                break;
            default: // covers -1/invalid
                break;
        }
    }
    
    // 4. Send messages for note on commands in delatedCommands in a deferred block, release list.
    // For anyone interested in porting Emstrument, this need to be modified to use something else equivalent to GCD.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1000000 * late_note_offset), luaMIDIQueue, ^{
        // send commands
        for (int i = 0; i < delayedCommandsIndex; i++) {
            switch (delayedCommands[i].type) {
                case kNoteOn:
                    //printf("sending delated note on\n");
                    sendNoteOn(delayedCommands[i].channel, delayedCommands[i].note, 
                                delayedCommands[i].velocity);
                    break;
                case kNoteOnWithDuration:
                    //printf("sending delated note on w/ duration\n");
                    sendNoteOnWithDuration(delayedCommands[i].channel, delayedCommands[i].note, 
                                delayedCommands[i].velocity, delayedCommands[i].duration, late_note_offset);
                    break;
                default: // shouldn't be any other commands, but just in case
                    break;
            }
        }    
        free(delayedCommands);
    });
    
    commandQueueIndex = 0;

    return 0;
}

static const struct luaL_reg kMidilib[] = {
    {"init", midi_init},
    {"configuretiming", midi_configuretiming},
    {"notenumber", midi_noteNumber},
    {"noteon", midi_noteon},
    {"noteoff", midi_noteoff},
    {"noteonwithduration", midi_noteonwithduration},
    {"CC", midi_CC},
    {"pitchbend", midi_pitchbend},
    {"allnotesoff", midi_allnotesoff},
    {"sendmessages", midi_sendMessages},
    {NULL,NULL}
};

LUALIB_API int luaopen_emstrument (lua_State *L) {
  luaL_register(L, "MIDI", kMidilib);
  return 0;
}


/* -- MIDI sending functions (only to be called from midi_sendMessages()) -- */
// For anyone interested in porting Emstrument, these are the core functions that need to be modified.

static void sendNoteOn(int ch, int note, int vel)
{
    Byte buffer[32];
    MIDIPacketList *packetlist = (MIDIPacketList *)buffer;
    MIDIPacket *currentpacket = MIDIPacketListInit(packetlist);
    
    // Update lastNoteIDs before sending out the MIDI message
    lastNoteIDs[ch][note]++;
        
    Byte onbytes[3] = {0x90 + ch, note, vel};
    currentpacket = MIDIPacketListAdd(packetlist, sizeof(buffer), currentpacket, 0, 3, onbytes);
    MIDIReceived(luaMIDIEndpoint, packetlist);
    
    notePlaying[ch][note] = true;
}

// offset reduces the duration to account for if this message is part of the delayed command list
// and note-on delay is set above 0
static void sendNoteOnWithDuration(int ch, int note, int vel, int duration, float offset)
{
    Byte buffer[32];
    MIDIPacketList *packetlist = (MIDIPacketList *)buffer;
    MIDIPacket *currentpacket = MIDIPacketListInit(packetlist);

    // Update lastNoteIDs before sending out the MIDI message
    lastNoteIDs[ch][note]++;
    int currentNoteID = lastNoteIDs[ch][note];
        
    Byte onbytes[3] = {0x90 + ch, note, vel};
    currentpacket = MIDIPacketListAdd(packetlist, sizeof(buffer), currentpacket, 0, 3, onbytes);
    MIDIReceived(luaMIDIEndpoint, packetlist); 

    notePlaying[ch][note] = true;
    
    // note off scheduling, the using a timestamp with MIDIReceived() doesn't seem to work all the time
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1000000 * duration_unit * (duration - offset)), 
        luaMIDIQueue, ^{
        // If the same note has been played since this one, don't send
        // note off message (it's already been turned off)
        if (lastNoteIDs[ch][note] == currentNoteID) {
            Byte buffer_d[32];
            MIDIPacketList *packetlist_d = (MIDIPacketList *)buffer_d;
            MIDIPacket *currentpacket_d = MIDIPacketListInit(packetlist_d);
            
            Byte offbytes[3] = {0x80 + ch, note, 0};
            MIDIPacketListAdd(packetlist_d, sizeof(buffer_d), currentpacket_d, 0, 3, offbytes);
            MIDIReceived(luaMIDIEndpoint, packetlist_d);
            
            notePlaying[ch][note] = false;
        }
    });
}

static void sendNoteOff(int ch, int note)
{
    Byte buffer[32];
    MIDIPacketList *packetlist = (MIDIPacketList *)buffer;
    MIDIPacket *currentpacket = MIDIPacketListInit(packetlist);
    
    Byte offbytes[3] = {0x80 + ch, note, 100};
    currentpacket = MIDIPacketListAdd(packetlist, sizeof(buffer), currentpacket, 0, 3, offbytes);
    MIDIReceived(luaMIDIEndpoint, packetlist);
    
    notePlaying[ch][note] = false;
}

static void sendCC(int ch, int CC, int value)
{
    Byte buffer[32];
    MIDIPacketList *packetlist = (MIDIPacketList *)buffer;
    MIDIPacket *currentpacket = MIDIPacketListInit(packetlist);
    
    Byte msg[3] = {0xB0 + ch, CC, value};
    currentpacket = MIDIPacketListAdd(packetlist, sizeof(buffer), currentpacket, 0, 3, msg);
    MIDIReceived(luaMIDIEndpoint, packetlist);
}

static void sendPitchBend(int ch, int msb, int lsb)
{
    Byte buffer[32];
    MIDIPacketList *packetlist = (MIDIPacketList *)buffer;
    MIDIPacket *currentpacket = MIDIPacketListInit(packetlist);
    
    Byte offbytes[3] = {0xE0 + ch, lsb, msb};
    currentpacket = MIDIPacketListAdd(packetlist, sizeof(buffer), currentpacket, 0, 3, offbytes);
    MIDIReceived(luaMIDIEndpoint, packetlist);
}

static void sendResetNotes(int ch)
{
    Byte buffer[1024];
    MIDIPacketList *packetlist = (MIDIPacketList *)buffer;
    MIDIPacket *currentpacket = MIDIPacketListInit(packetlist);
    for (int i = 0; i < 128; i++) {
        // only turn off notes currently playing, to avoid message congestion
        if (notePlaying[ch][i]) {
            Byte msg[3] = {0x80 + ch, i, 0};
            currentpacket = MIDIPacketListAdd(packetlist, sizeof(buffer), currentpacket, 0, 3, msg);
        }
    }
    MIDIReceived(luaMIDIEndpoint, packetlist);
    memset(&notePlaying[ch][0], 0, sizeof(bool) * 128);
}




