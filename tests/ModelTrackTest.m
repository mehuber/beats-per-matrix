classdef ModelTrackTest < BpmTestCase
    % Tests for bpm.model.Track.
    %
    % MATLAB features used below:
    %   @() expr           makes a small unnamed function; verifyError calls it and
    %                      checks that it throws the expected error.
    %   [t.effects.type]   collects the type of every effect into one string row.

    properties
        synth
        delay
        lowPass
        reverb
    end

    methods (TestClassSetup)
        function makeSpecs(testCase)
            % Built here, not as property defaults: defaults are evaluated when the
            % class loads, before BpmTestCase has put the repo root on the path.
            testCase.synth = bpm.model.PluginSpec("bpm.instruments.Synth");
            testCase.delay = bpm.model.PluginSpec("bpm.effects.Delay");
            testCase.lowPass = bpm.model.PluginSpec("bpm.effects.LowPass");
            testCase.reverb = bpm.model.PluginSpec("bpm.effects.Reverb");
        end
    end

    methods (Test)
        function hasSensibleDefaults(testCase)
            t = bpm.model.Track();
            testCase.verifyEqual(t.id, "");
            testCase.verifyEqual(t.name, "Track");
            testCase.verifyEmpty(t.instrument);
            testCase.verifySize(t.effects, [1 0]);
            testCase.verifyEqual(t.volumeDb, 0);
            testCase.verifyEqual(t.pan, 0);
            testCase.verifyFalse(t.mute);
            testCase.verifyFalse(t.solo);
        end

        function constructsFromNameValueArguments(testCase)
            t = bpm.model.Track(Name="Lead", Instrument=testCase.synth, Effects=testCase.delay, ...
                VolumeDb=-3, Pan=0.25, Mute=true, Solo=true, Id="trk-0042");
            testCase.verifyEqual(t.name, "Lead");
            testCase.verifyEqual(t.instrument, testCase.synth);
            testCase.verifyEqual(t.effects, testCase.delay);
            testCase.verifyEqual(t.volumeDb, -3);
            testCase.verifyEqual(t.pan, 0.25);
            testCase.verifyTrue(t.mute);
            testCase.verifyTrue(t.solo);
            testCase.verifyEqual(t.id, "trk-0042");
        end

        function muteAndSoloAreIndependent(testCase)
            % Set one at a time, so swapping the two by mistake would be caught.
            t = bpm.model.Track(Mute=true);
            testCase.verifyTrue(t.mute);
            testCase.verifyFalse(t.solo);
            t = bpm.model.Track(Solo=true);
            testCase.verifyFalse(t.mute);
            testCase.verifyTrue(t.solo);
        end

        function effectsAreAlwaysARow(testCase)
            % (1,:) turns a column of specs into a row and rejects a matrix.
            t = bpm.model.Track(Effects=[testCase.lowPass; testCase.delay]);
            testCase.verifySize(t.effects, [1 2]);
            testCase.verifyError(@() bpm.model.Track(Effects=[testCase.lowPass testCase.delay; testCase.reverb testCase.synth]), ...
                "MATLAB:validation:IncompatibleSize");
        end

        function idAndNameMustNotBeMissing(testCase)
            testCase.verifyError(@() bpm.model.Track(Id=string(missing)), "MATLAB:validators:mustBeNonmissing");
            testCase.verifyError(@() bpm.model.Track(Name=string(missing)), "MATLAB:validators:mustBeNonmissing");
        end

        function panMustBeBetweenMinusOneAndOne(testCase)
            testCase.verifyError(@() bpm.model.Track(Pan=1.5), "MATLAB:validators:mustBeInRange");
            testCase.verifyError(@() bpm.model.Track(Pan=-1.01), "MATLAB:validators:mustBeInRange");
            testCase.verifyEqual(bpm.model.Track(Pan=-1).pan, -1);
            testCase.verifyEqual(bpm.model.Track(Pan=1).pan, 1);
        end

        function volumeAllowsSilenceButNotOverSixDb(testCase)
            testCase.verifyEqual(bpm.model.Track(VolumeDb=-Inf).volumeDb, -Inf);
            testCase.verifyEqual(bpm.model.Track(VolumeDb=6).volumeDb, 6);
            testCase.verifyError(@() bpm.model.Track(VolumeDb=6.5), "MATLAB:validators:mustBeLessThanOrEqual");
            testCase.verifyError(@() bpm.model.Track(VolumeDb=NaN), "MATLAB:validators:mustBeNonNan");
        end

        function instrumentMustBeOneSpecOrNone(testCase)
            testCase.verifyError(@() bpm.model.Track(Instrument=[testCase.synth testCase.synth]), ...
                "MATLAB:validators:mustBeScalarOrEmpty");
            testCase.verifyError(@() bpm.model.Track(Instrument=struct("type", "x")), ...
                "MATLAB:validation:UnableToConvert");
            % "None" is PluginSpec.empty; plain [] is rejected (documented in Track.m).
            testCase.verifyEmpty(bpm.model.Track(Instrument=bpm.model.PluginSpec.empty).instrument);
            testCase.verifyError(@() bpm.model.Track(Instrument=[]), "MATLAB:validation:UnableToConvert");
        end

        function noInstrumentIsAlwaysTheSameValue(testCase)
            % Empties come in many shapes; the track always stores the 0x0 one, so
            % two tracks without an instrument are equal however it was removed.
            testCase.verifySize(bpm.model.Track().instrument, [0 0]);
            t = bpm.model.Track(Instrument=testCase.synth);
            t.instrument(1) = [];                                   % leaves 1x0 without the rule
            testCase.verifySize(t.instrument, [0 0]);
            testCase.verifyEqual(t, bpm.model.Track());
            testCase.verifyEqual(bpm.model.Track(Instrument=bpm.model.PluginSpec.empty(1, 0)), bpm.model.Track());
        end

        function textConvertsToPluginSpec(testCase)
            % MATLAB converts a value to a property's class by calling that class's
            % constructor, so a type name becomes a PluginSpec automatically.
            t = bpm.model.Track(Instrument="bpm.instruments.Synth", Effects="bpm.effects.Delay");
            testCase.verifyEqual(t.instrument, testCase.synth);
            testCase.verifyEqual(t.effects, testCase.delay);
            % An invalid name still fails. MATLAB reports its own generic
            % "unable to convert" error rather than PluginSpec's invalidType error.
            testCase.verifyError(@() bpm.model.Track(Instrument="not a type"), ...
                "MATLAB:validation:UnableToConvert");
        end

        function addEffectAppendsInOrder(testCase)
            t = bpm.model.Track().addEffect(testCase.lowPass).addEffect(testCase.delay);
            testCase.verifyEqual([t.effects.type], ["bpm.effects.LowPass", "bpm.effects.Delay"]);
        end

        function setEffectReplacesOnlyThatIndex(testCase)
            t = bpm.model.Track(Effects=[testCase.lowPass testCase.delay testCase.reverb]);
            t = t.setEffect(2, testCase.synth);
            testCase.verifyEqual([t.effects.type], ...
                ["bpm.effects.LowPass", "bpm.instruments.Synth", "bpm.effects.Reverb"]);
        end

        function removeEffectRemovesOnlyThatIndex(testCase)
            t = bpm.model.Track(Effects=[testCase.lowPass testCase.delay testCase.reverb]);
            t = t.removeEffect(2);
            testCase.verifyEqual([t.effects.type], ["bpm.effects.LowPass", "bpm.effects.Reverb"]);
            t = t.removeEffect(1).removeEffect(1);
            testCase.verifySize(t.effects, [1 0]);
        end

        function effectIndexMustExist(testCase)
            t = bpm.model.Track().addEffect(testCase.delay);
            testCase.verifyError(@() t.removeEffect(2), "bpm:model:Track:effectIndexOutOfRange");
            testCase.verifyError(@() t.setEffect(3, testCase.delay), "bpm:model:Track:effectIndexOutOfRange");
            testCase.verifyError(@() t.removeEffect(0), "MATLAB:validators:mustBePositive");
            testCase.verifyError(@() t.removeEffect(1.5), "MATLAB:validators:mustBeInteger");
            testCase.verifyError(@() t.setEffect(0, testCase.delay), "MATLAB:validators:mustBePositive");
            testCase.verifyError(@() t.setEffect(1.5, testCase.delay), "MATLAB:validators:mustBeInteger");
            try
                bpm.model.Track(Name="Bass", Effects=[testCase.delay testCase.reverb]).removeEffect(5);
            catch err
                testCase.verifySubstring(err.message, "Track ""Bass"" has 2 effect(s); there is no effect 5.");
            end
        end

        function effectMethodsTakeExactlyOneSpec(testCase)
            t = bpm.model.Track().addEffect(testCase.delay);
            two = [testCase.delay testCase.reverb];
            none = bpm.model.PluginSpec.empty;
            testCase.verifyError(@() t.addEffect(two), "MATLAB:validation:IncompatibleSize");
            testCase.verifyError(@() t.addEffect(none), "MATLAB:validation:IncompatibleSize");
            testCase.verifyError(@() t.setEffect(1, two), "MATLAB:validation:IncompatibleSize");
            testCase.verifyError(@() t.setEffect(1, none), "MATLAB:validation:IncompatibleSize");
        end

        function methodsDoNotChangeTheOriginal(testCase)
            original = bpm.model.Track(Name="Bass", Effects=[testCase.lowPass testCase.delay]);
            added = original.addEffect(testCase.reverb);
            replaced = original.setEffect(1, testCase.reverb);
            removed = original.removeEffect(1);

            testCase.verifyEqual([original.effects.type], ["bpm.effects.LowPass", "bpm.effects.Delay"]);
            testCase.verifySize(added.effects, [1 3]);
            testCase.verifyEqual(replaced.effects(1).type, "bpm.effects.Reverb");
            testCase.verifySize(removed.effects, [1 1]);
        end
    end
end
