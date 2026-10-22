function [y, phase] = polyblepOsc(waveform, freqHz, fs, numFrames, phase, options)
%POLYBLEPOSC Basic synth waveforms (sine, saw, square, triangle) with low aliasing.
%   [y, phase] = bpm.dsp.polyblepOsc(waveform, freqHz, fs, numFrames, phase)
%   returns numFrames samples (a column) of the waveform at frequency freqHz,
%   with peaks at -1 and +1. waveform is "sine", "saw", "square" or "triangle".
%
%   PHASE is where in the cycle to start: 0 = start of a cycle, 0.5 = halfway.
%   It is optional (default 0) and must be at least 0 and below 1.
%   The second output is where the NEXT block should start. Passing it back in
%   makes consecutive blocks join up seamlessly (PLAN.md decision D5):
%       [y1, ph] = bpm.dsp.polyblepOsc("saw", 440, 44100, 1024, 0);
%       [y2, ph] = bpm.dsp.polyblepOsc("saw", 440, 44100, 1024, ph);   % continues y1
%
%   freqHz can be one number, or a numFrames x 1 column giving a frequency for
%   every sample (for vibrato or pitch slides). It must be at least 0 and below
%   fs/2 (the Nyquist frequency, the highest frequency a sample rate can hold).
%
%   If the frequency can change from one block to the next, also pass the
%   frequency the PREVIOUS block ended with, so a jump right at the start of
%   this block is smoothed correctly:
%       [y2, ph] = bpm.dsp.polyblepOsc("saw", 660, 44100, 1024, ph, PrevFreqHz=440);
%   (Without it, the first sample assumes the frequency didn't change.)
%
%   Why "PolyBLEP": a saw or square wave JUMPS instantly, and an instant jump
%   contains frequencies far above fs/2. Sampling folds those back down as
%   "aliasing", which sounds like harsh, out-of-tune whistles on high notes.
%   PolyBLEP ("polynomial band-limited step") replaces the sample on each side
%   of a jump with a smooth polynomial curve, which removes most of the
%   aliasing at almost no cost. The triangle has CORNERS instead of jumps, and
%   gets the matching corner fix, PolyBLAMP ("band-limited ramp").
%
%   bpm.dsp.polyblepOsc(..., AntiAlias=false) gives the plain ("naive")
%   waveforms, useful for comparison and teaching.

    % An arguments block checks each input before the function runs:
    %   (1,1) = exactly one value; (:,1) = a column of any length (one number
    %   counts too); {mustBe...} = rules the value must pass; "= 0" = the default
    %   used when the input is left out; "exclude-upper" = the range excludes 1.
    %   options.AntiAlias declares an optional name-value input: AntiAlias=false.
    %   PrevFreqHz defaults to [] (empty), meaning "not given".
    arguments
        waveform (1,1) string {mustBeMember(waveform, ["sine", "saw", "square", "triangle"])}
        freqHz (:,1) double {mustBeReal, mustBeFinite, mustBeNonnegative}
        fs (1,1) double {mustBePositive, mustBeFinite}
        numFrames (1,1) double {mustBeInteger, mustBeNonnegative}
        phase (1,1) double {mustBeInRange(phase, 0, 1, "exclude-upper")} = 0
        options.AntiAlias (1,1) logical = true
        options.PrevFreqHz double {mustBeScalarOrEmpty, mustBeReal, mustBeFinite, mustBeNonnegative} = []
    end
    if ~(isscalar(freqHz) || numel(freqHz) == numFrames)
        error("bpm:dsp:polyblepOsc:freqSize", ...
            "freqHz must be one number or a %d x 1 column (one per frame), not %d values.", ...
            numFrames, numel(freqHz));
    end
    % || means "or", checking the right side only if the left side is false.
    if any(freqHz >= fs / 2) || any(options.PrevFreqHz >= fs / 2)
        error("bpm:dsp:polyblepOsc:aboveNyquist", ...
            "freqHz and PrevFreqHz must be below fs/2 = %g Hz (the highest frequency fs can hold).", fs / 2);
    end

    % dt = how far through a cycle each sample moves (cycles per sample).
    % "dt .* ones(numFrames, 1)" turns a single value into one value per frame
    % (.* multiplies element by element).
    dt = (freqHz / fs) .* ones(numFrames, 1);

    % t = position within the cycle (0 to just below 1) at every frame, and
    % mod(..., 1) wraps it back to 0 at each new cycle. steps has one extra
    % entry at the end: the position just after the last frame, which is where
    % the next block must start.
    if isscalar(freqHz)
        % Fixed frequency: frame k is k steps of dt from the start. Multiplying
        % (rather than adding dt up one frame at a time) avoids building up
        % rounding error, so rendering in small or large blocks gives the same
        % result to about 1e-10 even for long notes.
        steps = phase + (0:numFrames)' * (freqHz / fs);
    else
        % Changing frequency: add up each frame's step (cumsum = running total).
        % Rounding builds up slowly here: about 1e-8 over 10 seconds.
        steps = phase + [0; cumsum(dt)];
    end
    t = reshape(mod(steps(1:numFrames), 1), numFrames, 1);   % always a column
    phase = mod(steps(end), 1);

    % A jump (or corner) between frame k-1 and frame k is crossed by the step
    % dt(k-1). The correction on frame k, just AFTER the jump, needs that step,
    % so make dtPrev = dt shifted down by one frame. Frame 1's previous step
    % belongs to the previous block: PrevFreqHz if the caller gave it.
    if numFrames > 0
        if isempty(options.PrevFreqHz)
            firstPrev = dt(1);                 % assume no change at the block start
        else
            firstPrev = options.PrevFreqHz / fs;
        end
        dtPrev = [firstPrev; dt(1:end - 1)];
    else
        dtPrev = dt;                           % nothing to render
    end

    % Position relative to the second edge at t = 0.5 (the square's fall, the
    % triangle's peak), shifted so that edge sits at 0 like the first one.
    % Subtracting 0.5 from t >= 0.5 is exact. Adding 0.5 to t < 0.5 can round up
    % to exactly 1, which the corrections below rightly treat as "just before"
    % the edge. (mod(t + 0.5, 1) would wrap that 1 to 0, "just after", and put
    % a spike of 2 in the square wave.)
    t2 = t + 0.5;
    secondHalf = t >= 0.5;
    t2(secondHalf) = t(secondHalf) - 0.5;

    switch waveform
        case "sine"
            y = sin(2 * pi * t);           % already smooth: no correction needed
        case "saw"
            y = 2 * t - 1;                 % ramps -1 -> +1, then drops back
            if options.AntiAlias
                % kink(...): see the note on pitch changes below the switch.
                y = y - blep(t, dt, dtPrev) + kink(2, dt, dtPrev);
            end
        case "square"
            y = ones(numFrames, 1);        % +1 for the first half of the cycle,
            y(secondHalf) = -1;            % -1 for the second half
            if options.AntiAlias
                y = y + blep(t, dt, dtPrev) - blep(t2, dt, dtPrev);
            end
        case "triangle"
            y = 1 - 4 * abs(t - 0.5);      % -1 at the cycle start, +1 halfway
            if options.AntiAlias
                % The slope is +4 per cycle on the rising half and -4 on the
                % falling half, so each corner changes it by 8 per cycle. blamp
                % returns the correction for a change of 2 per cycle (its curve
                % times the step that crossed the corner), so multiply by 8/2 = 4.
                rising = 1 - 2 * secondHalf;   % +1 on the rising half, -1 falling
                y = y + 4 * (blamp(t, dt, dtPrev) - blamp(t2, dt, dtPrev)) ...
                      + rising .* kink(4, dt, dtPrev);
            end
    end
    % Note on pitch changes: the saw and triangle are made of straight lines whose
    % slope is (slope per cycle) x (step per sample). So when the step changes at a
    % frame, the waveform also bends a little exactly there: one more, very small
    % corner. kink() smooths it the same way blamp smooths the triangle's corners.
    % (With a fixed frequency it is always 0.) For the triangle it also keeps the
    % output from depending on rounding when a corner lands right on that frame.
end

function r = kink(slopePerCycle, dt, dtPrev)
% Correction for the bend a pitch change makes at a frame: the slope changes by
% slopePerCycle x (dt - dtPrev) per sample, exactly AT the frame (x = 0). For a
% corner at x = 0, the PolyBLAMP correction is (change of slope) / 6 on that
% frame only (the blamp curve at x = 0 is 1/3, times change / 2).
    r = slopePerCycle * (dt - dtPrev) / 6;
end

% The two functions below are "local functions": helpers that only this file
% can call. They work on whole columns at once (.* ./ .^ act element by element).

function r = blep(t, dt, dtPrev)
% PolyBLEP correction for an upward jump of size 2 at t = 0 (the start of a
% cycle). It is non-zero only within one sample of the jump. x measures the
% distance to the jump in samples: 0..1 just after it, -1..0 just before it.
% ("t(after)" picks out only the elements where the mask "after" is true.)
    r = zeros(size(t));
    after = t < dtPrev;                    % the sample just after the jump
    x = t(after) ./ dtPrev(after);
    r(after) = 2 * x - x .^ 2 - 1;
    before = t > 1 - dt;                   % the sample just before the jump
    x = (t(before) - 1) ./ dt(before);
    r(before) = x .^ 2 + 2 * x + 1;
end

function r = blamp(t, dt, dtPrev)
% PolyBLAMP correction for a corner at t = 0: the running total (integral) of
% the PolyBLEP correction above, which is why it is a cubic instead of a square.
% The cubic is the correction for a change of slope of 2 per SAMPLE. Multiplying
% by the step that crossed the corner (dt before it, dtPrev after it) makes it
% the correction for a change of 2 per CYCLE; callers multiply by (change / 2).
    r = zeros(size(t));
    after = t < dtPrev;
    x = t(after) ./ dtPrev(after);
    r(after) = dtPrev(after) .* (1 - x) .^ 3 / 3;
    before = t > 1 - dt;
    x = (t(before) - 1) ./ dt(before);
    r(before) = dt(before) .* (x + 1) .^ 3 / 3;
end
