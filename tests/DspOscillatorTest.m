classdef DspOscillatorTest < BpmTestCase
    % Tests for bpm.dsp.polyblepOsc.
    %
    % MATLAB features used below:
    %   properties (TestParameter)  values a test runs with: a test that takes fs
    %                               runs once per rate; a test that takes fs AND
    %                               waveform runs for every combination (2 x 4 = 8).
    %   @() expr      makes a small unnamed function; verifyError calls it and
    %                 checks that it throws the expected error.
    %   "x" + k       + joins text, turning a number k into text first.
    %   s.(name)      "dynamic field": reads the field whose name is in variable name.
    %   [~, x] = f()  ~ throws away an output we don't need (here the first one).
    %   [a, b] = c{k, :}   hands the cells of row k of cell array c out to
    %                 several variables at once.
    %   f = @(n1, n2) ...  an unnamed function with inputs n1 and n2.
    %   methods (Static)  helper functions that belong to the test class; call
    %                 them as DspOscillatorTest.peakFrequency(...).

    properties (TestParameter)
        fs = {44100, 96000}
        waveform = {"sine", "saw", "square", "triangle"}
        edgy = {"saw", "square", "triangle"}   % the waveforms that need anti-aliasing
        startPhase = {0, 0.25, 0.5, 0.75}
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
            % over the naive waveform: saw 14.6 / 16.2 dB, square 13.7 / 17.0 dB,
            % triangle 10.6 / 13.4 dB (at 44.1 / 96 kHz). Require a safe margin.
            minImprovementDb = struct("saw", 10, "square", 10, "triangle", 8);
            f0 = 2500.5;
            smooth = bpm.dsp.polyblepOsc(edgy, f0, fs, fs);
            naive = bpm.dsp.polyblepOsc(edgy, f0, fs, fs, AntiAlias=false);
            improvement = DspOscillatorTest.aliasDb(naive, f0, fs) - DspOscillatorTest.aliasDb(smooth, f0, fs);
            testCase.verifyGreaterThan(improvement, minImprovementDb.(edgy), ...
                sprintf("%s: aliasing only %.1f dB lower than naive", edgy, improvement));
        end

        function aliasMeasureHasALowNoiseFloor(testCase, fs)
            % The measurement itself must not invent aliasing: a pure sine has none.
            t = (0:fs - 1)' / fs;
            testCase.verifyLessThan(DspOscillatorTest.aliasDb(sin(2 * pi * 2500.5 * t), 2500.5, fs), -80);
        end

        function sawJumpSamplesMatchPolyBlep(testCase, fs)
            % Exact values. dt = 0.1 (fs/10) and phase 0.05 put the samples either
            % side of the jump exactly half a sample away from it (x = -0.5, +0.5):
            % before it 2(0.95) - 1 - 0.25 = 0.65, after it 2(0.05) - 1 + 0.25 = -0.65.
            y = bpm.dsp.polyblepOsc("saw", fs / 10, fs, 12, 0.05);
            testCase.verifyEqual(y([1 10 11]), [-0.65; 0.65; -0.65], "AbsTol", 1e-12);
            testCase.verifyEqual(y(2:9), 2 * (0.15:0.1:0.85)' - 1, "AbsTol", 1e-12, "Away from the jump: naive.");
        end

        function triangleCornerSamplesMatchPolyBlamp(testCase, fs)
            % Exact values. dt = 1/8 and phase 1/16 put each corner exactly half a
            % sample from its neighbours, where the PolyBLAMP correction is
            % 4*dt*(0.5^3)/3 = 1/48 (towards the inside of the corner).
            e = 1 / 48;
            y = bpm.dsp.polyblepOsc("triangle", fs / 8, fs, 8, 1 / 16);
            testCase.verifyEqual(y, [-0.75 + e; -0.25; 0.25; 0.75 - e; 0.75 - e; 0.25; -0.25; -0.75 + e], ...
                "AbsTol", 1e-12);
        end

        function squareSampleOnTheJumpIsHalfway(testCase, fs)
            % dt = 1/8 makes sample 5 land exactly on the falling edge (t = 0.5):
            % the corrected value is the midpoint of the jump, 0, and never 2.
            y = bpm.dsp.polyblepOsc("square", fs / 8, fs, 400);
            testCase.verifyEqual(y(5), 0, "AbsTol", 1e-12);
            testCase.verifyLessThanOrEqual(max(abs(y)), 1 + 1e-12);
            testCase.verifyEqual(bpm.dsp.polyblepOsc("square", 440, fs, 1, 0.5, AntiAlias=false), -1, ...
                "The naive square is -1 from exactly halfway.");
        end

        function antiAliasingOnlyTouchesSamplesNextToJumps(testCase, fs, edgy)
            % The correction only changes the sample on each side of a jump or
            % corner. Next to a jump it moves the sample by up to 1 (halfway across
            % the jump); next to a corner only slightly.
            f0 = 440;
            smooth = bpm.dsp.polyblepOsc(edgy, f0, fs, fs);
            naive = bpm.dsp.polyblepOsc(edgy, f0, fs, fs, AntiAlias=false);
            changed = abs(smooth - naive) > 1e-12;
            jumpsPerCycle = 1 + (edgy ~= "saw");                 % square/triangle: 2
            testCase.verifyLessThanOrEqual(nnz(changed), 2 * jumpsPerCycle * (f0 + 1), ...
                "At most 2 samples per jump or corner are changed.");
            testCase.verifyLessThanOrEqual(max(abs(smooth - naive)), 1 + 1e-12);
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

        function blockSizeDoesNotMatterForLongNotes(testCase, fs)
            % Ten seconds of a 440 Hz saw rendered in 64-frame blocks and in
            % 1024-frame blocks must agree (block-based instruments rely on this).
            n = 10 * fs;
            small = DspOscillatorTest.renderInBlocks("saw", 440, fs, n, 64);
            large = DspOscillatorTest.renderInBlocks("saw", 440, fs, n, 1024);
            testCase.verifyEqual(small, large, "AbsTol", 1e-9);
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

        function correctionsUseTheStepThatCrossedTheJump(testCase)
            % At fs = 1000, f = 100 Hz is a step of 0.1 cycles per sample, and 300 Hz
            % a step of 0.3. A jump or corner between frames k and k+1 is crossed by
            % frame k's step, and BOTH neighbours' corrections must use that step,
            % even when the frequency changes right there. Exact expected values:
            fs = 1000;
            f = @(n100, n300) [repmat(100, n100, 1); repmat(300, n300, 1)];
            cases = {
                % waveform  frequencies  phase  frames  expected values
                "saw",      f(10, 5),    0.05,  10:11,  [0.65; -0.65]        % crossed by 0.1
                "saw",      f(11, 4),    0.05,  12,     -0.7                 % no correction 2 frames on
                "saw",      f(7, 8),     0.05,  8:9,    [0.5 - (1 - 0.25 / 0.3) ^ 2; -0.9 + (1 - 0.05 / 0.3) ^ 2]
                "square",   f(10, 5),    0.05,  10:11,  [-0.75; 0.75]        % rising edge
                "square",   f(10, 5),    0.55,  10:11,  [0.75; -0.75]        % falling edge
                "triangle", f(10, 5),    0.05,  10:11,  [-0.8 + 1 / 60; -0.8 + 1 / 60]   % corner: 4*0.1*(1/24)
                "triangle", f(11, 4),    0.05,  12,     -0.4
                % The pitch changes at frame 10, and the corner falls between frames
                % 10 and 11, crossed by frame 10's NEW step 0.3: both corrections are
                % 4*0.3*(1/24) = 0.05, on the naive value -0.4.
                "triangle", f(9, 6),     0.95,  10:11,  [-0.35; -0.35]
                };
            for k = 1:size(cases, 1)
                [wf, freq, ph, frames, expected] = cases{k, :};
                y = bpm.dsp.polyblepOsc(wf, freq, fs, numel(freq), ph);
                testCase.verifyEqual(y(frames), expected, "AbsTol", 1e-12, "Case " + k + " (" + wf + ")");
            end
        end

        function prevFreqHzSmoothsAJumpAtTheBlockStart(testCase)
            % A pitch change exactly at a block boundary, with a saw jump between the
            % two blocks. 441 Hz at 44.1 kHz is 0.01 cycles per sample, so 1000 frames
            % are exactly 10 cycles and the jump falls half a sample before block 2.
            fs = 44100;
            whole = bpm.dsp.polyblepOsc("saw", [repmat(441, 1000, 1); repmat(661.5, 1000, 1)], fs, 2000, 0.005);
            [y1, ph] = bpm.dsp.polyblepOsc("saw", 441, fs, 1000, 0.005);
            y2 = bpm.dsp.polyblepOsc("saw", 661.5, fs, 1000, ph, PrevFreqHz=441);
            testCase.verifyEqual([y1; y2], whole, "AbsTol", 1e-9);
            % Without PrevFreqHz the first sample of block 2 is corrected as if the
            % pitch hadn't changed, which is noticeably different there.
            guess = bpm.dsp.polyblepOsc("saw", 661.5, fs, 1000, ph);
            testCase.verifyGreaterThan(abs(guess(1) - whole(1001)), 0.01);
            testCase.verifyEqual(guess(2:end), y2(2:end), "AbsTol", 1e-12, "Only the first sample differs.");
        end

        function squareNeverSpikesFromRounding(testCase)
            % At some round frequencies the phase lands on the largest number just
            % below 0.5. That sample sits on the falling edge and must be its
            % midpoint (0), not 2. (450 Hz at 44.1 kHz hits it at frame 50.)
            y = bpm.dsp.polyblepOsc("square", 450, 44100, 50);
            testCase.verifyEqual(y(50), 0, "AbsTol", 1e-9);
            for c = {{100, 48000}, {200, 48000}, {450, 44100}, {225, 44100}, {1000, 96000}}
                [f0, rate] = c{1}{:};
                y = bpm.dsp.polyblepOsc("square", f0, rate, rate);
                testCase.verifyLessThanOrEqual(max(abs(y)), 1 + 1e-9, f0 + " Hz at " + rate);
            end
        end

        function zeroFrequencyHoldsStill(testCase, waveform, startPhase)
            % 0 Hz (for example a stopped LFO) must give a steady, finite value.
            y = bpm.dsp.polyblepOsc(waveform, 0, 44100, 50, startPhase);
            testCase.verifyTrue(all(isfinite(y)), "No NaN or Inf.");
            testCase.verifyEqual(y, repmat(y(1), 50, 1), "Constant.");
        end

        function zeroFramesGivesAnEmptyColumn(testCase)
            [y, ph] = bpm.dsp.polyblepOsc("saw", 440, 44100, 0, 0.3);
            testCase.verifySize(y, [0 1]);
            testCase.verifyEqual(ph, 0.3);
            [y, ph] = bpm.dsp.polyblepOsc("saw", zeros(0, 1), 44100, 0, 0.3);
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
            testCase.verifyError(@() bpm.dsp.polyblepOsc("saw", Inf, 44100, 10), "MATLAB:validators:mustBeFinite");
            testCase.verifyError(@() bpm.dsp.polyblepOsc("saw", 440, Inf, 10), "MATLAB:validators:mustBeFinite");
            testCase.verifyError(@() bpm.dsp.polyblepOsc("saw", 440, 44100, 10, PrevFreqHz=22050), "bpm:dsp:polyblepOsc:aboveNyquist");
            testCase.verifyError(@() bpm.dsp.polyblepOsc("saw", 440, 44100, 10, PrevFreqHz=[1 2]), "MATLAB:validators:mustBeScalarOrEmpty");
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
            % energy everywhere else. A 4-term Blackman-Harris window spreads each
            % harmonic over a main lobe +-4 FFT bins wide (outside it, leakage is
            % below -92 dB). A harmonic can sit halfway between bins (odd multiples
            % of 2500.5 Hz do), so we skip +-5 bins around each one. A pure sine
            % then measures about -87 dB (see aliasMeasureHasALowNoiseFloor).
            n = numel(y);
            k = (0:n - 1)';
            w = 0.35875 - 0.48829 * cos(2 * pi * k / (n - 1)) ...
                + 0.14128 * cos(4 * pi * k / (n - 1)) - 0.01168 * cos(6 * pi * k / (n - 1));
            P = abs(fft(y .* w)) .^ 2;
            P = P(1:floor(n / 2));
            f = (0:numel(P) - 1)' * fs / n;
            nearHarmonic = f < 20;
            for h = f0 * (1:floor((fs / 2) / f0))
                nearHarmonic = nearHarmonic | abs(f - h) <= 5 * fs / n;
            end
            d = 10 * log10(sum(P(~nearHarmonic)) / sum(P));
        end

        function y = renderInBlocks(waveform, f0, fs, n, blockSize)
            % Render n frames in blocks, passing the phase from block to block.
            y = zeros(n, 1);
            phase = 0;
            for first = 1:blockSize:n
                count = min(blockSize, n - first + 1);
                [y(first:first + count - 1), phase] = bpm.dsp.polyblepOsc(waveform, f0, fs, count, phase);
            end
        end
    end
end
