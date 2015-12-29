--[[
    Tetris: multi-sequencer composition
    Script for FCEUX + Emstrument
    
    This script turns the tetris board into a virtual sequencer. The height of the blocks 
    in each column is used to trigger the bassline and a lead synth.
    The number of gaps (empty vertical spaces between blocks) in each column triggers percussion. 
    The behavior of the sequencer changes every few iterations. The sequencer's behavior
    also changes in response to cleared lines.
    Each piece, when initialized or rotated, produces a signature chord played on another synth.
    
    Each game starts out with an empty board, which creates little sound, but as pieces start piling 
    up and holes show up in each column, the music becomes more and more frantic. One fun thing to
    note is that the musical results are more interesting when the player makes mistakes, leading
    to possibly shorter games.
    For best results, play in mode A at a high level (7 or above).
    
    This script works with the Logic Pro X project "tetris.logicx"
    
    Tested with Tetris (USA).nes
    First published 12/2015 by Ben/Signal Narrative
    
    Special thanks to http://datacrystal.romhacking.net/wiki/Tetris_(NES):RAM_map
]]

-- This script sends MIDI over 4 channels:
-- 1: Bass synth (mod wheel mapped to LPF cutoff)
-- 2: Drum sampler, standard MIDI drum kit mapping
-- 3: Lead synth
-- 4: Chord synth

require('emstrument');
MIDI.init();

t = 0;
colNote = 0;
lastScore = 0;
lastLevel = 0;
lastPieceID = -1;
lastPieceX = -1;
lastPieceY = -1;

bassnotes = {38, 41, 43, 45, 48};
-- percussion: just repeat elements to avoid messy modulo with Lua's 1-indexed arrays
percussion = {36, 38, 45, 36, 40, 38, 55, 36, 57, 36, 38, 45, 36, 40, 38, 55, 36, 57};
percussion_alternate = {42, 38, 42, 36, 42, 40, 38, 55, 36, 45, 42, 38, 42, 36, 42, 40, 38, 55, 36, 45, 45, 45, 45, 45, 45, 45, 45};
leadnotes = {50, 52, 53, 55, 57, 60, 62, 64, 65, 67, 69, 72, 74, 76, 77, 79, 81, 84, 86, 88, 89};

-- The chord that is played for each rotation of each piece (rotations have the same notes in different order)
piecenotes = {
    {50, 55, 60}, {55, 60, 62}, {60, 62, 67}, {50, 60, 67}, -- T-block
    {50, 57, 60}, {57, 60, 62}, {60, 62, 69}, {50, 60, 69}, -- L-block
    {50, 52, 57}, {52, 57, 62}, -- Z-block
    {52, 57, 60}, -- square block
    {50, 55, 57}, {55, 57, 62}, -- S-block
    {50, 53, 60}, {53, 60, 62}, {60, 62, 65}, {50, 60, 65}, -- inverse L-block
    {50, 53, 57}, {53, 62, 69} -- I-block
}   

-- Cycles for bass/percussion: 8x normal, 4x alternate percussion, 2x percussion only
bpBehavior = 0; -- 0: normal, 1: alternate percussion, 2: percussion only
bpBehaviorTimer = 0;
bpBehaviorCycles = {80,40,20};
beatlength = 8;

-- Cycles for lead: 4 cycles off, 20 cycles on
leadBehavior = 0; -- 0: off 1: on
leadBehaviorTimer = 0;
leadBehaviorCycles = {4,20};
leadColNote = 0;
leadBeatLength = 80;
lastLeadNote = 0;

-- When a certain number of lines is cleared activeLinesRoutine is set to 1-4, triggering a sequence
linesRoutineStep = 0;
linesRoutineTimer = -1;
activeLinesRoutine = 0;
playDirection = 1; -- 1: forward, -1: backwards

while (true) do
    
    -- We need the score to figure out whether the player just cleared some lines
    -- The score is encoded in binary-coded decimal: https://en.wikipedia.org/wiki/Binary-coded_decimal
    level = memory.readbyte(0x0044)
    -- least significant 4 bits: ones digit, most significant 4 bits: tens digit
    scoreA = memory.readbyte(0x0053); 
    -- least significant 4 bits: hundreds digit, most significant 4 bits: thousands digit
    scoreB = memory.readbyte(0x0054);
    -- least significant 4 bits: ten-thousands digit, most significant 4 bits: hundred-thousands digit
    scoreC = memory.readbyte(0x0055);
    
    score10_0 = scoreA%16;
    score10_1 = math.floor(scoreA/16);
    score10_2 = scoreB%16;
    score10_3 = math.floor(scoreB/16) % 16;
    score10_4 = scoreC%16;
    score10_5 = math.floor(scoreC/16) % 16;
    score = 100000*score10_5 + 10000*score10_4 + 1000*score10_3 + 100*score10_2 + 10*score10_1 + score10_0;
    
    
    pieceID = memory.readbyte(0x0042);
    pieceX = memory.readbyte(0x0040);
    pieceY = memory.readbyte(0x0041);
    -- Uncomment to see which pieceID is currently in play and its position
    -- gui.text(0, 8, pieceID.." at "..pieceX..","..pieceY);
    
    -- Play the chord associated with the pieceID, if the pieceID changed, OR if the same piece was just
    -- introduced at the top of the screen
    if ((pieceID ~= lastPieceID) or (pieceY < lastPieceY)) and (pieceID <= 18) then
        -- The piece/chord instrument is set to channel 4
        MIDI.allnotesoff(4);
        MIDI.noteonwithduration(piecenotes[pieceID+1][1], 100, 15, 4);
        MIDI.noteonwithduration(piecenotes[pieceID+1][2], 100, 15, 4);
        MIDI.noteonwithduration(piecenotes[pieceID+1][3], 100, 15, 4);
    end;
    
    -- Read through the board to see where the blocks are to measure each column and its gaps
    --$0400-0409    top row
    --$040A-0413    2nd row
    --$04BE-04C7    19th row (bottom)
    -- contents%10 are 3, 4 or 5 depending on the color of the block
    boardPointer = 0x0400;
    
    topPositions = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}; -- height of the top block in the 10 columns
    numberOfGaps = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}; -- how many gaps between blocks exist in the 10 columns
    totalGaps = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0}; -- how many total spaces are in the gaps in the 10 columns
    
    -- board is 10 wide
    for i=1,10 do
        gap = 0;
        -- board is 19 tall
        for j=20,1,-1 do
            v = memory.readbyte(boardPointer) % 10;
            if (v ~= 9) then
                if (j > topPositions[i]) then
                    topPositions[i] = j;
                end
                if (gap == 1) then
                    gap = 0;
                    numberOfGaps[i] = numberOfGaps[i] + 1;
                end
            else
                if (topPositions[i] > 0) then
                    gap = 1;
                    totalGaps[i] = totalGaps[i] + 1;
                end
            end
            -- the board's contents are arranged in row-major order, so we need to 
            -- increment by 10 (the width) to get to the next row
            boardPointer = boardPointer + 10;
        end
        if (gap == 1) then
            numberOfGaps[i] = numberOfGaps[i] + 1;
        end
        
        -- increment to the next column
        boardPointer = 0x0400 + i;
        
        -- Uncomment to see each column's stats printed at the top of the screen
        -- gui.text((i-1)*24, 16, topPositions[i]);
        -- gui.text((i-1)*24, 24, numberOfGaps[i]);
        -- gui.text((i-1)*24, 32, totalGaps[i]);
    end
    
    
    -- Play/stop the lead instrument (channel 3);
    -- This code is only run once every 80 frames (leadBeatLength)
    if (t % leadBeatLength == 0) then
        -- leadBehaviorTimer controls when we turn the lead instrument on or off
        if (leadBehaviorTimer <= 0) then
            leadBehavior = (leadBehavior + 1) % 2;
            leadBehaviorTimer = leadBehaviorCycles[leadBehavior+1];
            MIDI.allnotesoff(3);
        end;
        -- If we want the lead instrument on, play the note corresponding to the current column's height,
        -- unless that note was already playing, in that case let it keep playing
        if (leadBehavior == 1) then
            leadNote = math.floor(topPositions[leadColNote+1] % 21) + 1;
            if (leadNote ~= lastLeadNote) then
                MIDI.noteoff(lastLeadNote, 3);
                MIDI.noteon(leadnotes[leadNote], 100, 3);
                lastLeadNote = leadnotes[leadNote];
            end;
        end;
        leadColNote = (leadColNote + 1) % 10;
        -- Decrement leadBehaviorTimer. Behavior changes when it hits 0
        leadBehaviorTimer = leadBehaviorTimer - 1;
    end;
    
    -- Play the bass (channel 1) and percussion (channel 2) instruments
    -- This code runs once every 'beatlength' frames (8 by default but beatlength can change)
    if (t % beatlength == 0) then
        -- play notes for 4/3 beatlength. If the same note is played again the first one is stopped
        -- before the second one starts. Round down, as all durations have to be integers.
        notelength = math.floor(beatlength * 4 / 3)
        
        -- bpBehaviorTimer controls when we change the sequencer behavior for the bass and percussion (bp)
        if (bpBehaviorTimer <= 0) then
            bpBehavior = (bpBehavior+1)%3;
            bpBehaviorTimer = bpBehaviorCycles[bpBehavior + 1];
        end;
        
        -- Play a bass note on channel 1 corresponding to topPositions[colNote] as long as bpBehavior is
        -- not 2 (percussion only)
        if ((bpBehavior ~= 2)) then
            bassnote = math.floor(topPositions[colNote+1] % 5) + 1
            -- Instead of playing higher and higher bass notes, play one of the same 5 notes in 'bassnotes', but 
            -- also send a CC corresponding to the total height which reduces the low pass filter on the bass note,
            -- adding higher pitched harmonics to the note, making it sound higher.
            MIDI.noteonwithduration(bassnotes[bassnote], 100, notelength, 1);
            MIDI.CC(1, topPositions[colNote+1]*4, 1);
        end;
        
        -- Play percussion if the current column has any gaps
        if ((numberOfGaps[colNote+1] >= 1) and (numberOfGaps[colNote+1] <= 9)) then
            -- bpBehavior 0: Play percussion from 'percussion' based on number of gaps
            if ((bpBehavior == 0)) then
                MIDI.noteonwithduration(percussion[numberOfGaps[colNote+1]], 127, 4, 2);
                -- Add closed hi-hat if column height is at 9 or above
                if (topPositions[colNote+1] > 9) then
                    MIDI.noteonwithduration(42, 127, 4, 2); -- closed hi hat
                end;
            end;
            -- bpBehavior 1: Play percussion from 'percussion_alternate' based on number of gaps
            if (bpBehavior == 1) then
                perc_index = totalGaps[colNote+1];
                MIDI.noteonwithduration(percussion_alternate[totalGaps[colNote+1]], 127, 4, 2);
                -- Add bass drum if column height is at 9 or above
                if (topPositions[colNote+1] > 9) then
                    MIDI.noteonwithduration(36, 127, 4, 2); -- bass drum
                end;
            end;
            -- bpBehavior 2: Play percussion from 'percussion_alternate' based on total gap spaces
            if ((bpBehavior == 2)) then
                MIDI.noteonwithduration(percussion_alternate[topPositions[colNote+1]+1], 127, 4, 2);
                -- Add closed hi-hat if column height is at 9 or above
                if (topPositions[colNote+1] > 9) then
                    MIDI.noteonwithduration(42, 127, 4, 2); -- closed hi hat
                end;
            end;
        end;
        bpBehaviorTimer = bpBehaviorTimer - 1;
        
        -- If some lines were cleared recently, then modify the sequencer behavior accordingly:
        if (activeLinesRoutine == 4) then
            -- 4 lines: Play a crash cymbal, play the sequencer backwards at 2x speed for 20 iterations,
            -- then play a clap and play the last 2 notes 5 times.
            -- linesRoutineStep tells us which of those steps we're on.
            if (linesRoutineStep > 6) then
                -- routine is done, go back to normal behavior
                activeLinesRoutine = 0;
                linesRoutineStep = 0;
                linesRoutineTimer = -1;
            elseif (linesRoutineTimer == 0) then
                if (linesRoutineStep == 0) then
                    MIDI.noteonwithduration(49, 100, 30, 2);
                    playDirection = -1;
                    linesRoutineTimer = 20;
                    beatlength = 4;
                end;
                if (linesRoutineStep >= 1) then
                    if (linesRoutineStep > 1) then
                        colNote = (colNote - 2) % 10;
                    else
                        MIDI.noteonwithduration(39, 100, 30, 2);
                    end;
                    playDirection = 1;
                    beatlength = 8;
                    linesRoutineTimer = 2;
                end;
                linesRoutineStep = linesRoutineStep + 1;
            end;
        elseif (activeLinesRoutine == 3) then
            -- 3 lines: Play an open hat, play the sequencer backwards at 2x speed for 10 iterations,
            -- then play a clap and play the last 2 notes 2 times.
            if (linesRoutineStep > 3) then
                activeLinesRoutine = 0;
                linesRoutineStep = 0;
                linesRoutineTimer = -1;
            elseif (linesRoutineTimer == 0) then
                if (linesRoutineStep == 0) then
                    MIDI.noteonwithduration(46, 100, 30, 2);
                    playDirection = -1;
                    linesRoutineTimer = 10;
                    beatlength = 4;
                end;
                if (linesRoutineStep >= 1) then
                    if (linesRoutineStep > 1) then
                        colNote = (colNote - 2) % 10;
                    else
                        MIDI.noteonwithduration(39, 100, 30, 2);
                    end;
                    playDirection = 1;
                    beatlength = 8;
                    linesRoutineTimer = 2;
                end;
                linesRoutineStep = linesRoutineStep + 1;
            end;
        elseif (activeLinesRoutine == 2) then
            -- 2 lines: play a crash then repeat the last 2 notes 4 times
            if (linesRoutineStep > 5) then
                activeLinesRoutine = 0;
                linesRoutineStep = 0;
                linesRoutineTimer = -1;
                playDirection = 1;
            elseif ((linesRoutineStep <= 5) and (linesRoutineTimer == 0)) then
                if (linesRoutineStep > 0) then
                    colNote = (colNote + 2) % 10;
                else
                    MIDI.noteonwithduration(49, 100, 30, 2);
                end;
                playDirection = -1;
                linesRoutineTimer = 2;
                linesRoutineStep = linesRoutineStep + 1;
            end;
        elseif (activeLinesRoutine == 1) then
            -- 1 line: play a crash then repeat the last 2 notes twice
            if (linesRoutineStep > 2) then
                activeLinesRoutine = 0;
                linesRoutineStep = 0;
                linesRoutineTimer = -1;
            elseif ((linesRoutineStep <= 2) and (linesRoutineTimer == 0)) then
                if (linesRoutineStep > 0) then
                    colNote = (colNote - 2) % 10;
                else
                    MIDI.noteonwithduration(46, 100, 30, 2);
                end;
                playDirection = 1;
                linesRoutineTimer = 2;
                linesRoutineStep = linesRoutineStep + 1;
            end;
        end;
        if (activeLinesRoutine ~= 0) then
            linesRoutineTimer = linesRoutineTimer - 1;
        end
        
        -- Move on to the next column (either forward of backwards)
        colNote = (colNote + playDirection)%10;
    end
    
    -- Take the difference of the score last frame and the score now to see if lines were cleared
    dScore = score - lastScore;
    -- Scores vary depending on level, so check both current and 1 previous level, in case the level changed.
    -- Also need to account for 15(?) maximum that can be obtained by speed dropping the piece, and is
    -- added to the score at the same time as the line bonus.
    if ((dScore >= 40*(level+1)) and (dScore < 40*(level+1) + 16)) or
        ((level > 0) and (dScore >= 40*(level)) and (dScore < 40*(level) + 16)) then
        activeLinesRoutine = 1;
        linesRoutineStep = 0;
        linesRoutineTimer = 0;
        beatlength = 8; -- reset beatlength in case we get a line in the middle of another line routine.
    elseif ((dScore >= 100*(level+1)) and (dScore < 100*(level+1) + 16)) or
        ((level > 0) and (dScore >= 100*(level)) and (dScore < 100*(level) + 16)) then
        activeLinesRoutine = 2;
        linesRoutineStep = 0;
        linesRoutineTimer = 0;
        beatlength = 8;
    elseif ((dScore >= 300*(level+1)) and (dScore < 300*(level+1) + 16)) or
        ((level > 0) and (dScore >= 300*(level)) and (dScore < 300*(level) + 16)) then
        activeLinesRoutine = 3;
        linesRoutineStep = 0;
        linesRoutineTimer = 0;
        beatlength = 8;
    elseif ((dScore >= 1200*(level+1)) and (dScore < 1200*(level+1) + 16)) or
        ((level > 0) and (dScore >= 1200*(level)) and (dScore < 1200*(level) + 16)) then
        activeLinesRoutine = 4;
        linesRoutineStep = 0;
        linesRoutineTimer = 0;
        beatlength = 8;
    end
    
    -- Draw the current position of the bassline/percussion sequencer
    if (bpBehavior ~= 2) then
        currentColNote = (colNote - 1)%10;
        playhead1x = 96+currentColNote*8;
        playhead1y = 200 - 8*topPositions[currentColNote+1] + 4;
        gui.drawbox(playhead1x, playhead1y, playhead1x+6, playhead1y+2, "gray");
    end;
    
    -- Draw the current position of the lead sequencer
    if (leadBehavior == 1) then
        currentLeadColNote = (leadColNote - 1)%10;
        playhead2x = 96+currentLeadColNote*8;
        playhead2y = 200 - 8*topPositions[currentLeadColNote+1] + 4;
        gui.drawbox(playhead2x, playhead2y, playhead2x+6, playhead2y+2, "white");
    end;
    
    -- Store the last values of these values for comparison later on
    lastLevel = level;
    lastScore = score;
    lastPieceID = pieceID;
    lastPieceX = pieceX;
    lastPieceY = pieceY;

    -- Advance time, send midi messages
    t = t + 1;
    MIDI.sendmessages();
    FCEU.frameadvance();
end;

