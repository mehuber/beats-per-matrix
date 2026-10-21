classdef PlaceholderTest < BpmTestCase
    % Placeholder so CI has something to run before real features land.
    % It also checks the one hard requirement we already have: MATLAB R2025a or newer.

    methods (Test)
        function matlabReleaseIsSupported(testCase)
            testCase.verifyFalse(isMATLABReleaseOlderThan("R2025a"), ...
                "Beats Per Matrix requires MATLAB R2025a or newer.");
        end

        function bpmNamespaceIsOnPath(testCase)
            % BpmTestCase adds the repo root to the path; this proves it worked.
            testCase.verifyNotEmpty(meta.package.fromName("bpm"), ...
                "The +bpm namespace is not on the path. Does this test inherit from BpmTestCase?");
        end
    end
end
