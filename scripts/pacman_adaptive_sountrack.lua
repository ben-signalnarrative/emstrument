--[[
    Pac-man: adaptive ambient soundtrack
    Script for FCEUX + Emstrument
    
    This script creates an alternate adaptive soundtrack for Pac-man. Sounds are generated
    in response to game events and the player's and ghosts' positions.
    
    This script works with the Logic Pro X project "pacman.logicx"
    
    Tested with Pac-Man (USA) (Namco).nes
    First published 12/2015 by Ben/Signal Narrative
    
    Special thanks to http://datacrystal.romhacking.net/wiki/Pac-Man:RAM_map
]]

-- This script sends MIDI over 6 channels:
-- 1: FX 1 (pellets, etc).
-- 2-5: 4 synths corresponding to each ghost
-- 6: FX 2 (ghost eaten, etc)

require('emstrument');
MIDI.init();

lastscore = 0;
powerup = 0; -- Tracks whether or not any ghosts are still blue
pellets = 0;

-- The direction of each ghost determines which note it plays (g1___ = ghost 1's ____, etc)
g1lastdir = 0; -- ghost directions: 0 = stationary (beginning level or paused)
g2lastdir = 0; -- 1 = right, 2 = up, 3 = left, 4 = down
g3lastdir = 0; 
g4lastdir = 0;

function getdirection(dx,dy)
    if ((dx>0) and (dy==0)) then
        return 1;
    end;
    if ((dx<0) and (dy==0)) then
        return 3;
    end;
    if ((dx==0) and (dy>0)) then
        return 4;
    end;
    if ((dx==0) and (dy<0)) then
        return 2;
    end;
    -- object is either stationary or did something unexpected
    return 0;
end;

g1lastx = 0;
g1lasty = 0;
g2lastx = 0;
g2lasty = 0;
g3lastx = 0;
g3lasty = 0;
g4lastx = 0;
g4lasty = 0;
lastlives = 0;
ghostnoteson = 0; -- only play the ghosts' notes during gameplay (obviously)
g1lastnote = 0;
g2lastnote = 0;
g3lastnote = 0;
g4lastnote = 0;

-- the basic notes for the ghosts (one per direction), which are gradually transposed.
ghostnotes1 = {55, 67, 59, 70};
ghostnotes2 = {52, 64, 56, 67};
ghostnotes = ghostnotes1; -- changes to ghostnotes1 or ghostnotes2 based on player x position

-- the notes played when eating pellets, chosen at random
pacnotes1 = {71, 72, 76, 78, 80, 82, 85, 86};
pacnotes2 = {69, 70, 73, 75, 79, 81, 82, 85};
pacnotes = pacnotes1; -- changes to pacnotes1 or pacnotes2 based on player y position
pacnotecount = 8; -- number of notes in each array
lastpacnote = 1; -- the last note played from the array. Used to avoid playing the same note twice


while (true) do
    level = memory.readbyte(0x0068);
    
    -- Score is used to determine when events occur
    -- Each digit is stored in a byte:
    score10s = memory.readbyte(0x0070);
    score10_2s = memory.readbyte(0x0071);
    score10_3s = memory.readbyte(0x0072);
    score10_4s = memory.readbyte(0x0073);
    score10_5s = memory.readbyte(0x0074);
    score10_6s = memory.readbyte(0x0075);
    score = 10*score10s + 100*score10_2s + 1000*score10_3s + 
            10000*score10_4s + 100000*score10_5s + 1000000*score10_6s;
    
    pacx = memory.readbyte(0x001A);
    pacy = memory.readbyte(0x001C);
    
    lives = memory.readbyte(0x0067);
    
    -- Read the memory indicating which graphic each ghost has:
    -- 10 or 11 if heading up, 16 or 17 if heading right
    -- 14 or 15 if heading down, 12 or 13 if heading left
    -- 30 or 31 if ghost is blue
    -- Can't use this for determing ghost direction because blue ghosts don't tell direction
    g1graphic = memory.readbyte(0x0033);
    g2graphic = memory.readbyte(0x0034); 
    g3graphic = memory.readbyte(0x0035); 
    g4graphic = memory.readbyte(0x0036);
    -- Figure out where the ghosts are
    g1x = memory.readbyte(0x001E);
    g1y = memory.readbyte(0x0020);
    g2x = memory.readbyte(0x0022);
    g2y = memory.readbyte(0x0024);
    g3x = memory.readbyte(0x0026);
    g3y = memory.readbyte(0x0028);
    g4x = memory.readbyte(0x002A);
    g4y = memory.readbyte(0x002C);
    
    -- If any ghosts are blue (graphic is 30 or 31), powerup is still active
    if ((g1graphic-(g1graphic%2)==30) or (g2graphic-(g2graphic%2)==30) or 
        (g3graphic-(g3graphic%2)==30) or (g4graphic-(g4graphic%2)==30)) then
        powerup = 1;
    else
        powerup = 0;
    end;
    
    
    -- Update CCs based on player's location
    -- Channel 1 modulation/mod wheel = pacman's distance from center (96,112)
        -- ll corner: (24,208)
        -- lr corner: (168,208)
        -- tl corner: (24,16)
        -- tr corner: (168,16)
        -- Max distance = 120
    -- Controls filter cutoff for channel 1 instrument
    centerdist = math.pow(math.pow(pacx - 96, 2) + math.pow(pacy - 112, 2), 0.5)
    MIDI.CC(1, 64 - math.floor(centerdist/2 + 0.5), 1);
    
    -- channel 2-5 mod = modified ghost distance from player
    -- controls the intensity of each of the ghosts' notes
    g1dist = math.max(0, 127 - math.pow(math.pow(pacx - g1x, 2) + math.pow(pacy - g1y, 2), 0.5));
    g2dist = math.max(0, 127 - math.pow(math.pow(pacx - g2x, 2) + math.pow(pacy - g2y, 2), 0.5));
    g3dist = math.max(0, 127 - math.pow(math.pow(pacx - g3x, 2) + math.pow(pacy - g3y, 2), 0.5));
    g4dist = math.max(0, 127 - math.pow(math.pow(pacx - g4x, 2) + math.pow(pacy - g4y, 2), 0.5));
    
    -- Set ghosts' channels modulation values based on distance to player    
    MIDI.CC(1, math.floor(g1dist), 2);
    MIDI.CC(1, math.floor(g2dist), 3);
    MIDI.CC(1, math.floor(g3dist), 4);
    MIDI.CC(1, math.floor(g4dist), 5);
    
    -- Set ghosts' general purpose 1 control values based on L/R distance to player (for
    -- a panning effect). This causes an interesting effect when you go through the tunnel.
    MIDI.CC(16, math.floor(64 + (g1x - pacx)/3 + 0.5), 2);
    MIDI.CC(16, math.floor(64 + (g2x - pacx)/3 + 0.5), 3);
    MIDI.CC(16, math.floor(64 + (g3x - pacx)/3 + 0.5), 4);
    MIDI.CC(16, math.floor(64 + (g4x - pacx)/3 + 0.5), 5);
    
    -- Get ghosts' directions
    g1dir = getdirection(g1x - g1lastx, g1y - g1lasty);
    g2dir = getdirection(g2x - g2lastx, g2y - g2lasty);
    g3dir = getdirection(g3x - g3lastx, g3y - g3lasty);
    g4dir = getdirection(g4x - g4lastx, g4y - g4lasty);
    
    -- Play notes based on change in score and location on channels 1,6
    if (score ~= lastscore) then
        -- 10 points per pellet (modulo 50 so ghosts eaten at the same time as a pellet make noise)
        if (((score - lastscore)%50) == 10) then
            -- pick a random note from pacnotes array
            pacnote = math.floor(pacnotecount * math.random()) + 1;
            -- don't repeat notes, play the next note in the array if it's the same one as last time
            if (pacnote == lastpacnote) then
                pacnote = pacnote % (pacnotecount) + 1;
            end;
            -- transpose note based on which level the player is on.
            MIDI.noteonwithduration(pacnotes[pacnote] - ((level%3)*2), 80, 1, 1);
            if (powerup == 1) then
                -- if powerup is enabled play another higher note at the same time
                MIDI.noteonwithduration(pacnotes[pacnote] - ((level%3)*2) + 7, 80, 1, 1);
            end;
            lastpacnote = pacnote;
            
            pellets = pellets + 1;
            if (pellets % 30 == 0) then
                -- add an octave to the ghost note every 30 pellets
                MIDI.noteonwithduration(g1lastnote + 24, 100, 60, 5);
                MIDI.noteonwithduration(g2lastnote + 12, 100, 60, 4);
                MIDI.noteonwithduration(g3lastnote + 24, 100, 60, 3);
                MIDI.noteonwithduration(g4lastnote + 12, 100, 60, 2);
            end;
            
        end;
        -- 50 points for power pellet
        if (score-lastscore == 50) then
            -- play longer note for power pellet
            MIDI.noteonwithduration(60, 100, 6, 1);
        end;
        -- 200, 400, 800, 1600 points for eating ghosts
        -- (the -10 case is for when a pellet and ghost coincide)
        if ((score - lastscore == 200) or (score - 10 - lastscore == 200)) then
            MIDI.noteonwithduration(56, 100, 60, 6);
        end;
        if ((score - lastscore == 400) or (score - 10 - lastscore == 400)) then
            MIDI.noteonwithduration(56, 100, 60, 6);
        end;
        if ((score - lastscore == 800) or (score - 10 - lastscore == 800)) then
            MIDI.noteonwithduration(49, 100, 60, 6);
        end;
        if ((score - lastscore == 1600) or (score - 10 - lastscore == 1600)) then
            MIDI.noteonwithduration(49, 100, 60, 6);
        end;
        -- 100, 300, 500, 700, 1000, 2000+ for various fruits
        if (score-lastscore == 100) then
            MIDI.noteonwithduration(60, 100, 6, 1);
        end;
        if (score-lastscore == 300) then
            MIDI.noteonwithduration(60, 100, 6, 1);
        end;
        if (score-lastscore == 500) then
            MIDI.noteonwithduration(60, 100, 6, 1);
        end;
        if (score-lastscore == 700) then
            MIDI.noteonwithduration(60, 100, 6, 1);
        end;
        if ((score-lastscore == 1000) or (score-lastscore >= 2000)) then
            MIDI.noteonwithduration(60, 100, 6, 1);
        end;
    end;
    
    -- Choose the set of notes based on pacman's position:
    if (pacx > 96) then
        ghostnotes = ghostnotes1;
    else
        ghostnotes = ghostnotes2;
    end;
    if (pacy < 112) then
        pacnotes = pacnotes1;
    else
        pacnotes = pacnotes2;
    end;
    
    -- play starts: lives reduced by 1, or ghosts jump back in
    if ((lastlives - lives == 1)) or
        ((g1x ~= 0) and (g1y ~= 0) and (g1lastx == 0) and (g1lasty == 0)) then
        -- start playing ghosts' notes again when play starts
        ghostnoteson = true;
        -- play the starting sound
        MIDI.noteonwithduration(38, 100, 60, 1);
    end;
    
    -- pacman died if ghosts reset to location 0,0 (only need to check ghost1); stop playing ghosts' notes
    if ((g1x == 0) and (g1y == 0) and (g1lastx ~= 0) and (g1lasty ~= 0)) then
        -- stop note corresponding to g1dir, g2dir, etc
        MIDI.noteoff(g1lastnote, 2);
        MIDI.noteoff(g2lastnote, 3);
        MIDI.noteoff(g3lastnote, 4);
        MIDI.noteoff(g4lastnote, 5);
        ghostnoteson = false;
        MIDI.noteonwithduration(58, 100, 80, 6);
    elseif (ghostnoteson) then
        -- If the game is active, play the ghosts' notes:
        offset = math.floor((level*3)/2) -- increase the notes pitch every level
        -- If one of their directions changed, stop the last note and start playing the new one
        if ((g1dir ~= 0) and (g1dir ~= g1lastdir)) then
            -- stop the last note
            MIDI.noteoff(g1lastnote, 2);
            -- play the note corresponding to g1dir
            MIDI.noteon(ghostnotes[g1dir] + offset, 100, 2);
            g1lastnote = ghostnotes[g1dir] + offset;
            g1lastdir = g1dir;
        end;
        if ((g2dir ~= 0) and (g2dir ~= g2lastdir)) then
            MIDI.noteoff(g2lastnote, 3);
            MIDI.noteon(ghostnotes[g2dir] + offset, 100, 3);
            g2lastnote = ghostnotes[g2dir] + offset;
            g2lastdir = g2dir;
        end;
        if ((g3dir ~= 0) and (g3dir ~= g3lastdir)) then
            MIDI.noteoff(g3lastnote, 4);
            MIDI.noteon(ghostnotes[g3dir] + offset, 100, 4);
            g3lastnote = ghostnotes[g3dir] + offset;
            g3lastdir = g3dir;
        end;
        if ((g4dir ~= 0) and (g4dir ~= g4lastdir)) then
            MIDI.noteoff(g4lastnote, 5);
            MIDI.noteon(ghostnotes[g4dir] + offset, 100, 5);
            g4lastnote = ghostnotes[g4dir] + offset;
            g4lastdir = g4dir;
        end;
    end;
    
    -- Update last values for comparison later
    lastscore = score;
    g1lastx = g1x;
    g1lasty = g1y;
    g2lastx = g2x;
    g2lasty = g2y;
    g3lastx = g3x;
    g3lasty = g3y;
    g4lastx = g4x;
    g4lasty = g4y;
    lastlives = lives;
    
    -- send midi messages
    MIDI.sendmessages();
    FCEU.frameadvance();
end;

