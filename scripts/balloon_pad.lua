--[[
    Balloon Fight: pad + sfx trigger
    Script for FCEUX + Emstrument
    
    This script turns the game into an instrument that modulates notes based on game character
    positions and plays sound effects in response to in-game events.
    Each enemy has an assigned note, which is drawn on it. The distance between the player
    and the enemy changes the loudness of the sound. The musical result is a tug of war between
    the player and the enemy AI.
    Sound effects are played in response to balloons or bubbles popping, characters landing
    in the water, and enemies being pushed while on the ground.
    
    This script works with the Logic Pro X project "balloon_pad.logicx"
    
    Tested with Balloon Fight (USA).nes
    First published 12/2015 by Ben/Signal Narrative
    
    Special thanks to Quick Curly's guide to Balloon Fight: http://www.romhacking.net/documents/698/
]]

-- MIDI channels used in this script:
    -- 1: SFX
    -- 2-7: sound corresponding to each enemy

require('emstrument');
MIDI.init();

-- The x,y position of each enemy (there are a maximum of 6)
enemyx = {0, 0, 0, 0, 0, 0};
enemyy = {0, 0, 0, 0, 0, 0};
-- The status of each enemy: 0xFF=no enemy, 0x80=enemy gone, 0=falling, 1=ground/slow fall, 2=floating
enemystatus = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

-- used to draw an overlay over the enemies showing which note they represent
enemynotelabels = {"C", "G", "D", "E", "A", "B"};
-- the notes for each enemy
enemynotes = {MIDI.notenumber("C3"), MIDI.notenumber("G3"), MIDI.notenumber("D4"),
            MIDI.notenumber("E4"), MIDI.notenumber("A4"), MIDI.notenumber("B4")};

lastb = 0; -- the number of balloons the player had in the last frame
lastscore = 0; -- the score in the last frame

-- We control the loudness of the 6 enemy voices using CC number 1, modulation/mod wheel
-- Silence all voices before starting
MIDI.CC(1,0,2); 
MIDI.CC(1,0,3);
MIDI.CC(1,0,4);
MIDI.CC(1,0,5);
MIDI.CC(1,0,6);
MIDI.CC(1,0,7);

while (true) do
    -- The score is store as one digit per byte, as is typical of these games
    score10_0 = memory.readbyte(0x0002);
    score10_1 = memory.readbyte(0x0003);
    score10_2 = memory.readbyte(0x0004);
    score10_3 = memory.readbyte(0x0005);
    score10_4 = memory.readbyte(0x0006);
    score = score10_0 + 10*score10_1 + 100*score10_2 + 1000*score10_3 + 10000*score10_4;
    
    -- $0088 - player's balloons - either 0,1,2 or 255 (when the game is between levels or in a menu)
    b = memory.readbyte(0x0088);
    -- $0091 - player's x position
    x = memory.readbyte(0x0091);
    -- $009A - player's y position
    y = memory.readbyte(0x009A);
    
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
        
        -- Since the playfield wraps around horizontally, we can't just use the normal
        -- distance formula, we need to consider the cases where the distance is shorter
        -- because the 2 points are near the left or right edge
        dist1 = math.pow(math.pow(enemyx[i] - x, 2)+math.pow(enemyy[i] - y, 2), 0.5);
        dist2 = math.pow(math.pow(x + (255 - enemyx[i]), 2)+math.pow(enemyy[i] - y, 2), 0.5);
        dist3 = math.pow(math.pow(enemyx[i] + (255 - x), 2)+math.pow(enemyy[i] - y, 2), 0.5);
        dist =  math.min(dist1,dist2,dist3);
        
        laststatus = enemystatus[i];
        enemystatus[i] = memory.readbyte(0x008A + i - 1);
        
        -- If the level just started, enemy status will go from 0xFF or 0x80 to something else
        if (((enemystatus[i] ~= 0xFF) and (enemystatus[i] ~= 0x80)) and 
            ((laststatus == 0x80) or (laststatus == 0xFF))) then
            -- start playing note, enemy just spawned
            MIDI.noteon(enemynotes[i], 90, i + 1);
        end;
        -- If the enemy fell into water, enemy status goes from 0x00 (falling) to 0x80 (gone)
        if ((enemystatus[i] == 0x80) and (laststatus == 0x00)) then
            -- play splash sfx
            MIDI.noteonwithduration(36, 100, 15, 1);
            -- stop playing enemy's note
            MIDI.noteoff(enemynotes[i], i + 1);
            MIDI.CC(1, 0, i + 1);
        end;
        -- If the enemy's balloons popped, status goes from 0x02 (floating) to 0x01 (slow fall)
        if ((enemystatus[i] == 0x01) and (laststatus == 0x02)) then
            -- play pop sfx
            MIDI.noteonwithduration(37, 100, 15, 1);
        end;
        -- If the enemy was pushed while on the ground, status goes from 0x01 (ground) to 0x00 (fall)
        if ((enemystatus[i] == 0x00) and (laststatus == 0x01)) then
            -- enemy hit while on ground
            MIDI.noteonwithduration(38, 100, 15, 1);
        end;
        -- If the enemy somehow stopped existing, stop playing its note
        if ((enemystatus[i] == 0xFF) and (laststatus ~= 0xFF)) then
            MIDI.noteoff(enemynotes[i], i + 1);
            MIDI.CC(1, 0, i + 1);
        end;
        -- If the enemy is still active, draw a line to it with a color corresponding to distance
        -- and draw the name of the note on top of the enemy
        if ((enemystatus[i] ~= 0x80) and (enemystatus[i] ~= 0xFF)) then
            gui.drawline(x + 10, y + 20, enemyx[i] + 10, enemyy[i] + 20,
                                {2*(96 - dist/2), (96 - dist/2), 200 - (96 - dist/2)});            
            gui.text(enemyx[i] + 6, enemyy[i] + 16, enemynotelabels[i]);
            MIDI.CC(1, math.max(0, math.floor(96 - dist/2)), i + 1);
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


-- Addendum: I had to find out where the score was stored, so I used the following method:
-- I got a score of something like 25900, paused the game, and searched the RAM for values of 2, 5 and 9
-- The RAM addresses that were consecutive were where the score is stored.
--[[
-- be sure to only run this loop once per digit
for i=1,2048 do
    if (memory.readbyte(i) == 2) then
        print("possible digit byte: "..i);
    end;
end;
break;]]

