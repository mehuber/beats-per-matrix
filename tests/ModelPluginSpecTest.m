classdef ModelPluginSpecTest < BpmTestCase
    % Tests for bpm.model.PluginSpec.

    methods (Test)
        function constructsWithDefaults(testCase)
            spec = bpm.model.PluginSpec("bpm.effects.Delay");
            testCase.verifyEqual(spec.type, "bpm.effects.Delay");
            testCase.verifyEqual(spec.params, struct());
            testCase.verifyFalse(spec.bypass);
        end

        function constructsWithParamsAndBypass(testCase)
            spec = bpm.model.PluginSpec("bpm.effects.LowPass", struct("cutoffHz", 1800, "q", 0.7), Bypass=true);
            testCase.verifyEqual(spec.params.cutoffHz, 1800);
            testCase.verifyEqual(spec.params.q, 0.7);
            testCase.verifyTrue(spec.bypass);
        end

        function acceptsJsonFriendlyParamValues(testCase)
            p = struct("n", 3, "flag", true, "mode", "saw", "label", 'chars', ...
                "row", [1 2 3], "none", []);
            spec = bpm.model.PluginSpec("bpm.instruments.Synth", p);
            testCase.verifyEqual(spec.params, p);
        end

        function rejectsBadTypeNames(testCase)
            for bad = ["", "Delay effect", "1bpm.Delay", "bpm..Delay", "bpm.effects.", ".Delay"]
                testCase.verifyError(@() bpm.model.PluginSpec(bad), ...
                    "bpm:model:PluginSpec:invalidType", "Should reject """ + bad + """");
            end
        end

        function rejectsBadTypeAssignedLater(testCase)
            spec = bpm.model.PluginSpec("bpm.effects.Delay");
            function assignBad()
                spec.type = "not a class";
            end
            testCase.verifyError(@assignBad, "bpm:model:PluginSpec:invalidType");
        end

        function rejectsNonJsonParams(testCase)
            badValues = {{1, 2}, struct("a", 1), [1 2; 3 4], 1 + 2i, [1; 2]};
            for k = 1:numel(badValues)
                p = struct("x", {badValues(k)});   % {badValues(k)} stores the value itself
                testCase.verifyError(@() bpm.model.PluginSpec("bpm.effects.Delay", p), ...
                    "bpm:model:PluginSpec:invalidParams", "Case " + k);
            end
        end

        function withParamReturnsModifiedCopy(testCase)
            original = bpm.model.PluginSpec("bpm.effects.Delay", struct("mix", 0.5));
            changed = original.withParam("mix", 0.2).withParam("timeMs", 300);

            testCase.verifyEqual(changed.params.mix, 0.2);
            testCase.verifyEqual(changed.params.timeMs, 300);
            % Value semantics: the original is untouched.
            testCase.verifyEqual(original.params, struct("mix", 0.5));
        end

        function withParamRejectsBadNameOrValue(testCase)
            spec = bpm.model.PluginSpec("bpm.effects.Delay");
            testCase.verifyError(@() spec.withParam("bad name", 1), "MATLAB:validators:mustBeValidVariableName");
            testCase.verifyError(@() spec.withParam("x", {1}), "bpm:model:PluginSpec:invalidParams");
        end

        function emptyArrayNeedsNoConstructorCall(testCase)
            specs = bpm.model.PluginSpec.empty(1, 0);
            testCase.verifySize(specs, [1 0]);
        end
    end
end
