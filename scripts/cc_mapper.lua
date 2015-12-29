--[[
    CC Mapper
    Script for FCEUX + Emstrument
    
    This script is for mapping CCs to parameters in a DAW (digital audio workstation).
    
    The user selects a CC number and channel using the NES controller d-pad.
    When the A button is pressed it outputs CC messages on that channel, allowing the DAW 
    to map that CC number/channel to an instrument/effect/mixer parameter.
    
    How this is done on the DAW side differs.
    Generally the user goes into a "learn" mode, clicks a parameter in the DAW,
    and then sends a CC from this script to map that CC to the parameter. However this is
    not always the case. See the DAW documentation for more details.
    
    This script can be run with any ROM; the user interface is drawn on top of whatever
    game is running.
    
    Note:
    Many CCs are undefined or may not always be mappable. Read up on all the different
    CCs at http://www.midi.org/techspecs/midimessages.php (table 3).
    
    First published 12/2015 by Ben/Signal Narrative
]]

require('emstrument');
MIDI.init();

CC = 0;
channel = 1;
direction = -1; -- r = 0, u = 1, l = 2, d = 3
t = 0; -- timer for increment/decrement auto-repeat
v = 0; -- value to send for CC/channel

while (true) do
    buttons = joypad.read(1);
    
    if (buttons.right == true) then
        if (direction ~= 0) then
            direction = 0;
            t = 1;
        end;
        if (direction == 0) then
            t = t - 1;
            if (t <= 0) then
                CC = (CC + 1)%120;
                t = 10;
            end;
        end;
    elseif (buttons.up == true) then
        if (direction ~= 1) then
            direction = 1;
            t = 1;
        end;
        if (direction == 1) then
            t = t - 1;
            if (t <= 0) then
                channel = channel + 1;
                if (channel > 16) then
                    channel = 1;
                end;
                t = 10;
            end;
        end;
    elseif (buttons.left == true) then
        if (direction ~= 2) then
            direction = 2;
            t = 1;
        end;
        if (direction == 2) then
            t = t - 1;
            if (t <= 0) then
                CC = (CC - 1)%120;
                t = 10;
            end;
        end;
    elseif (buttons.down == true) then
        if (direction ~= 3) then
            direction = 3;
            t = 1;
        end;
        if (direction == 3) then
            t = t - 1;
            if (t <= 0) then
                channel = channel - 1;
                if (channel < 1) then
                    channel = 16;
                end;
                t = 10;
            end;
        end;
    else
        direction = -1;
    end;
    
    gui.text(0, 40, "CC Mapper:");
    gui.text(0, 48, "Left/Right to change CC");
    gui.text(0, 56, "Up/Down to change channel");
    
    gui.text(0, 72, "Current CC: "..CC);
    gui.text(0, 80, "Current channel: "..channel);
    
    gui.text(0, 96, "A button to send CC"..CC.." message on channel "..channel);
    
    if (buttons.A == true) then
        MIDI.CC(CC, v, channel);
        v = (v + 1)%127;
        gui.text(16, 104, "sending...");
    end;
    
    -- send midi messages
    MIDI.sendmessages();
    FCEU.frameadvance();
end;

