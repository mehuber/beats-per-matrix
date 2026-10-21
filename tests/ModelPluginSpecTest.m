classdef ModelPluginSpecTest < BpmTestCase
    % Tests for bpm.model.PluginSpec.
    %
    % Note: verifyEqual on two STRUCTS checks each field's class too ("a" vs 'a'
    % fails), but on two OBJECTS it uses isequal, which treats "a" and 'a' as
    % equal. So tests about stored forms compare spec.params, not the whole spec.

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

        function storesSettingsInCanonicalForm(testCase)
            % Each pair: what goes in -> what is stored (see PluginSpec.normalizeParams).
            cases = {
                3,                   3
                int8(4),             4                  % numbers become double
                single(0.5),         0.5
                true,                true               % logicals stay logical
                [true; false],       [true false]       % lists become rows
                [1; 2; 3],           [1 2 3]
                "saw",               "saw"
                'saw',               "saw"              % text becomes string
                {'lo'; 'hi'},        ["lo" "hi"]        % cell of text -> string row
                {"lo", "hi"},        ["lo" "hi"]
                {'lo', "hi"},        ["lo" "hi"]
                ["a"; "b"],          ["a" "b"]
                "",                  ""
                '',                  ""
                [],                  []                 % every empty list -> []
                zeros(1, 0),         []
                zeros(0, 1),         []
                false(1, 0),         []
                strings(1, 0),       []
                {},                  []
                zeros(0, 3),         []
                zeros(3, 0),         []
                strings(0, 3),       []
                cell(0, 3),          []
                {''},                ""                 % a blank in a list (jsondecode gives '')
                {'', 'a'},           ["" "a"]
                matlab.lang.OnOffSwitchState.on, true   % logical look-alike -> plain true
                };
            for k = 1:size(cases, 1)
                p = struct();
                p.x = cases{k, 1};
                spec = bpm.model.PluginSpec("bpm.effects.Test", p);
                testCase.verifyEqual(spec.params.x, cases{k, 2}, "Case " + k);
            end
        end

        function settingsSurviveAJsonRoundTripExactly(testCase)
            % Save then load must give back exactly the same settings (needed by V1-18).
            p = struct("n", 3, "i", int16(7), "s", single(0.25), "flag", true, ...
                "row", [0.5 1 2], "one", [9], "names", ["saw" "sine"], "oneName", "saw", ...
                "chars", 'abc', "empty", [], "emptyRow", zeros(1, 0), "emptyText", strings(1, 0), ...
                "blank", "", "flags", [true false true], "withBlank", ["a" "" "b"], ...
                "blanks", ["" ""], "switch", matlab.lang.OnOffSwitchState.off);
            original = bpm.model.PluginSpec("bpm.instruments.Synth", p);
            decoded = jsondecode(jsonencode(original.params));
            reloaded = bpm.model.PluginSpec(original.type, decoded);
            testCase.verifyEqual(reloaded.params, original.params);
        end

        function rejectsBadTypeNames(testCase)
            bad = ["", "Delay", "true", "Delay effect", "1bpm.Delay", "bpm..Delay", ...
                "bpm.effects.", ".Delay", "bpm.end.Delay", "bpm.effects.D" + char(233) + "lay", string(missing)];
            for k = 1:numel(bad)
                testCase.verifyError(@() bpm.model.PluginSpec(bad(k)), ...
                    "bpm:model:PluginSpec:invalidType", ...
                    "Should reject case " + k + ": " + fillmissing(bad(k), "constant", "<missing>"));
            end
        end

        function acceptsQualifiedTypeNames(testCase)
            for good = ["bpm.effects.Delay", "my.Plugin", "a.b.c.D_2"]
                testCase.verifyEqual(bpm.model.PluginSpec(good).type, good);
            end
            testCase.verifyEqual(bpm.model.PluginSpec('bpm.effects.Delay').type, "bpm.effects.Delay");
        end

        function isQualifiedNameAcceptsStringOrChar(testCase)
            testCase.verifyTrue(bpm.model.PluginSpec.isQualifiedName("bpm.effects.Delay"));
            testCase.verifyTrue(bpm.model.PluginSpec.isQualifiedName('bpm.effects.Delay'));
            testCase.verifyFalse(bpm.model.PluginSpec.isQualifiedName(["a.b" "c.d"]));
            testCase.verifyFalse(bpm.model.PluginSpec.isQualifiedName(42));
        end

        function rejectsBadTypeAssignedLater(testCase)
            spec = bpm.model.PluginSpec("bpm.effects.Delay");
            % A nested function lets verifyError run an assignment statement.
            function assignBad()
                spec.type = "not a class";
            end
            testCase.verifyError(@assignBad, "bpm:model:PluginSpec:invalidType");
        end

        function typeIsRequired(testCase)
            testCase.verifyError(@() bpm.model.PluginSpec(), "bpm:model:PluginSpec:typeRequired");
        end

        function growingAnArrayPastItsEndGivesAClearError(testCase)
            % MATLAB fills the gap at specs(2) by calling the constructor with no inputs.
            function growWithGap()
                specs = bpm.model.PluginSpec("bpm.effects.Delay");
                specs(3) = bpm.model.PluginSpec("bpm.effects.Reverb");
            end
            testCase.verifyError(@growWithGap, "bpm:model:PluginSpec:typeRequired");
        end

        function rejectsNonJsonParams(testCase)
            % Each row: a bad value, and a word the error message must contain.
            badValues = {
                {1, 2},                         "other than text"
                {'a', 1},                       "other than text"
                {"a", 1},                       "other than text"
                {['a'; 'b']},                   "other than text"
                {char(zeros(0, 5))},            "other than text"
                {{'a'}},                        "other than text"
                {'a', 'b'; 'c', 'd'},           "size 2x2"
                char(zeros(3, 0)),              "size 3x0"
                struct("a", 1),                 "struct"
                table(1),                       "table"
                bpm.model.PluginSpec("bpm.a.B"), "PluginSpec"
                [1 2; 3 4],                     "size 2x2"
                ['ab'; 'cd'],                   "size 2x2"
                ['a'; 'b'],                     "size 2x1"
                1 + 2i,                         "complex"
                NaN,                            "NaN or Inf"
                Inf,                            "NaN or Inf"
                -Inf,                           "NaN or Inf"
                [1 NaN],                        "NaN or Inf"
                string(missing),                "missing text"
                ["a" missing],                  "missing text"
                sparse([1 0 2]),                "sparse"
                };
            for k = 1:size(badValues, 1)
                % badValues{k, 1} (curly braces) takes the value OUT of the cell.
                % badValues(k, 1) (parentheses) would give a 1x1 cell CONTAINING
                % it, and every case would then only test "a cell is rejected".
                p = struct();
                p.x = badValues{k, 1};
                try
                    bpm.model.PluginSpec("bpm.effects.Delay", p);
                    testCase.verifyFail("Case " + k + " (" + class(badValues{k, 1}) + ") was accepted.");
                catch err
                    testCase.verifyEqual(string(err.identifier), "bpm:model:PluginSpec:invalidParams", ...
                        "Case " + k + ": " + err.message);
                    testCase.verifySubstring(err.message, badValues{k, 2}, "Case " + k);
                end
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

        function withParamStoresCanonicalForm(testCase)
            spec = bpm.model.PluginSpec("bpm.effects.Delay").withParam("mode", 'pingpong');
            testCase.verifyEqual(spec.params.mode, "pingpong");
        end

        function withParamRejectsBadNameOrValue(testCase)
            spec = bpm.model.PluginSpec("bpm.effects.Delay");
            testCase.verifyError(@() spec.withParam("bad name", 1), "MATLAB:validators:mustBeValidVariableName");
            % Looping over a cell gives a 1x1 cell each time, so bad{1} takes the value out.
            for bad = {{1}, 1 + 2i, NaN, [1 2; 3 4]}
                testCase.verifyError(@() spec.withParam("x", bad{1}), "bpm:model:PluginSpec:invalidParams");
            end
        end
    end
end
