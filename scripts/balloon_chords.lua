--[[
    Balloon Fight: chord + sfx trigger
    Script for FCEUX + Emstrument
    
    This script turns the game into an instrument that plays a chord assigned to each
    enemy when they are hit. The highest note of the last chord played is played on 
    another channel and modulated by the player's y-position.
    In addition, sound effects are played in response to balloons or bubbles popping, 
    characters landing in the water, and enemies being pushed while on the ground.
    
    This script works with the Logic Pro X project "balloon_chord.logicx"

    Tested with Balloon Fight (USA).nes
    First published 12/2015 by Ben/Signal Narrative
    
    Special thanks to Quick Curly's guide to Balloon Fight: http://www.romhacking.net/documents/698/
]]

-- MIDI channels used in this script:
    -- 1: SFX
    -- 2: chords corresponding to each enemy
    -- 3: high note

require('emstrument');
MIDI.init();

-- The same note can be triggered while it's playing, sometimes causing a note-on note-off
-- reversal, so set note-on delay to 5ms.
MIDI.configuretiming(16, 5); 

-- The x,y position of each enemy (there are a maximum of 6)
enemyx = {0, 0, 0, 0, 0, 0};
enemyy = {0, 0, 0, 0, 0, 0};
-- The status of each enemy: 0xFF=no enemy, 0x80=enemy gone, 0=falling, 1=ground/slow fall, 2=floating
enemystatus = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

-- used to draw an overlay over the enemies showing which chord they represent
enemychordlabels = {"e7", "g4", "F7", "e4", "E4", "C7"};
-- the chords for each enemy (there are 6 at most in any level)
enemychords = {
            {"E2", "E3", "G3", "B3", "D4"},
            {"G2", "G3", "A3", "C4", "D4"},
            {"F2", "F3", "A3", "C4", "E4"},
            {"E2", "E3", "G3", "A3", "D4"},
            {"E2", "E3", "A3", "B3", "D4"},
            {"C2", "C3", "B3", "E4", "G4"},
};
chordlength = 5;

lastb = 0; -- the number of balloons the player had in the last frame
lastscore = 0; -- the score in the last frame

while (true) do
    -- The score is store as one digit per byte, as is typical of these games
    score10_0 = memory.readbyte(0x0002);
    score10_1 = memory.readbyte(0x0003);
    score10_2 = memory.readbyte(0x0004);
    score10_3 = memory.readbyte(0x0005);
    score10_4 = memory.readbyte(0x0006);
    score = score10_0 + 10*score10_1 + 100*score10_2 + 1000*score10_3 + 10000*score10_4;
    
    -- $0088 - player's balloons - either 0, 1, 2 or 255 (when the game is between levels or in a menu)
    b = memory.readbyte(0x0088);
    -- $0091 - player's x position
    x = memory.readbyte(0x0091);
    -- $009A - player's y position
    y = memory.readbyte(0x009A);
    
    MIDI.CC(1, math.max(0, math.floor((255 - y*2)/2)), 3);
    
    -- 500 points means something popped, possibly a bubble
    if (score - lastscore == 500) then
        -- if it was actually an enemy balloon and we want a louder pop, the call to noteonwithduration
        -- in the next block of code will overwrite this one when we call MIDI.sendmessages()
        MIDI.noteonwithduration(37, 60, 15, 1); -- popping sound
    end;
    
    -- There are at most 6 enemies in a level, and their info is always stored in the same
    -- 6 sets of addresses
    for i=1,6 do
        enemyx[i] = memory.readbyte(0x0093 + i - 1);
        enemyy[i] = memory.readbyte(0x009C + i - 1);
        
        laststatus = enemystatus[i];
        enemystatus[i] = memory.readbyte(0x008A + i - 1);
        
        -- If the level just started, enemy status will go from 0xFF or 0x80 to something else
        if (((enemystatus[i] ~= 0xFF) and (enemystatus[i] ~= 0x80)) and 
            ((laststatus == 0x80) or (laststatus == 0xFF))) then
            -- enemy just spawned
        end;
        -- If the enemy fell into water, enemy status goes from 0x00 (falling) to 0x80 (gone)
        if ((enemystatus[i] == 0x80) and (laststatus == 0x00)) then
            -- play splash sfx
            MIDI.noteonwithduration(36, 100, 15, 1);
        end;
        -- If the enemy's balloons popped, status goes from 0x02 (floating) to 0x01 (slow fall)
        if ((enemystatus[i] == 0x01) and (laststatus == 0x02)) then
            -- play pop sfx
            MIDI.noteonwithduration(37, 100, 15, 1);
            -- play chord
            for n=1,chordlength do
                MIDI.noteonwithduration(MIDI.notenumber(enemychords[i][n]), 127, 20, 2);
            end;
            MIDI.allnotesoff(3);
            MIDI.noteon(MIDI.notenumber(enemychords[i][chordlength])+12, 127, 3);
        end;
        -- If the enemy was pushed while on the ground, status goes from 0x01 (ground) to 0x00 (fall)
        if ((enemystatus[i] == 0x00) and (laststatus == 0x01)) then
            -- enemy hit while on ground
            MIDI.noteonwithduration(38, 100, 15, 1);
            for n=1,chordlength do
                MIDI.noteonwithduration(MIDI.notenumber(enemychords[i][n]), 127, 20, 2);
            end;
            MIDI.allnotesoff(3);
            MIDI.noteon(MIDI.notenumber(enemychords[i][chordlength])+12, 127, 3);
        end;
        if ((enemystatus[i] == 0xFF) and (laststatus ~= 0xFF)) then
            -- The enemy somehow stopped existing
        end;
        -- If the enemy is still active, draw a line to it with a color corresponding to distance
        -- and draw the name of the note on top of the enemy
        if ((enemystatus[i] ~= 0x80) and (enemystatus[i] ~= 0xFF)) then
            gui.text(enemyx[i]+6, enemyy[i]+16, enemychordlabels[i]);
        end;
    end;
    
    -- Monitor player status by the number of balloons they have
    if ((b == lastb - 1) or (b == lastb - 2)) then
        -- one of the player's balloons was popped (or both, by a spark)
        MIDI.noteonwithduration(37, 100, 15, 1);
    end;
    if ((b == 255) and (lastb ~= 255)) then
        -- player fell into the water
        MIDI.noteonwithduration(36, 100, 15, 1); 
    end;
    
    -- store values for comparison later
    lastb = b;
    lastscore = score;
    
    -- send midi messages
    MIDI.sendmessages();
    FCEU.frameadvance();    
end;

