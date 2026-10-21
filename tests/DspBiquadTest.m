classdef DspBiquadTest < BpmTestCase
    % Tests for bpm.dsp.biquadCoeffs. Each response is MEASURED: run an impulse
    % through filter() and take the Fourier transform of what comes out (the
    % "frequency response" says how much each frequency is boosted or cut).
    %
    % MATLAB features used below:
    %   @() expr   makes a small unnamed function; verifyError calls it.
    %   {:}        "args{:}" spreads a cell array out as separate inputs.

    properties (TestParameter)
        fs = {44100, 96000}
    end

    methods (Test)
        function lowpassIsMinus3dBAtCutoff(testCase, fs)
            [b, a] = bpm.dsp.biquadCoeffs("lowpass", 1000, 1 / sqrt(2), fs);
            testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 1000, fs), -3.01, "AbsTol", 0.5);
            testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 20, fs), 0, "AbsTol", 0.01, "Low notes pass.");
            testCase.verifyLessThan(DspBiquadTest.gainDb(b, a, 2000, fs), -11, "An octave up is cut ~12 dB.");
            testCase.verifyLessThan(DspBiquadTest.gainDb(b, a, 4000, fs), -20, "Two octaves up, ~24 dB.");
        end

        function lowpassAndHighpassGainAtCutoffEqualsQ(testCase, fs)
            for q = [0.5 1 2 5]
                for type = ["lowpass", "highpass"]
                    [b, a] = bpm.dsp.biquadCoeffs(type, 2000, q, fs);
                    testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 2000, fs), 20 * log10(q), ...
                        "AbsTol", 0.05, type + " q=" + q);
                end
            end
        end

        function highpassCutsLowsAndKeepsHighs(testCase, fs)
            [b, a] = bpm.dsp.biquadCoeffs("highpass", 500, 1 / sqrt(2), fs);
            testCase.verifyLessThan(DspBiquadTest.gainDb(b, a, 50, fs), -35);
            testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 10000, fs), 0, "AbsTol", 0.05);
        end

        function bandpassPeaksAtZeroDbAtCenter(testCase, fs)
            [b, a] = bpm.dsp.biquadCoeffs("bandpass", 1000, 4, fs);
            testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 1000, fs), 0, "AbsTol", 0.01);
            testCase.verifyLessThan(DspBiquadTest.gainDb(b, a, 100, fs), -20);
            testCase.verifyLessThan(DspBiquadTest.gainDb(b, a, 10000, fs), -20);
        end

        function notchRemovesTheCenterFrequency(testCase, fs)
            [b, a] = bpm.dsp.biquadCoeffs("notch", 1000, 2, fs);
            testCase.verifyLessThan(DspBiquadTest.gainDb(b, a, 1000, fs), -60);
            testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 100, fs), 0, "AbsTol", 0.1);
        end

        function allpassKeepsEveryLevel(testCase, fs)
            [b, a] = bpm.dsp.biquadCoeffs("allpass", 1000, 0.7, fs);
            for f = [50 500 1000 5000 15000]
                testCase.verifyEqual(DspBiquadTest.gainDb(b, a, f, fs), 0, "AbsTol", 0.01, "at " + f + " Hz");
            end
        end

        function peakingBoostsOrCutsByGainAtCenter(testCase, fs)
            for g = [-12 -6 6 12]
                [b, a] = bpm.dsp.biquadCoeffs("peaking", 3000, 1.5, fs, g);
                testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 3000, fs), g, "AbsTol", 0.01, "gain " + g);
                testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 30, fs), 0, "AbsTol", 0.1, "far below");
            end
        end

        function shelvesBoostOrCutOneEnd(testCase, fs)
            for g = [-9 6]
                [b, a] = bpm.dsp.biquadCoeffs("lowshelf", 300, 0.7, fs, g);
                testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 10, fs), g, "AbsTol", 0.05, "low shelf, lows");
                testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 15000, fs), 0, "AbsTol", 0.05, "low shelf, highs");
                [b, a] = bpm.dsp.biquadCoeffs("highshelf", 5000, 0.7, fs, g);
                testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 20000, fs), g, "AbsTol", 0.3, "high shelf, highs");
                testCase.verifyEqual(DspBiquadTest.gainDb(b, a, 50, fs), 0, "AbsTol", 0.05, "high shelf, lows");
            end
        end

        function zeroGainPeakAndShelvesChangeNothing(testCase, fs)
            for type = ["peaking", "lowshelf", "highshelf"]
                [b, a] = bpm.dsp.biquadCoeffs(type, 1000, 1, fs, 0);
                testCase.verifyEqual(b, a, "AbsTol", 1e-12, type + " with 0 dB is a plain wire");
            end
        end

        function coefficientsAreNormalizedAndStable(testCase, fs)
            types = ["lowpass", "highpass", "bandpass", "notch", "allpass", "peaking", "lowshelf", "highshelf"];
            for type = types
                [b, a] = bpm.dsp.biquadCoeffs(type, 1234, 0.9, fs, 4);
                testCase.verifySize(b, [1 3]);
                testCase.verifySize(a, [1 3]);
                testCase.verifyEqual(a(1), 1, type);
                % A filter is stable (its output dies away instead of blowing up)
                % when the roots of a lie inside the unit circle.
                testCase.verifyLessThan(abs(roots(a)), 1, type + " must be stable");
            end
        end

        function cutoffScalesWithSampleRate(testCase)
            % The same cutoff in Hz must behave the same at any sample rate.
            g = zeros(1, 2);
            rates = [44100 96000];
            for k = 1:2
                [b, a] = bpm.dsp.biquadCoeffs("lowpass", 5000, 1 / sqrt(2), rates(k));
                g(k) = DspBiquadTest.gainDb(b, a, 5000, rates(k));
            end
            testCase.verifyEqual(g(1), g(2), "AbsTol", 0.01);
        end

        function rejectsBadInputs(testCase)
            testCase.verifyError(@() bpm.dsp.biquadCoeffs("bandstop", 1000, 1, 44100), "MATLAB:validators:mustBeMember");
            testCase.verifyError(@() bpm.dsp.biquadCoeffs("lowpass", 22050, 1, 44100), "bpm:dsp:biquadCoeffs:aboveNyquist");
            testCase.verifyError(@() bpm.dsp.biquadCoeffs("lowpass", 0, 1, 44100), "MATLAB:validators:mustBePositive");
            testCase.verifyError(@() bpm.dsp.biquadCoeffs("lowpass", 1000, 0, 44100), "MATLAB:validators:mustBePositive");
            testCase.verifyError(@() bpm.dsp.biquadCoeffs("peaking", 1000, 1, 44100, Inf), "MATLAB:validators:mustBeFinite");
        end
    end

    methods (Static)
        function g = gainDb(b, a, f, fs)
            % Measured gain (dB) of the filter at frequency f: filter an impulse,
            % then evaluate the Fourier transform of the result at f.
            n = 2 ^ 16;
            h = filter(b, a, [1; zeros(n - 1, 1)]);
            H = sum(h .* exp(-1j * 2 * pi * f / fs * (0:n - 1)'));
            g = 20 * log10(abs(H));
        end
    end
end
