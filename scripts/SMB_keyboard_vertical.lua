--[[
    Super Mario Brothers: vertical keyboard
    Script for FCEUX + Emstrument
    
    This script turns the game world into a keyboard that is activated when Mario lands
    after jumping or falling.
    The key that is played depends on the height of the platform Mario is on. The key 
    is lifted when Mario jumps or falls off of that platform. A keyboard is drawn on 
    the left of the screen for reference.
    
    Tested with Super Mario Bros. (Japan, USA).nes
    First published 12/2015 by Ben/Signal Narrative
    
    Special thanks to http://datacrystal.romhacking.net/wiki/Super_Mario_Bros.:RAM_map
]]

require('emstrument');
MIDI.init();

-- The notes of a major scale. Modify next 2 values to change to a different scale
notes = {0, 2, 4, 5, 7, 9, 11};
notesinscale = 7;

lastfloating = 0;
drawnote = 0;
drawnotex = 0;
drawnoteon = 20;

while (true) do
    -- The Y position of Mario, used to determine which note to play
    y = memory.readbyte(0x00CE); 
    -- Mario's 'float' status. 0 if standing on ground, above 0 if in the air (for the most part)
    floating = memory.readbyte(0x001D);
    
    if (floating ~= 0) then
        MIDI.allnotesoff();
        drawnoteon = 0;
    end;
    
    -- Trigger a note if Mario was in the air last frame, but now he's on the ground
    if ((floating ~= lastfloating) and (floating == 0)) then
        -- Use math.floor to make sure all values are integers
        note = math.floor((176 - y)/16);
        octave = math.floor(note / notesinscale);
        MIDI.noteon(MIDI.notenumber("C3") + 12*octave + notes[(note%7) + 1], 100);
        
        -- Store which note we just played so we can draw it on the keyboard on the left side of the screen
        drawnote = math.floor(y/16) + 1;
        drawnoteon = 1;
    end;
    
    -- Draw the keyboard on the left
    gui.drawbox(0, 8, 12, 256, "white"); -- White background
    for i=1,16 do
        -- For each boundary between keys, draw a thin line.
        gui.drawline(0, 16*i + 8, 12, 16*i + 8, "black");
        -- For every boundary with a black key between 2 white keys, draw a small (nonfunctional) black key
        if ((i%7 == 4) or (i%7 == 5) or (i%7 == 0) or (i%7 == 1) or (i%7 == 2)) then
            gui.drawrect(0, 16*i + 6, 8, 16*i + 10, "black");
        end;
    end;
    
    -- Draw the note if it's still playing
    if (drawnoteon > 0) then
        gui.drawbox(0, 16*drawnote + 12, 12, 16*drawnote + 20, "black");
        -- Draw a line from the note to Mario
        drawnotex = memory.readbyte(0x03AD); -- Mario's x position within current screen offset
        gui.drawbox(12, 16*drawnote + 16, drawnotex + 8, 16*drawnote + 17, "red");
    end;
    
    -- Store the last value of 'floating' for comparison later on, send midi messages
    lastfloating = floating;
    MIDI.sendmessages();
    FCEU.frameadvance();
end;

