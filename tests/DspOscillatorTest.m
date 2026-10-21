classdef DspOscillatorTest < BpmTestCase
    % Tests for bpm.dsp.polyblepOsc.
    %
    % MATLAB features used below:
    %   @() expr      makes a small unnamed function; verifyError calls it and
    %                 checks that it throws the expected error.
    %   "x" + k       + joins text, turning a number k into text first.

    properties (TestParameter)
        fs = {44100, 96000}
        waveform = {"sine", "saw", "square", "triangle"}
        edgy = {"saw", "square", "triangle"}   % the waveforms that need anti-aliasing
    end

    methods (Test)
        function fundamentalIsAtTheRequestedFrequency(testCase, fs, waveform)
            % One second of signal gives FFT bins exactly 1 Hz apart, so a 440 Hz
            % tone must peak in the 440 Hz bin; 1234 Hz checks a less round number.
            for f0 = [440 1234]
                y = bpm.dsp.polyblepOsc(waveform, f0, fs, fs);
                testCase.verifyEqual(DspOscillatorTest.peakFrequency(y, fs), f0, ...
                    "AbsTol", 1e-9, waveform + " at " + f0 + " Hz");
            end
        end

        function antiAliasingReducesAliasing(testCase, fs, edgy)
            % A high note (2500.5 Hz) makes aliasing easy to see. Measured improvement
            % is about 14 dB (saw, square) and 8-10 dB (triangle); require a safe margin.
            minImprovementDb = struct("saw", 8, "square", 8, "triangle", 5);
            f0 = 2500.5;
            smooth = bpm.dsp.polyblepOsc(edgy, f0, fs, fs);
            naive = bpm.dsp.polyblepOsc(edgy, f0, fs, fs, AntiAlias=false);
            improvement = DspOscillatorTest.aliasDb(naive, f0, fs) - DspOscillatorTest.aliasDb(smooth, f0, fs);
            testCase.verifyGreaterThan(improvement, minImprovementDb.(edgy), ...
                sprintf("%s: aliasing only %.1f dB lower than naive", edgy, improvement));
        end

        function antiAliasingKeepsTheWaveformShape(testCase, fs, edgy)
            % The correction only touches samples next to a jump or corner, so most
            % samples equal the naive waveform exactly, and the rest stay close.
            f0 = 440;
            smooth = bpm.dsp.polyblepOsc(edgy, f0, fs, fs);
            naive = bpm.dsp.polyblepOsc(edgy, f0, fs, fs, AntiAlias=false);
            changed = abs(smooth - naive) > 1e-12;
            jumpsPerCycle = 1 + (edgy ~= "saw");                 % square/triangle: 2
            testCase.verifyLessThanOrEqual(nnz(changed), 2 * jumpsPerCycle * (f0 + 1), ...
                "At most 2 samples per jump or corner are changed.");
        end

        function staysWithinPlusMinusOne(testCase, fs, waveform)
            y = bpm.dsp.polyblepOsc(waveform, 3001.7, fs, fs);
            testCase.verifyLessThanOrEqual(max(abs(y)), 1 + 1e-12);
        end

        function hasNoDcOffset(testCase, fs, waveform)
            y = bpm.dsp.polyblepOsc(waveform, 440, fs, fs);    % exactly 440 cycles
            testCase.verifyLessThan(abs(mean(y)), 1e-3);
        end

        function naiveWaveformsHaveTheTextbookShapes(testCase)
            fs = 1000; f = 10; t = mod((0:199)' * f / fs, 1);
            sq = ones(200, 1); sq(t >= 0.5) = -1;
            expected = struct("sine", sin(2 * pi * t), "saw", 2 * t - 1, "square", sq, ...
                "triangle", 1 - 4 * abs(t - 0.5));
            for wf = ["sine", "saw", "square", "triangle"]
                y = bpm.dsp.polyblepOsc(wf, f, fs, 200, AntiAlias=false);
                testCase.verifyEqual(y, expected.(wf), "AbsTol", 1e-12, wf);
            end
        end

        function blocksJoinUpSeamlessly(testCase, fs, waveform)
            f0 = 523.25;
            [y1, ph] = bpm.dsp.polyblepOsc(waveform, f0, fs, 1000, 0.25);
            [y2, ph] = bpm.dsp.polyblepOsc(waveform, f0, fs, 777, ph);
            [y3, phEnd] = bpm.dsp.polyblepOsc(waveform, f0, fs, 1, ph);
            [whole, phWhole] = bpm.dsp.polyblepOsc(waveform, f0, fs, 1778, 0.25);
            testCase.verifyEqual([y1; y2; y3], whole, "AbsTol", 1e-9);
            testCase.verifyEqual(phEnd, phWhole, "AbsTol", 1e-9);
        end

        function returnedPhaseIsWhereTheNextBlockStarts(testCase)
            [~, ph] = bpm.dsp.polyblepOsc("sine", 441, 44100, 25);   % 25 frames = 0.25 cycle
            testCase.verifyEqual(ph, 0.25, "AbsTol", 1e-12);
            [~, ph] = bpm.dsp.polyblepOsc("sine", 441, 44100, 100, 0.5);  % one full cycle
            testCase.verifyEqual(ph, 0.5, "AbsTol", 1e-12);
            testCase.verifyGreaterThanOrEqual(ph, 0);
            testCase.verifyLessThan(ph, 1);
        end

        function startingPhaseIsRespected(testCase)
            y = bpm.dsp.polyblepOsc("sine", 100, 44100, 1, 0.25);
            testCase.verifyEqual(y, 1, "AbsTol", 1e-12, "A quarter cycle into a sine is its peak.");
        end

        function frequencyCanChangeEverySample(testCase, fs)
            n = 2000;
            constant = bpm.dsp.polyblepOsc("saw", 300, fs, n);
            perSample = bpm.dsp.polyblepOsc("saw", repmat(300, n, 1), fs, n);
            testCase.verifyEqual(perSample, constant, "AbsTol", 1e-9);
            % A pitch jump halfway: the second half continues from where the first left off.
            f = [repmat(300, n / 2, 1); repmat(600, n / 2, 1)];
            [y, ph] = bpm.dsp.polyblepOsc("saw", f, fs, n);
            [a, phA] = bpm.dsp.polyblepOsc("saw", 300, fs, n / 2);
            [b, phB] = bpm.dsp.polyblepOsc("saw", 600, fs, n / 2, phA);
            testCase.verifyEqual(y, [a; b], "AbsTol", 1e-9);
            testCase.verifyEqual(ph, phB, "AbsTol", 1e-9);
        end

        function zeroFrequencyHoldsStill(testCase)
            y = bpm.dsp.polyblepOsc("sine", 0, 44100, 50, 0.25);
            testCase.verifyEqual(y, ones(50, 1), "AbsTol", 1e-12);
        end

        function zeroFramesGivesAnEmptyColumn(testCase)
            [y, ph] = bpm.dsp.polyblepOsc("saw", 440, 44100, 0, 0.3);
            testCase.verifySize(y, [0 1]);
            testCase.verifyEqual(ph, 0.3);
        end

        function rejectsBadInputs(testCase)
            testCase.verifyError(@() bpm.dsp.polyblepOsc("noise", 440, 44100, 10), "MATLAB:validators:mustBeMember");
            testCase.verifyError(@() bpm.dsp.polyblepOsc("saw", 22050, 44100, 10), "bpm:dsp:polyblepOsc:aboveNyquist");
            testCase.verifyError(@() bpm.dsp.polyblepOsc("saw", [440; 22050], 44100, 2), "bpm:dsp:polyblepOsc:aboveNyquist");
            testCase.verifyError(@() bpm.dsp.polyblepOsc("saw", -1, 44100, 10), "MATLAB:validators:mustBeNonnegative");
            testCase.verifyError(@() bpm.dsp.polyblepOsc("saw", [440; 441], 44100, 10), "bpm:dsp:polyblepOsc:freqSize");
            testCase.verifyError(@() bpm.dsp.polyblepOsc("saw", 440, 44100, 10, 1), "MATLAB:validators:mustBeInRange");
            testCase.verifyError(@() bpm.dsp.polyblepOsc("saw", 440, 44100, 2.5), "MATLAB:validators:mustBeInteger");
        end
    end

    methods (Static)
        function f = peakFrequency(y, fs)
            % Frequency (Hz) of the strongest FFT bin, ignoring 0 Hz.
            n = numel(y);
            Y = abs(fft(y));
            Y(1) = 0;
            [~, k] = max(Y(1:floor(n / 2)));
            f = (k - 1) * fs / n;
        end

        function d = aliasDb(y, f0, fs)
            % Energy that is NOT at a true harmonic of f0, relative to all energy, in
            % dB. A true harmonic is a whole multiple of f0 below fs/2; aliasing puts
            % energy everywhere else. A Blackman-Harris window keeps each harmonic's
            % energy within a few FFT bins, so we skip +-3 bins around each one.
            n = numel(y);
            k = (0:n - 1)';
            w = 0.35875 - 0.48829 * cos(2 * pi * k / (n - 1)) ...
                + 0.14128 * cos(4 * pi * k / (n - 1)) - 0.01168 * cos(6 * pi * k / (n - 1));
            P = abs(fft(y .* w)) .^ 2;
            P = P(1:floor(n / 2));
            f = (0:numel(P) - 1)' * fs / n;
            nearHarmonic = f < 20;
            for h = f0 * (1:floor((fs / 2) / f0))
                nearHarmonic = nearHarmonic | abs(f - h) <= 3 * fs / n;
            end
            d = 10 * log10(sum(P(~nearHarmonic)) / sum(P));
        end
    end
end
