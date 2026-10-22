function [gL, gR] = panGains(pan)
%PANGAINS Left and right gains for a pan position (constant-power pan law).
%   [gL, gR] = bpm.dsp.panGains(pan) works element by element on any array of
%   pan positions: -1 = full left, 0 = center, +1 = full right.
%
%   "Constant power" means gL^2 + gR^2 = 1 at every position, so a sound keeps
%   the same perceived loudness as it moves across the stereo field. (Simply
%   using gL = 1 - x and gR = x, with x = (pan + 1)/2 going from 0 to 1, would
%   make it dip in the middle: at center gL^2 + gR^2 = 0.5, i.e. 3 dB quieter.)
%   The trick is
%   to sweep an angle from 0 to 90 degrees and use cosine and sine, because
%   cos(theta)^2 + sin(theta)^2 = 1 for every angle:
%       theta = (pan + 1) * pi/4      % pan -1 -> 0,  0 -> pi/4,  +1 -> pi/2
%       gL = cos(theta),  gR = sin(theta)
%   At center both gains are cos(pi/4) = 0.7071 (that is -3 dB on each side).
%
%   Example:
%       [gL, gR] = bpm.dsp.panGains([-1 0 1])   % gL = [1 0.7071 0], gR = [0 0.7071 1]

    % An arguments block checks the input before the function runs: any array
    % of doubles, every element between -1 and 1.
    arguments
        pan double {mustBeInRange(pan, -1, 1)}
    end
    % cos, sin and the arithmetic below all work element by element, so a whole
    % array of pan positions is handled at once.
    theta = (pan + 1) * pi / 4;
    gL = cos(theta);
    gR = sin(theta);
    % At full right, cos(pi/2) is 6e-17 rather than exactly 0 (rounding), so snap
    % it: full right really means silent on the left. (At full left, sin(0) is
    % already exactly 0.) gL(pan == 1) = 0 sets only the elements where pan is 1.
    gL(pan == 1) = 0;
end
