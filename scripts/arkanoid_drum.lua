--[[
    Arkanoid: drum machine
    Script for FCEUX + Emstrument
    
    This script turns the game into an interactive drum machine that triggers percussion
    when the ball strikes various objects in the game. The sounds are quantized to 1/6th 
    second, in order to keep a regular rhythm. An indicator is drawn on the right side of 
    the screen to indicate which sounds are being triggered.

    Unlike the other example scripts, this one modifies the game by preventing the ball(s)
    from leaving the playfield - when a ball hits the bottom of the screen, it jumps to the 
    top, and vice versa, creating the illusion that the game wraps around vertically. This 
    is to prevent the game from stopping in the middle of a beat when the player loses the 
    ball, as well as to create more interesting rhythms by always keeping all 3 balls in 
    play when the player gets the multi-ball powerup.
    
    Tested with Arkanoid (U) [b2].nes
    First published 12/2015 by Ben/Signal Narrative
    
    Thanks to http://datacrystal.romhacking.net/wiki/Arkanoid:RAM_map for some RAM info.
    The score and multi-ball locations were found by manually searching the RAM.
]]

require('emstrument');
MIDI.init();

-- X,Y coordinates and X/Y directions for the 3 balls
x = {0, 0, 0};
y = {0, 0, 0};
dx = {0, 0, 0};
dy = {0, 0, 0};
lastx = {0, 0, 0};
lasty = {0, 0, 0};
lastdx = {0, 0, 0};
lastdy = {0, 0, 0};

-- A table used to store what sounds to play at the next 1/6th second
play = {};
-- A table used to store which percussion displays to draw
draw = {};
-- How many total ball bounces occured in the last 1/6th second
bounces = 0;

t = 0;

while (true) do
    -- Get ball positions
    -- If only 1 ball is active, the others won't be moving and will not trigger any sounds
    y[1] = memory.readbyte(0x0037);
    x[1] = memory.readbyte(0x0038);
    y[2] = memory.readbyte(0x0051);
    x[2] = memory.readbyte(0x0052);
    y[3] = memory.readbyte(0x006B);
    x[3] = memory.readbyte(0x006C);
    
    -- The score is not currently used in this script, but is here for reference:
    score10_0 = memory.readbyte(0x0375);
    score10_1 = memory.readbyte(0x0374);
    score10_2 = memory.readbyte(0x0373);
    score10_3 = memory.readbyte(0x0372);
    score10_4 = memory.readbyte(0x0371);
    score = score10_0 + 10*score10_1 + 100*score10_2 + 1000*score10_3 + 10000*score10_4;
    
    for i=1,3 do
        -- Figure out which direction the ball is moving in
        -- make sure the ball isn't "jumping in", like when the multi-ball powerup is activated
        if ((math.abs(x[i] - lastx[i]) < 16) and (math.abs(y[i] - lasty[i]) < 16)) then
            -- If the x value didn't change, don't treat that as a change in direction,
            -- since if the ball is traveling at 0.5 pixels left per frame there will 
            -- be a "change" in x-direction every frame (direction = 0, 1, 0, 1, etc).
            if (x[i] - lastx[i] ~= 0) then
                dx[i] = math.floor((x[i] - lastx[i])/math.abs(x[i] - lastx[i]));
            end;
    
            if (y[i] - lasty[i] ~= 0) then
                dy[i] = math.floor((y[i] - lasty[i])/math.abs(y[i] - lasty[i]));
            end;
        end;
        
        
        if (lastdx[i] ~= dx[i]) then
            -- if the x direction changed play a mid tom
            play['hh'] = true;
            bounces = bounces + 1;
        end;
        
        if (lastdy[i] ~= dy[i]) then
            if (dy[i] < 0) then
                -- if the y direction is now up, play a bass drum if it just hit the paddle
                -- otherwise play a hi-hat
                if (y[i] > 192) then
                    play['bd'] = true;
                else
                    play['mt'] = true;
                end;
                bounces = bounces + 1;
            end;
            if (dy[i] > 0) then
                -- if the y direction is now down, play a snare
                play['sn'] = true;
                bounces = bounces + 1;
            end;
        end;
        
        -- copy each value individually, since just saying 'lastx = x' would copy by reference
        lastx[i] = x[i];
        lasty[i] = y[i];
        lastdx[i] = dx[i];
        lastdy[i] = dy[i];
    end;
    
    -- If any of the balls hit the bottom or top of the screen, move them to the top or
    -- bottom respectively
    for i=1,3 do
        if (y[1] > 230) then
            memory.writebyte(0x0037, 20);
        end;
        if (y[2] > 230) then
            memory.writebyte(0x0051, 20);
        end;
        if (y[3] > 230) then
            memory.writebyte(0x006B, 20);
        end;
        if (y[1] < 20) then
            memory.writebyte(0x0037, 228);
        end;
        if (y[2] < 20) then
            memory.writebyte(0x0051, 228);
        end;
        if (y[3] < 20) then
            memory.writebyte(0x006B, 228);
        end;
    end;

    -- We only play sounds at every 6th of a second, to keep them roughly in time.
    -- Ideally the physics could be modified to do this in-game, but that's not
    -- possible without hardcore disassembly hacking.
    if (t%10 == 0) then
        draw = {};
        if (play['mt']) then
            if (bounces < 3) then
                MIDI.noteonwithduration(41, 100, 5); -- mid tom
                draw['mt'] = true;
            else
                MIDI.noteonwithduration(49, 100, 5); -- crash
                draw['cr'] = true;
            end
        end;
        if (play['hh']) then
            MIDI.noteonwithduration(42, 100, 5); -- hi-hat          
            draw['hh'] = true;
        end;
        if (play['bd']) then
            MIDI.noteonwithduration(36, 100, 5); -- kick
            draw['bd'] = true;
        end;
        if (play['sn']) then
            MIDI.noteonwithduration(38, 100, 5); -- snare
            draw['sn'] = true;
        end;
        
        -- clear the bounces counter
        bounces = 0;
        -- clear the play table
        play = {};
    end;
    
    -- draw the sounds we played on the right side of the screen (outside the game area)
    gui.drawrect(209, 145, 223, 159, "gray");
    gui.drawtext(211, 148, "BD", "blue", "gray");
    if (draw['bd']) then
        gui.drawrect(209, 145, 223, 159, "white");
        gui.drawtext(211, 148, "BD", "blue", "white");
    end;
    gui.drawrect(225, 145, 239, 159, "gray");
    gui.drawtext(227, 148, "SN", "blue", "gray");
    if (draw['sn']) then
        gui.drawrect(225, 145, 239, 159, "white");
        gui.drawtext(227, 148, "SN", "blue", "white");
    end;
    gui.drawrect(209, 161, 223, 175, "gray");
    gui.drawtext(211, 164, "MT", "blue", "gray");
    if (draw['mt']) then
        gui.drawrect(209, 161, 223, 175, "white");
        gui.drawtext(211, 164, "MT", "blue", "white");
    end;
    gui.drawrect(225, 161, 239, 175, "gray");
    gui.drawtext(227, 164, "HH", "blue", "gray");
    if (draw['hh']) then
        gui.drawrect(225, 161, 239, 175, "white");
        gui.drawtext(227, 164, "HH", "blue", "white");
    end;
    gui.drawrect(209, 177, 223, 191, "gray");
    gui.drawtext(211, 180, "CR", "blue", "gray");
    if (draw['cr']) then
        gui.drawrect(209, 177, 223, 191, "white");
        gui.drawtext(211, 180, "CR", "blue", "white");
    end;
    
    -- advance time, send midi messages
    t = t+1
    MIDI.sendmessages();
    FCEU.frameadvance();
end;

