function [y, phase] = polyblepOsc(waveform, freqHz, fs, numFrames, phase, options)
%POLYBLEPOSC Basic synth waveforms (sine, saw, square, triangle) with low aliasing.
%   [y, phase] = bpm.dsp.polyblepOsc(waveform, freqHz, fs, numFrames, phase)
%   returns numFrames samples (a column) of the waveform at frequency freqHz,
%   with peaks at -1 and +1. waveform is "sine", "saw", "square" or "triangle".
%
%   PHASE is where in the cycle to start: 0 = start of a cycle, 0.5 = halfway.
%   The second output is where the NEXT block should start. Passing it back in
%   makes consecutive blocks join up seamlessly (PLAN.md decision D5):
%       [y1, ph] = bpm.dsp.polyblepOsc("saw", 440, 44100, 1024, 0);
%       [y2, ph] = bpm.dsp.polyblepOsc("saw", 440, 44100, 1024, ph);   % continues y1
%
%   freqHz can be one number, or a numFrames x 1 column giving a frequency for
%   every sample (for vibrato or pitch slides). It must be at least 0 and below
%   fs/2 (the Nyquist frequency, the highest frequency a sample rate can hold).
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

    arguments
        waveform (1,1) string {mustBeMember(waveform, ["sine", "saw", "square", "triangle"])}
        freqHz (:,1) double {mustBeReal, mustBeFinite, mustBeNonnegative}
        fs (1,1) double {mustBePositive, mustBeFinite}
        numFrames (1,1) double {mustBeInteger, mustBeNonnegative}
        phase (1,1) double {mustBeInRange(phase, 0, 1, "exclude-upper")} = 0
        options.AntiAlias (1,1) logical = true
    end
    if ~(isscalar(freqHz) || numel(freqHz) == numFrames)
        error("bpm:dsp:polyblepOsc:freqSize", ...
            "freqHz must be one number or a %d x 1 column (one per frame), not %d values.", ...
            numFrames, numel(freqHz));
    end
    if any(freqHz >= fs / 2)
        error("bpm:dsp:polyblepOsc:aboveNyquist", ...
            "freqHz must be below fs/2 = %g Hz (the highest frequency fs can hold).", fs / 2);
    end

    % dt = how far through a cycle each sample moves (cycles per sample).
    % "dt .* ones(numFrames, 1)" turns a single value into one value per frame.
    dt = (freqHz / fs) .* ones(numFrames, 1);

    % t = position within the cycle (0 to just below 1) at every frame.
    % cumsum adds up dt as we go (a running total); mod(..., 1) wraps back to 0
    % at each new cycle. steps has one extra entry at the end: the position just
    % after the last frame, which is where the next block must start.
    steps = phase + [0; cumsum(dt)];
    t = reshape(mod(steps(1:numFrames), 1), numFrames, 1);   % always a column
    phase = mod(steps(end), 1);

    switch waveform
        case "sine"
            y = sin(2 * pi * t);           % already smooth: no correction needed
        case "saw"
            y = 2 * t - 1;                 % ramps -1 -> +1, then drops back
            if options.AntiAlias
                y = y - blep(t, dt);
            end
        case "square"
            y = ones(numFrames, 1);        % +1 for the first half of the cycle,
            y(t >= 0.5) = -1;              % -1 for the second half
            if options.AntiAlias
                y = y + blep(t, dt) - blep(mod(t + 0.5, 1), dt);
            end
        case "triangle"
            y = 1 - 4 * abs(t - 0.5);      % -1 at the cycle start, +1 halfway
            if options.AntiAlias
                % Corner size = change of slope. The slope is +-4 per cycle,
                % i.e. +-4*dt per sample, so each corner changes it by 8*dt.
                y = y + 4 * dt .* (blamp(t, dt) - blamp(mod(t + 0.5, 1), dt));
            end
    end
end

function r = blep(t, dt)
% PolyBLEP correction for an upward jump of size 2 at t = 0 (the start of a
% cycle). It is non-zero only within one sample of the jump. x measures the
% distance to the jump in samples: 0..1 just after it, -1..0 just before it.
    r = zeros(size(t));
    after = t < dt;                        % the sample just after the jump
    x = t(after) ./ dt(after);
    r(after) = 2 * x - x .^ 2 - 1;
    before = t > 1 - dt;                   % the sample just before the jump
    x = (t(before) - 1) ./ dt(before);
    r(before) = x .^ 2 + 2 * x + 1;
end

function r = blamp(t, dt)
% PolyBLAMP correction for a corner at t = 0: the running total (integral) of
% the PolyBLEP correction above, which is why it is a cubic instead of a square.
% Scaled for a change of slope of 2 per sample; callers multiply by (change / 2).
    r = zeros(size(t));
    after = t < dt;
    x = t(after) ./ dt(after);
    r(after) = (1 - x) .^ 3 / 3;
    before = t > 1 - dt;
    x = (t(before) - 1) ./ dt(before);
    r(before) = (x + 1) .^ 3 / 3;
end
