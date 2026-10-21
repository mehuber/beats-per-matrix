function [env, isFinished] = adsr(attack, decay, sustain, release, fs, gateFrames, totalFrames, options)
%ADSR Attack-decay-sustain-release envelope: how a note's loudness changes over time.
%   env = bpm.dsp.adsr(attack, decay, sustain, release, fs, gateFrames, totalFrames)
%   returns a totalFrames x 1 column of gains between 0 and 1, one per sample,
%   for a note that starts at frame 0 and is released (key let go) after
%   gateFrames frames. Use gateFrames = Inf while the key is still held.
%
%   The four stages, with times in SECONDS and sustain as a LEVEL (0 to 1):
%       attack   rise from 0 to full level (1)             /\
%       decay    fall from 1 to the sustain level         /  \______
%       sustain  stay at that level while the key is     /          \
%                held                                    A  D   S    R
%       release  fall from wherever it is to 0 after the key is released
%   All four stages are straight lines (linear).
%
%   env = bpm.dsp.adsr(..., StartFrame=n) returns the frames n .. n+totalFrames-1
%   of the same note instead of 0 .. totalFrames-1. An instrument that renders
%   audio in blocks (PLAN.md decision D5) uses this to get one block's piece of a
%   note's envelope, with no envelope "state" to remember between blocks: the
%   envelope is a pure function of how many frames have passed since note-on.
%   That only works if the instrument passes the SAME attack/decay/sustain/
%   release for every block of a note: decide them at note-on and keep them.
%   (Changing them halfway re-draws the whole curve, which makes the level jump.)
%
%   env = bpm.dsp.adsr(..., StartLevel=L) starts the attack from level L instead
%   of 0. Use it to restart a note that is still sounding (a retrigger, or a
%   voice "stolen" for a new note) from its current level, without a click.
%
%   [env, isFinished] = bpm.dsp.adsr(...) also returns true once the envelope is
%   silent for good by the last requested frame (the release has finished, or a
%   sustain of 0 has been reached), so the voice can be freed.
%
%   Example: 10 ms attack, 100 ms decay to 70%, 300 ms release, at 44.1 kHz,
%   key held for half a second, 1 second of output:
%       env = bpm.dsp.adsr(0.01, 0.1, 0.7, 0.3, 44100, 22050, 44100);

    % An arguments block checks each input (size, type, allowed values) before
    % the function runs; "(1,1)" means exactly one value. "options.StartFrame"
    % declares an optional name-value argument, written by the caller as
    % adsr(..., StartFrame=1024); "= 0" is its default.
    arguments
        attack (1,1) double {mustBeNonnegative, mustBeFinite}
        decay (1,1) double {mustBeNonnegative, mustBeFinite}
        sustain (1,1) double {mustBeInRange(sustain, 0, 1)}
        release (1,1) double {mustBeNonnegative, mustBeFinite}
        fs (1,1) double {mustBePositive, mustBeFinite}
        gateFrames (1,1) double {mustBeNonNan, mustBeNonnegative}   % Inf = still held
        totalFrames (1,1) double {mustBeInteger, mustBeNonnegative}
        options.StartFrame (1,1) double {mustBeInteger, mustBeNonnegative} = 0
        options.StartLevel (1,1) double {mustBeInRange(options.StartLevel, 0, 1)} = 0
    end

    % Stage lengths in frames (samples). These can be fractions of a frame.
    a = attack * fs;
    d = decay * fs;
    r = release * fs;
    startLevel = options.StartLevel;

    % Frame numbers since note-on, as a column: (0:N-1)' is 0, 1, ..., N-1.
    n = options.StartFrame + (0:totalFrames - 1)';

    % Level while the key is held: attack, then decay, then sustain.
    env = heldLevel(n, a, d, sustain, startLevel);

    % After the key is released, fall in a straight line from the level the
    % note had at the moment of release down to 0, over r frames.
    released = n >= gateFrames;   % logical mask: true where the key is up
    if any(released)
        levelAtRelease = heldLevel(gateFrames, a, d, sustain, startLevel);
        if r == 0
            env(released) = 0;
        else
            framesIntoRelease = n(released) - gateFrames;
            env(released) = levelAtRelease .* max(0, 1 - framesIntoRelease / r);
        end
    end

    % The note is silent for good once the release has played out, or, with a
    % sustain level of 0, once the decay has reached 0 (if the key wasn't let go
    % before that: then the release decides).
    lastFrame = options.StartFrame + totalFrames - 1;
    releaseDone = lastFrame >= gateFrames + r;
    decayedToSilence = sustain == 0 && gateFrames >= a + d && lastFrame >= a + d;
    isFinished = releaseDone || decayedToSilence;
end

function level = heldLevel(n, a, d, sustain, startLevel)
% Envelope level at frame(s) N while the key is held (no release yet).
    level = repmat(sustain, size(n));          % default: the sustain level
    inAttack = n < a;
    level(inAttack) = startLevel + (1 - startLevel) * n(inAttack) / a;   % startLevel -> 1
    inDecay = n >= a & n < a + d;
    level(inDecay) = 1 - (1 - sustain) * (n(inDecay) - a) / d;          % 1 -> sustain
end
