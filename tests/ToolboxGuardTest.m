classdef ToolboxGuardTest < BpmTestCase
    % Tests for bpm.util.hasToolbox, plus an example of the skip-if-missing
    % pattern every toolbox-dependent test should follow.

    methods (Test)
        function returnsLogicalScalar(testCase)
            for name = ["audio", "signal", "dsp"]
                tf = bpm.util.hasToolbox(name);
                testCase.verifyClass(tf, "logical");
                testCase.verifySize(tf, [1 1]);
            end
        end

        function nameIsCaseInsensitive(testCase)
            testCase.verifyEqual(bpm.util.hasToolbox("AUDIO"), bpm.util.hasToolbox("audio"));
        end

        function unknownNameErrors(testCase)
            testCase.verifyError(@() bpm.util.hasToolbox("kazoo"), ...
                "bpm:util:hasToolbox:unknownToolbox");
        end

        function agreesWithInstalledProducts(testCase)
            installed = any(strcmp({ver().Name}, "Audio Toolbox"));
            if ~installed
                testCase.verifyFalse(bpm.util.hasToolbox("audio"), ...
                    "Must be false when Audio Toolbox is not installed.");
            end
        end

        function audioToolboxExample(testCase)
            % The pattern: skip (Incomplete), don't fail, when the toolbox is missing.
            % In CI this runs in the "full" job and is skipped in the "base" job.
            testCase.assumeTrue(bpm.util.hasToolbox("audio"), ...
                "Audio Toolbox not available; skipping.");
            testCase.verifyTrue(exist("audioDeviceWriter", "class") == 8, ...
                "audioDeviceWriter should exist when Audio Toolbox is available.");
        end
    end
end
