function g = dbToGain(dB)
%DBTOGAIN Convert decibels to a linear gain (the number you multiply a signal by).
%   g = bpm.dsp.dbToGain(dB) works element by element on any array.
%
%   Decibels measure ratios on a log scale. For signal levels (amplitudes):
%       g = 10^(dB/20)
%   so  0 dB -> 1 (unchanged),  -6 dB -> about 0.5,  +6 dB -> about 2,
%   and -Inf dB -> 0 (silence).
%
%   Example:
%       bpm.dsp.dbToGain([0 -6 -Inf])   % -> [1 0.5012 0]

    arguments
        dB double {mustBeReal, mustBeNonNan}
    end
    % .^ raises each element to a power on its own ("element-wise"), so this
    % works for a single number or a whole array of dB values at once.
    g = 10 .^ (dB / 20);
end
