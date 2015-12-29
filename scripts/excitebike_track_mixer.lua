--[[
    Excitebike: interactive 'track' mixer
    Script for FCEUX + Emstrument
    
    This script turns the game into an interactive mixer where the players's position,
    speed and jumps control the sound of 4 tracks. The mapping between CCs and parameters
    cannot be stored in the Logic Pro X project, so the following section details how
    to map each parameter in your project.
    
    CC mapping:
    CC 16, channel 16 - percussion 1 low pass filter cutoff
    CC 17, channel 16 - bass/kick low pass filter cutoff
    CC 18, channel 16 - percussion 2 low pass filter cutoff
    CC 19, channel 16 - snare/clap low pass filter cutoff
    CC 16, channel 15 - output track reverb output
    CC 17, channel 15 - output track reverb dry output
    CC 18, channel 15 - output track high pass filter cutoff
    CC 19, channel 15 - output track high pass filter resonance
    
    These CCs can be easily mapped using the cc_mapper.lua script.
    
    Once the CCs have been mapped as shown above, this script will work with the Logic 
    Pro X project "excitebike_track_mixer.logicx".
    
    Note: This script does not output any notes so it is necessary for the DAW
    to be playing the 4 tracks in a loop for any sound to be manipulated.
    
    Tested with Excitebike (Japan, USA).nes
    First published 12/2015 by Ben/Signal Narrative
    
    Special thanks to XKeeper's 'Excitingbike' Lua script for speed calculation.
]]

require('emstrument');
MIDI.init();

-- keep track of these to see if they change frame to frame
lastlane = 0;
lastspeed = 0;
lastjump = 0;
-- high pass filter to be applied on jumps
hpamount = 0;
hpres = 0;
-- the time counter variable is only used to rhythmically flash the track labels
t = 0;

while (true) do
    lane = memory.readbyte(0x00B8); -- 14, 26, 38, or 50 for each lane, 
    -- the value is in-between while switching lanes and <14 or >50 if off track.
    jump = memory.readbyte(0x00B0); -- 0 if on ground, 2 if in the air
    
    -- max ground speed is 800 for normal acceleration
    speed = memory.readbyte(0x0094) * 0x100 + memory.readbyte(0x0090);
    
    -- Speed controls the final output volume - at low speeds some of it is reverbed,
    -- to sound more distant
    if (speed ~= lastspeed) then
        dryOut = 32 + math.min(95, math.floor(speed/800 * 95));
        MIDI.CC(16, dryOut, 15);
        wetOut = 32 - math.min(32, math.floor(speed/800 * 32));
        MIDI.CC(17, wetOut, 15);
    end;
    
    -- If the player changed lanes, change the mixing of the 4 tracks
    if (lane ~= lastlane) then
        if (lane < 14) then
            -- we're under the 4th (bottom) lane
            MIDI.CC(17, 127 - 14*(14 - lane), 16);
            MIDI.CC(19, 0, 16);
            MIDI.CC(16, 0, 16);
            MIDI.CC(18, 0, 16);
        elseif ((lane >= 14) and (lane < 26)) then
            -- we're in the 4th lane or between it and the 3rd lane
            MIDI.CC(17, 127, 16);
            MIDI.CC(19, 127 - 10*(26 - lane), 16);
            MIDI.CC(16, 0, 16);
            MIDI.CC(18, 0, 16);
        elseif ((lane >= 26) and (lane < 38)) then
            -- we're in the 3th lane or between it and the 2rd lane
            MIDI.CC(17, 127, 16);
            MIDI.CC(19, 127, 16);
            MIDI.CC(16, 127 - 10*(38 - lane), 16);
            MIDI.CC(18, 0, 16);
        elseif ((lane >= 38) and (lane < 50)) then
            -- we're in the 2th lane or between it and the 1st lane
            MIDI.CC(17, 127, 16);
            MIDI.CC(19, 127, 16);
            MIDI.CC(16, 127, 16);
            MIDI.CC(18, 127 - 10*(50 - lane), 16);
       elseif (lane >= 50) then
            -- we're in the 1st (top) lane or above it (where the player goes when they crash)
            MIDI.CC(17, 127 - 14*(lane - 50), 16);
            MIDI.CC(19, 127 - 14*(lane - 50), 16);
            MIDI.CC(16, 127 - 14*(lane - 50), 16);
            MIDI.CC(18, 127 - 14*(lane - 50), 16);
        end;
    end;
    
    -- When jumping, increase the output track high pass filter cutoff/resonance
    if (jump ~= 0) then
        hpamount = math.min(hpamount + 5, 127); -- don't increase past 127
        hpres = math.min(96, hpres + 3, 80); -- don't increase past 80
        MIDI.CC(18, hpamount, 15);
        MIDI.CC(19, hpres, 15);
    elseif (jump ~= lastjump) then
        -- we landed, reset the high pass variables
        hpamount = 0;
        hpres = 0;
        MIDI.CC(18, hpamount, 15);
        MIDI.CC(19, hpres, 15);
    end;
    

    -- Draw track labels
    gui.text(200, 166, " Bass   ", "white", "black");
    gui.text(200, 154, " Snare  ", "white", "black");
    gui.text(200, 142, " Perc 1 ", "white", "black");
    gui.text(200, 130, " Perc 2 ", "white", "black");
    
    -- Draw the active tracks' labels on top of the normal track labels.
    -- The labels flash at 60 or 120bpm. Change the 30 to BPM/2 or BPM/4 if your
    -- project has a different BPM.
    if (t%30 > 3) then
        if (lane < 14) then
            -- we're under the 4th (bottom) lane
        elseif ((lane >= 14) and (lane < 26)) then
            -- we're in the 4th lane or between it and the 3rd lane
            gui.text(200, 166, " Bass   ", "white", "gray");
        elseif ((lane >= 26) and (lane < 38)) then
            -- we're in the 3th lane or between it and the 2rd lane
            gui.text(200, 166, " Bass   ", "white", "gray");
            gui.text(200, 154, " Snare  ", "white", "gray");
        elseif ((lane >= 38) and (lane < 50)) then
            -- we're in the 2th lane or between it and the 1st lane
            gui.text(200, 166, " Bass   ", "white", "gray");
            gui.text(200, 154, " Snare  ", "white", "gray");
            gui.text(200, 142, " Perc 1 ", "white", "gray");
       elseif (lane >= 50) then
            -- we're in the 1st (top) lane or above it (where the player goes when they crash)
            gui.text(200, 166, " Bass   ", "white", "gray");
            gui.text(200, 154, " Snare  ", "white", "gray");
            gui.text(200, 142, " Perc 1 ", "white", "gray");
            gui.text(200, 130, " Perc 2 ", "white", "gray");
        end;
    end;
    
    -- increment time counter
    t = t + 1;
    -- store values for comparison later on
    lastlane = lane;
    lastspeed = speed;
    lastjump = jump;
    -- send midi messages
    MIDI.sendmessages();
    FCEU.frameadvance();
end;

