--[[
    Super Mario Brothers: horizontal keyboard
    Script for FCEUX + Emstrument
    
    This script turns the game world into a keyboard that is activated when Mario lands on
    a key. The key is held until Mario walks off of it or jumps off of it. Kind of like
    the giant piano from 'Big', except it only plays notes when jumped on.
    The key that is played depends on Mario's horizontal position. A keyboard is drawn on 
    the bottom of the screen for reference.
    This script is longer than SMB_keyboard_vertical.lua because it has to keep track of 
    the horizontal screen scrolling.
    
    Tested with Super Mario Bros. (Japan, USA).nes
    First published 12/2015 by Ben/Signal Narrative
    
    Special thanks to http://datacrystal.romhacking.net/wiki/Super_Mario_Bros.:RAM_map
]]

require('emstrument');
MIDI.init();

-- The notes of a major scale, over 2 octaves. These can be modified to play a different scale,
-- but changing the number of notes (14) will require additional code changes.
notes = {0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23};

-- variables relating to drawing the keyboard on the bottom of the screen
drawnote = 0;
drawnotey = 0;
drawnoteon = 0;
-- variables used to keep track of changes from frame to frame
lastfloating = 0;
lastoffset = 0;
translation = 0;
lastlevel = -1;
lastx = 0;
lastnote = 0;

while (true) do
    -- If the level changed, scroll the keyboard back to its initial position
    level = memory.readbyte(0x0960);
    if (level ~= lastlevel) then
        translation = 0; -- reset the scrolling x-translation, it's a new level
    end;
    
    -- Mario's overall x position in the level or pipe area
    x = memory.readbyte(0x0086) + (255 * memory.readbyte(0x006D));
    if ((lastx > x + 16) or (lastx < x - 16)) then
        translation = 0; -- reset the scrolling x-translation, we went in a pipe or something
    end;
    
    -- Mario's Y position
    y = memory.readbyte(0x00CE);
    -- Mario's 'float' status. 0 if standing on ground, above 0 if in the air (for the most part)
    floating = memory.readbyte(0x001D);
    -- Mario's x position within current screen offset. Used to determine which key on the virtual keyboard is played
    x_screen = memory.readbyte(0x03AD);
    -- The amount of horizontal scrolling modulo 255. Used to scroll the virtual keyboard the same amount
    offset = memory.readbyte(0x071D);
    scroll = (offset - lastoffset) % 255;
    translation = translation + scroll;
    
    -- To figure out which note Mario is on, take the x position on the screen and 
    -- add translation%224 (the length of the 2 octaves) and divide by the 2-octave length.
    -- Use math.floor to make sure the note value is an integer, since it's an array index.
    note = math.floor((x_screen + 8 + translation%224)/16);
    
    -- If we walk off the note stop playing it
    if ((note ~= lastnote) or (floating ~= 0)) then
        MIDI.allnotesoff();
        drawnoteon = 0;
    end;
    
    -- Play a note when we land somewhere after jumping/fallling
    if ((floating ~= lastfloating) and (floating == 0)) then
        MIDI.noteon(MIDI.notenumber("C3") + notes[(note%14) + 1], 100, 1);
        -- Store which note we just played so we can draw it on the keyboard
        drawnote = math.floor((x_screen + 8 + translation%224)/16);
        drawnotey = y + 32;
        drawnoteon = 1;
    end;
    
    -- Draw the keyboard on the bottom
    gui.drawbox(0, 216, 256, 232, "white"); -- White background
    for i=0,28 do -- draw 4 octaves
        -- For each boundary between keys, draw a thin line.
        gui.drawline(16*i - translation%224, 216, 16*i - translation%224, 232, "black");
        -- For every boundary with a black key between 2 white keys, draw a small (nonfunctional) black key
        if ((i%7 == 1) or (i%7 == 2) or (i%7 == 4) or (i%7 == 5) or (i%7 == 6)) then
            gui.drawrect(16*i - 1 - translation%224 , 216, 16*i + 1 - translation%224, 228, "black");
        end;
        -- When the keys cycle back after 2 octaves, draw a small gray line between keys to indicate that.
        if (i%14 == 0) then
            gui.drawline(16*i - translation%224, 228, 16*i - translation%224, 232, "gray");
        end;
    end;
    
    -- Draw the last note played, if it wasn't too long ago and it's still playing
    if (drawnoteon ~= 0) then
        gui.drawrect(16*drawnote + 4 - translation%224, 216, 16*drawnote + 12 - translation%224, 228, "black");
        -- Draw lines from the note to Mario
        gui.drawline(16*drawnote + 3 - translation%224, drawnotey, 16*drawnote + 3 - translation%224, 216, "gray");
        gui.drawline(16*drawnote + 13 - translation%224, drawnotey, 16*drawnote + 13 - translation%224, 216, "gray");
        gui.drawline(16*drawnote + 3 - translation%224, drawnotey, 16*drawnote + 13 - translation%224, drawnotey, "gray");
    end;
    
    -- Store values for comparison later on
    lastfloating = floating;
    lastoffset = offset;
    lastlevel = level;
    lastx = x;
    lastnote = note;
    
    -- Send midi messages
    MIDI.sendmessages();
    FCEU.frameadvance();
end;

