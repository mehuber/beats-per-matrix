classdef DspGainPanTest < BpmTestCase
    % Tests for bpm.dsp.dbToGain and bpm.dsp.panGains.
    %
    % MATLAB features used below:
    %   @() expr   makes a small unnamed function; verifyError calls it and checks
    %              that it throws the expected error.

    methods (Test)
        function dbToGainKnownValues(testCase)
            testCase.verifyEqual(bpm.dsp.dbToGain(0), 1);
            testCase.verifyEqual(bpm.dsp.dbToGain(20), 10, "AbsTol", 1e-12);
            testCase.verifyEqual(bpm.dsp.dbToGain(-20), 0.1, "AbsTol", 1e-12);
            testCase.verifyEqual(bpm.dsp.dbToGain(20 * log10(0.5)), 0.5, "AbsTol", 1e-12);
            testCase.verifyEqual(bpm.dsp.dbToGain(-Inf), 0, "-Inf dB is silence.");
        end

        function dbToGainWorksOnArraysAndKeepsTheirShape(testCase)
            dB = [0 -6; 6 -Inf];
            testCase.verifyEqual(bpm.dsp.dbToGain(dB), 10 .^ (dB / 20), "AbsTol", 1e-12);
            testCase.verifySize(bpm.dsp.dbToGain(zeros(3, 1)), [3 1]);
        end

        function dbToGainRejectsNaNAndComplex(testCase)
            testCase.verifyError(@() bpm.dsp.dbToGain(NaN), "MATLAB:validators:mustBeNonNan");
            testCase.verifyError(@() bpm.dsp.dbToGain(1i), "MATLAB:validators:mustBeReal");
        end

        function panPreservesPowerEverywhere(testCase)
            pan = linspace(-1, 1, 201);
            [gL, gR] = bpm.dsp.panGains(pan);
            testCase.verifyEqual(gL .^ 2 + gR .^ 2, ones(1, 201), "AbsTol", 1e-12);
        end

        function panKnownPositions(testCase)
            [gL, gR] = bpm.dsp.panGains([-1 0 1]);
            testCase.verifyEqual(gL, [1 1 / sqrt(2) 0], "AbsTol", 1e-12);
            testCase.verifyEqual(gR, [0 1 / sqrt(2) 1], "AbsTol", 1e-12);
            testCase.verifyEqual([gL(3) gR(1)], [0 0], "Hard left/right are exactly silent on the other side.");
        end

        function panMovesSmoothlyFromLeftToRight(testCase)
            [gL, gR] = bpm.dsp.panGains(linspace(-1, 1, 101));
            testCase.verifyLessThan(diff(gL), 0, "Left gets quieter as pan moves right.");
            testCase.verifyGreaterThan(diff(gR), 0, "Right gets louder.");
        end

        function panIsSymmetric(testCase)
            p = [0.1 0.4 0.9];
            [gL, gR] = bpm.dsp.panGains(p);
            [mL, mR] = bpm.dsp.panGains(-p);
            testCase.verifyEqual(gL, mR, "AbsTol", 1e-12);
            testCase.verifyEqual(gR, mL, "AbsTol", 1e-12);
        end

        function panKeepsTheShapeOfItsInput(testCase)
            [gL, gR] = bpm.dsp.panGains(zeros(2, 3));
            testCase.verifySize(gL, [2 3]);
            testCase.verifySize(gR, [2 3]);
        end

        function panRejectsPositionsOutsideTheRange(testCase)
            testCase.verifyError(@() bpm.dsp.panGains(1.01), "MATLAB:validators:mustBeInRange");
            testCase.verifyError(@() bpm.dsp.panGains([0 -2]), "MATLAB:validators:mustBeInRange");
        end
    end
end
