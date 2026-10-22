classdef DspAdsrTest < BpmTestCase
    % Tests for bpm.dsp.adsr.
    %
    % MATLAB features used below:
    %   properties (TestParameter)  a test that takes fs runs once per rate.
    %   @() expr     makes a small unnamed function; verifyError calls it and checks
    %                that it throws the expected error.
    %   env(k + 1)   MATLAB counts from 1, but frames count from 0, so frame k is
    %                element k + 1.
    %   args{:}      spreads the cell array args out as separate inputs, so
    %                adsr(args{:}, 10) is adsr(args{1}, args{2}, ..., 10).
    %   bad{k, 1}    curly braces take the value OUT of row k, column 1 of a cell.
    %   [~, done]    ~ throws away the first output; we only want the second.
    %   properties (Constant)  a fixed value shared by all tests: testCase.tol.
    %   "Argument " + k   + joins text, turning the number k into text first.

    properties (TestParameter)
        fs = {44100, 96000}   % every test that takes fs runs at both rates
    end

    properties (Constant)
        tol = 1e-12
    end

    methods (Test)
        function attackRisesLinearlyToOne(testCase, fs)
            a = 2 * round(0.005 * fs);                 % attack length in frames (even, so a/2 is whole)
            env = bpm.dsp.adsr(a / fs, 0.1, 0.7, 0.3, fs, Inf, 2 * a);
            testCase.verifyEqual(env(1), 0, "Starts at 0.");
            testCase.verifyEqual(env(a / 2 + 1), 0.5, "AbsTol", testCase.tol, "Halfway through the attack.");
            testCase.verifyEqual(env(a + 1), 1, "AbsTol", testCase.tol, "Peak exactly at the end of the attack.");
            testCase.verifyEqual(max(env), 1, "AbsTol", testCase.tol, "Never above 1.");
        end

        function decayFallsToSustainThenHolds(testCase, fs)
            a = round(0.01 * fs); d = round(0.1 * fs);
            env = bpm.dsp.adsr(a / fs, d / fs, 0.7, 0.3, fs, Inf, a + 2 * d);
            testCase.verifyEqual(env(a + d / 2 + 1), 0.85, "AbsTol", testCase.tol, "Halfway down the decay.");
            testCase.verifyEqual(env(a + d + 1), 0.7, "AbsTol", testCase.tol, "Sustain level at the end of the decay.");
            testCase.verifyEqual(env(a + d + 1:end), repmat(0.7, d, 1), "AbsTol", testCase.tol, "Holds while the key is down.");
        end

        function releaseFallsLinearlyToZero(testCase, fs)
            a = round(0.01 * fs); d = round(0.1 * fs); r = round(0.3 * fs);
            gate = a + d + 1000;                       % released during sustain
            env = bpm.dsp.adsr(a / fs, d / fs, 0.7, r / fs, fs, gate, gate + r + 500);
            testCase.verifyEqual(env(gate + 1), 0.7, "AbsTol", testCase.tol, "Release starts at the sustain level.");
            testCase.verifyEqual(env(gate + r / 2 + 1), 0.35, "AbsTol", testCase.tol, "Halfway through the release.");
            testCase.verifyEqual(env(gate + r + 1:end), zeros(500, 1), "Silent after the release.");
        end

        function releaseDuringAttackStartsFromTheCurrentLevel(testCase, fs)
            a = 2 * round(0.005 * fs);                 % even, so a/2 is a whole frame
            gate = a / 2;                               % let go halfway up the attack
            env = bpm.dsp.adsr(a / fs, 0.1, 0.7, 0.1, fs, gate, a);
            testCase.verifyEqual(env(gate + 1), 0.5, "AbsTol", testCase.tol);
            testCase.verifyLessThan(diff(env(gate + 1:end)), 0, "Falls from there, no jump up to 1.");
        end

        function noJumpsAnywhere(testCase, fs)
            % The steepest segment is the 5 ms attack, which rises by 1 over
            % 0.005*fs frames, so no step between frames may exceed 1/(0.005*fs).
            env = bpm.dsp.adsr(0.005, 0.05, 0.4, 0.2, fs, round(0.3 * fs), fs);
            biggestStep = 1 / (0.005 * fs);
            testCase.verifyLessThanOrEqual(max(abs(diff(env))), biggestStep + testCase.tol);
        end

        function zeroAttackStartsAtFullLevel(testCase, fs)
            env = bpm.dsp.adsr(0, 0.1, 0.5, 0.1, fs, Inf, 10);
            testCase.verifyEqual(env(1), 1);
        end

        function zeroDecayGoesStraightToSustain(testCase, fs)
            a = round(0.01 * fs);
            env = bpm.dsp.adsr(a / fs, 0, 0.6, 0.1, fs, Inf, a + 10);
            testCase.verifyEqual(env(a + 1:end), repmat(0.6, 10, 1));
        end

        function zeroReleaseStopsImmediately(testCase, fs)
            env = bpm.dsp.adsr(0, 0, 1, 0, fs, 100, 200);
            testCase.verifyEqual(env(1:100), ones(100, 1));
            testCase.verifyEqual(env(101:200), zeros(100, 1));
        end

        function fractionalStageLengthsAreExact(testCase)
            % At 44.1 kHz, 0.1 ms is 4.41 frames: stages need not be whole frames.
            fs = 44100;
            env = bpm.dsp.adsr(0.0001, 0, 0.5, 0.1, fs, Inf, 7);
            testCase.verifyEqual(env, [(0:4)' / 4.41; 0.5; 0.5], "AbsTol", 1e-12, "Fractional attack.");
            env = bpm.dsp.adsr(0, 0.0001, 0.5, 0.1, fs, Inf, 7);
            testCase.verifyEqual(env, [1 - 0.5 * (0:4)' / 4.41; 0.5; 0.5], "AbsTol", 1e-12, "Fractional decay.");
            % Released at frame 20.5 during a 44.1-frame attack and 44.1-frame release.
            env = bpm.dsp.adsr(0.001, 0, 1, 0.001, fs, 20.5, 24);
            levelAtRelease = 20.5 / 44.1;
            testCase.verifyEqual(env(21), 20 / 44.1, "AbsTol", 1e-12, "Frame 20: still held.");
            testCase.verifyEqual(env(22), levelAtRelease * (1 - 0.5 / 44.1), "AbsTol", 1e-12, "Frame 21: releasing.");
        end

        function startLevelRestartsTheAttackFromThere(testCase, fs)
            % A retriggered or stolen voice starts its new attack from its current
            % level instead of jumping to 0 (which would click).
            a = 2 * round(0.005 * fs);
            env = bpm.dsp.adsr(a / fs, 0.1, 0.7, 0.3, fs, Inf, a + 1, StartLevel=0.4);
            testCase.verifyEqual(env(1), 0.4, "AbsTol", 1e-12);
            testCase.verifyEqual(env(a / 2 + 1), 0.7, "AbsTol", 1e-12, "Halfway from 0.4 to 1.");
            testCase.verifyEqual(env(a + 1), 1, "AbsTol", 1e-12);
            % A release during that attack starts from the level reached.
            env = bpm.dsp.adsr(a / fs, 0.1, 0.7, 0.01, fs, a / 2, a / 2 + 1, StartLevel=0.4);
            testCase.verifyEqual(env(end), 0.7, "AbsTol", 1e-12);
        end

        function blocksJoinUpExactly(testCase, fs)
            % Rendering one note in blocks with StartFrame gives the same envelope
            % as rendering it all at once (needed by block-based instruments).
            % Released at 50 ms with a 30 ms release, so the blocks cover attack,
            % decay, sustain, a release that starts mid-block, and silence after.
            gate = round(0.05 * fs); r = round(0.03 * fs);
            args = {0.01, 0.02, 0.6, r / fs, fs, gate};
            total = gate + r + 700;
            whole = bpm.dsp.adsr(args{:}, total);
            blocks = zeros(total, 1);
            for first = 0:1000:total - 1              % first frame of each block
                count = min(1000, total - first);
                blocks(first + 1:first + count) = bpm.dsp.adsr(args{:}, count, StartFrame=first);
            end
            testCase.verifyEqual(blocks, whole);
            testCase.verifyLessThan(whole(gate + round(r / 2)), 0.6, "The release really is inside the span.");
            testCase.verifyEqual(whole(end), 0, "So is the silence after it.");
        end

        function releaseDuringDecayIsAStraightLine(testCase, fs)
            a = round(0.01 * fs); d = round(0.1 * fs); r = round(0.3 * fs);
            gate = a + d / 2;                           % halfway from 1 down to 0.2: level 0.6
            env = bpm.dsp.adsr(a / fs, d / fs, 0.2, r / fs, fs, gate, gate + r + 1);
            k = (0:r)';
            testCase.verifyEqual(env(gate + 1 + k), 0.6 * (1 - k / r), "AbsTol", testCase.tol);
        end

        function fractionalAttackAndDecayTogether(testCase)
            fs = 44100;                                 % 0.1 ms = 4.41 frames
            env = bpm.dsp.adsr(0.0001, 0.0001, 0.5, 0.1, fs, Inf, 12);
            n = (0:11)';
            expected = repmat(0.5, 12, 1);
            expected(n < 4.41) = n(n < 4.41) / 4.41;
            inDecay = n >= 4.41 & n < 8.82;
            expected(inDecay) = 1 - 0.5 * (n(inDecay) - 4.41) / 4.41;
            testCase.verifyEqual(env, expected, "AbsTol", testCase.tol);
        end

        function releaseShorterThanAFrame(testCase)
            % Half a frame of release: the level holds at the gate frame, then is 0.
            fs = 44100;
            [env, done] = bpm.dsp.adsr(0, 0, 1, 0.5 / fs, fs, 10, 12);
            testCase.verifyEqual(env(11:12), [1; 0]);
            testCase.verifyTrue(done);
            [~, done] = bpm.dsp.adsr(0, 0, 1, 0.5 / fs, fs, 10, 11);
            testCase.verifyFalse(done, "The release ends half a frame after frame 10.");
            % Even 0.3 of a frame is a real (very short) release, not "no release":
            % the gate frame still has the full level.
            env = bpm.dsp.adsr(0, 0, 1, 0.3 / fs, fs, 10, 12);
            testCase.verifyEqual(env(11:12), [1; 0]);
        end

        function reportsWhenTheNoteHasFinished(testCase, fs)
            % Released at frame 1000, the release ends at frame 1000 + r. Asking for
            % frames 0 .. 1000 + r means asking for 1000 + r + 1 frames.
            r = round(0.1 * fs);
            [~, done] = bpm.dsp.adsr(0, 0, 1, r / fs, fs, 1000, 1000 + r + 1);
            testCase.verifyTrue(done, "The last frame is the end of the release.");
            [~, done] = bpm.dsp.adsr(0, 0, 1, r / fs, fs, 1000, 1000 + r);
            testCase.verifyFalse(done, "One frame before the end.");
            [~, done] = bpm.dsp.adsr(0, 0, 1, 0.1, fs, Inf, 10 * fs);
            testCase.verifyFalse(done, "Never finished while the key is held.");
            [~, done] = bpm.dsp.adsr(0, 0, 1, r / fs, fs, 1000, 10, StartFrame=1000 + r);
            testCase.verifyTrue(done, "Works with StartFrame too.");
        end

        function zeroSustainFinishesAfterTheDecay(testCase, fs)
            % A drum hit or pluck (sustain 0) is silent for good once the decay ends,
            % even if the key is never released, so its voice can be freed.
            a = round(0.001 * fs); d = round(0.2 * fs);
            [env, done] = bpm.dsp.adsr(a / fs, d / fs, 0, 0.5, fs, Inf, a + d + 1);
            testCase.verifyTrue(done);
            testCase.verifyEqual(env(end), 0);
            [~, done] = bpm.dsp.adsr(a / fs, d / fs, 0, 0.5, fs, Inf, a + d);
            testCase.verifyFalse(done, "Still decaying one frame earlier.");

            % Rendered in blocks (StartFrame), it is the same rule.
            [~, done] = bpm.dsp.adsr(a / fs, d / fs, 0, 0.5, fs, Inf, 10, StartFrame=a + d);
            testCase.verifyTrue(done, "A block that reaches the end of the decay.");
            [~, done] = bpm.dsp.adsr(a / fs, d / fs, 0, 0.5, fs, Inf, 10, StartFrame=a + d - 10);
            testCase.verifyFalse(done, "A block that ends just before it.");

            % Released halfway down the decay, with a release (0.5 s) longer than
            % the rest of the decay (0.1 s): the release decides, so the note is
            % still sounding when the decay alone would have reached 0.
            r = round(0.5 * fs); gate = a + d / 2;
            [env, done] = bpm.dsp.adsr(a / fs, d / fs, 0, r / fs, fs, gate, a + d + 1);
            testCase.verifyEqual(env(end), 0.5 * (1 - (d / 2) / r), "AbsTol", testCase.tol, "Still at 0.4.");
            testCase.verifyFalse(done, "Not finished while the release is still sounding.");
            [~, done] = bpm.dsp.adsr(a / fs, d / fs, 0, r / fs, fs, gate, gate + r + 1);
            testCase.verifyTrue(done, "Finished once the release has played out.");
            [~, done] = bpm.dsp.adsr(a / fs, d / fs, 0, r / fs, fs, gate, gate + r);
            testCase.verifyFalse(done, "One frame before that.");

            % Released exactly when the decay reaches 0: already silent, so finished.
            [env, done] = bpm.dsp.adsr(a / fs, d / fs, 0, 0.1, fs, a + d, a + d + 1);
            testCase.verifyTrue(done);
            testCase.verifyEqual(env(end), 0);

            % A tiny but non-zero sustain is never "finished" while held.
            [~, done] = bpm.dsp.adsr(a / fs, d / fs, 1e-6, 0.5, fs, Inf, 2 * (a + d));
            testCase.verifyFalse(done);

            % A retriggered pluck (StartLevel > 0) still finishes after its decay.
            [env, done] = bpm.dsp.adsr(a / fs, d / fs, 0, 0.5, fs, Inf, a + d + 1, StartLevel=0.3);
            testCase.verifyEqual(env(end), 0);
            testCase.verifyTrue(done);
        end

        function finishedUsesTheExactFractionalBoundary(testCase, fs)
            % Stage lengths and the gate can be fractions of a frame, so "finished"
            % must compare with the exact boundary, not a rounded one. (x / fs
            % seconds is x frames.)
            f = 1 / fs;
            % Sustain 0, key held: the decay ends at frame 2.205 + 2.205 = 4.41.
            [env, done] = bpm.dsp.adsr(2.205 * f, 2.205 * f, 0, 0.1, fs, Inf, 5);   % frames 0-4
            testCase.verifyGreaterThan(env(end), 0, "Frame 4 is still decaying.");
            testCase.verifyFalse(done);
            [env, done] = bpm.dsp.adsr(2.205 * f, 2.205 * f, 0, 0.1, fs, Inf, 6);   % frames 0-5
            testCase.verifyEqual(env(end), 0);
            testCase.verifyTrue(done, "Frame 5 is past 4.41.");
            % Released at frame 4.2, during a 4.41-frame attack, with a 44.1-frame
            % release: it ends at frame 48.3.
            [env, done] = bpm.dsp.adsr(4.41 * f, 0, 0, 44.1 * f, fs, 4.2, 49);      % frames 0-48
            testCase.verifyGreaterThan(env(end), 0, "Frame 48 is still releasing.");
            testCase.verifyFalse(done);
            [~, done] = bpm.dsp.adsr(4.41 * f, 0, 0, 44.1 * f, fs, 4.2, 50);        % frames 0-49
            testCase.verifyTrue(done, "Frame 49 is past 48.3.");
        end

        function alwaysBetweenZeroAndOne(testCase, fs)
            env = bpm.dsp.adsr(0.003, 0.02, 0.25, 0.04, fs, round(0.01 * fs), fs);
            testCase.verifyGreaterThanOrEqual(env, 0);
            testCase.verifyLessThanOrEqual(env, 1);
        end

        function outputIsAColumnOfTheRequestedLength(testCase)
            testCase.verifySize(bpm.dsp.adsr(0.01, 0.1, 0.7, 0.3, 44100, Inf, 123), [123 1]);
            testCase.verifySize(bpm.dsp.adsr(0.01, 0.1, 0.7, 0.3, 44100, Inf, 0), [0 1]);
        end

        function rejectsBadInputs(testCase)
            ok = {0.01, 0.1, 0.7, 0.3, 44100, Inf, 100};
            bad = {
                1, -0.01,  "MATLAB:validators:mustBeNonnegative"   % negative attack
                1, Inf,    "MATLAB:validators:mustBeFinite"        % endless attack
                2, -0.1,   "MATLAB:validators:mustBeNonnegative"   % negative decay
                2, Inf,    "MATLAB:validators:mustBeFinite"        % endless decay
                3, 1.5,    "MATLAB:validators:mustBeInRange"       % sustain above 1
                3, -0.1,   "MATLAB:validators:mustBeInRange"       % sustain below 0
                4, -1,     "MATLAB:validators:mustBeNonnegative"   % negative release
                4, Inf,    "MATLAB:validators:mustBeFinite"        % endless release
                5, 0,      "MATLAB:validators:mustBePositive"      % zero sample rate
                5, Inf,    "MATLAB:validators:mustBeFinite"        % infinite sample rate
                6, NaN,    "MATLAB:validators:mustBeNonNan"        % gate NaN
                6, -1,     "MATLAB:validators:mustBeNonnegative"   % gate before note-on
                7, 10.5,   "MATLAB:validators:mustBeInteger"       % fractional frame count
                7, -1,     "MATLAB:validators:mustBeNonnegative"   % negative frame count
                };
            for k = 1:size(bad, 1)
                args = ok;
                args{bad{k, 1}} = bad{k, 2};
                testCase.verifyError(@() bpm.dsp.adsr(args{:}), bad{k, 3}, "Argument " + bad{k, 1});
            end
            testCase.verifyError(@() bpm.dsp.adsr(ok{:}, StartFrame=-1), "MATLAB:validators:mustBeNonnegative");
            testCase.verifyError(@() bpm.dsp.adsr(ok{:}, StartFrame=0.5), "MATLAB:validators:mustBeInteger");
            testCase.verifyError(@() bpm.dsp.adsr(ok{:}, StartLevel=1.2), "MATLAB:validators:mustBeInRange");
            testCase.verifyError(@() bpm.dsp.adsr(ok{:}, StartLevel=-0.1), "MATLAB:validators:mustBeInRange");
        end
    end
end
