function [b, a] = biquadCoeffs(type, f0, q, fs, gainDb)
%BIQUADCOEFFS Filter coefficients for one "biquad" (second-order) filter section.
%   [b, a] = bpm.dsp.biquadCoeffs(type, f0, q, fs, gainDb) returns 1x3 rows b
%   and a (with a(1) = 1) for use with MATLAB's filter function:
%       y = filter(b, a, x);
%   The formulas are Robert Bristow-Johnson's "Audio EQ Cookbook", the standard
%   reference for audio filters.
%
%   type    what the filter does:
%       "lowpass"   keeps frequencies below f0, cuts those above
%       "highpass"  keeps frequencies above f0, cuts those below
%       "bandpass"  keeps a band around f0 (0 dB at f0)
%       "notch"     removes a narrow band around f0
%       "allpass"   passes everything at full level, but shifts the timing (phase)
%       "peaking"   boosts or cuts by gainDb around f0 (one EQ band)
%       "lowshelf"  boosts or cuts by gainDb below f0
%       "highshelf" boosts or cuts by gainDb above f0
%   f0      the key frequency in Hz, between 0 and fs/2 (both excluded)
%   q       how sharp the filter is: larger = narrower / more resonant.
%           For lowpass and highpass, q = 1/sqrt(2) (0.7071) gives the smoothest
%           response, -3 dB at f0. (In general those two are q at f0, i.e. 20*log10(q) dB.)
%   gainDb  boost (+) or cut (-) in dB; used only by peaking and the shelves.
%
%   For bandpass and notch, q sets the width: the band between the two -3 dB
%   points is f0/q wide (roughly). For peaking, it sets the width between the
%   two points where the boost is half of gainDb. For the shelves, larger q makes
%   the change from one level to the other steeper (with a small bump).
%
%   A biquad computes each output sample from the current input, the two
%   previous inputs and the two previous outputs:
%       y(n) = b(1) x(n) + b(2) x(n-1) + b(3) x(n-2) - a(2) y(n-1) - a(3) y(n-2)
%
%   Example: a smooth low-pass at 1 kHz for 44.1 kHz audio:
%       [b, a] = bpm.dsp.biquadCoeffs("lowpass", 1000, 1/sqrt(2), 44100);

    % An arguments block checks each input before the function runs: "(1,1)"
    % means exactly one value, {mustBe...} lists rules the value must pass, and
    % "= 0" is the default used when gainDb is left out.
    arguments
        type (1,1) string {mustBeMember(type, ["lowpass", "highpass", "bandpass", ...
            "notch", "allpass", "peaking", "lowshelf", "highshelf"])}
        f0 (1,1) double {mustBePositive, mustBeFinite}
        q (1,1) double {mustBePositive, mustBeFinite}
        fs (1,1) double {mustBePositive, mustBeFinite}
        gainDb (1,1) double {mustBeReal, mustBeFinite} = 0
    end
    if f0 >= fs / 2
        error("bpm:dsp:biquadCoeffs:aboveNyquist", ...
            "f0 must be below fs/2 = %g Hz (the highest frequency fs can hold).", fs / 2);
    end

    % Shared intermediate values, named as in the Cookbook.
    w0 = 2 * pi * f0 / fs;      % f0 as an angle (radians per sample)
    cw = cos(w0);
    alpha = sin(w0) / (2 * q);
    A = 10 ^ (gainDb / 40);     % square root of the linear gain (Cookbook's A)
    sA = 2 * sqrt(A) * alpha;   % appears in the shelf formulas

    switch type
        case "lowpass"
            b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2];
            a = [1 + alpha, -2 * cw, 1 - alpha];
        case "highpass"
            b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2];
            a = [1 + alpha, -2 * cw, 1 - alpha];
        case "bandpass"
            b = [alpha, 0, -alpha];
            a = [1 + alpha, -2 * cw, 1 - alpha];
        case "notch"
            b = [1, -2 * cw, 1];
            a = [1 + alpha, -2 * cw, 1 - alpha];
        case "allpass"
            b = [1 - alpha, -2 * cw, 1 + alpha];
            a = [1 + alpha, -2 * cw, 1 - alpha];
        case "peaking"
            b = [1 + alpha * A, -2 * cw, 1 - alpha * A];
            a = [1 + alpha / A, -2 * cw, 1 - alpha / A];
        case "lowshelf"
            b = A * [(A + 1) - (A - 1) * cw + sA, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sA];
            a = [(A + 1) + (A - 1) * cw + sA, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sA];
        case "highshelf"
            b = A * [(A + 1) + (A - 1) * cw + sA, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sA];
            a = [(A + 1) - (A - 1) * cw + sA, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sA];
    end

    % Divide everything by a(1) so that a(1) = 1. Then the difference equation
    % above can be used as written (for example in a hand-written filter loop).
    % MATLAB's filter() would also accept coefficients without this step.
    b = b / a(1);
    a = a / a(1);
end
