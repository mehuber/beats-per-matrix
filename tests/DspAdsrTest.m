classdef DspAdsrTest < BpmTestCase
    % Tests for bpm.dsp.adsr.
    %
    % MATLAB features used below:
    %   @() expr     makes a small unnamed function; verifyError calls it and checks
    %                that it throws the expected error.
    %   env(k + 1)   MATLAB counts from 1, but frames count from 0, so frame k is
    %                element k + 1.

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
            % Linear segments of at least 1 ms never change by more than 1/(1 ms) per frame.
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

        function blocksJoinUpExactly(testCase, fs)
            % Rendering one note in blocks with StartFrame gives the same envelope
            % as rendering it all at once (needed by block-based instruments).
            args = {0.02, 0.05, 0.6, 0.1, fs, round(0.15 * fs)};
            whole = bpm.dsp.adsr(args{:}, 3 * 1024 + 300);
            blocks = [bpm.dsp.adsr(args{:}, 1024, StartFrame=0)
                      bpm.dsp.adsr(args{:}, 1024, StartFrame=1024)
                      bpm.dsp.adsr(args{:}, 1024, StartFrame=2048)
                      bpm.dsp.adsr(args{:}, 300, StartFrame=3072)];
            testCase.verifyEqual(blocks, whole);
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
                2, Inf,    "MATLAB:validators:mustBeFinite"        % endless decay
                3, 1.5,    "MATLAB:validators:mustBeInRange"       % sustain above 1
                4, -1,     "MATLAB:validators:mustBeNonnegative"   % negative release
                5, 0,      "MATLAB:validators:mustBePositive"      % zero sample rate
                6, NaN,    "MATLAB:validators:mustBeNonNan"        % gate NaN
                7, 10.5,   "MATLAB:validators:mustBeInteger"       % fractional frame count
                };
            for k = 1:size(bad, 1)
                args = ok;
                args{bad{k, 1}} = bad{k, 2};
                testCase.verifyError(@() bpm.dsp.adsr(args{:}), bad{k, 3}, "Argument " + bad{k, 1});
            end
            testCase.verifyError(@() bpm.dsp.adsr(ok{:}, StartFrame=-1), "MATLAB:validators:mustBeNonnegative");
        end
    end
end
