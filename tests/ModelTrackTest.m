classdef ModelTrackTest < BpmTestCase
    % Tests for bpm.model.Track.

    properties
        Synth
        Delay
        LowPass
    end

    methods (TestClassSetup)
        function makeSpecs(testCase)
            % Built here, not as property defaults: defaults are evaluated when the
            % class loads, before BpmTestCase has put the repo root on the path.
            testCase.Synth = bpm.model.PluginSpec("bpm.instruments.Synth");
            testCase.Delay = bpm.model.PluginSpec("bpm.effects.Delay");
            testCase.LowPass = bpm.model.PluginSpec("bpm.effects.LowPass");
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
            t = bpm.model.Track(Name="Lead", Instrument=testCase.Synth, Effects=testCase.Delay, ...
                VolumeDb=-3, Pan=0.25, Mute=true, Solo=true, Id="trk-0042");
            testCase.verifyEqual(t.name, "Lead");
            testCase.verifyEqual(t.instrument, testCase.Synth);
            testCase.verifyEqual(t.effects, testCase.Delay);
            testCase.verifyEqual(t.volumeDb, -3);
            testCase.verifyEqual(t.pan, 0.25);
            testCase.verifyTrue(t.mute);
            testCase.verifyTrue(t.solo);
            testCase.verifyEqual(t.id, "trk-0042");
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
            testCase.verifyError(@() bpm.model.Track(Instrument=[testCase.Synth testCase.Synth]), ...
                "MATLAB:validators:mustBeScalarOrEmpty");
            testCase.verifyError(@() bpm.model.Track(Instrument=struct("type", "x")), ...
                "MATLAB:validation:UnableToConvert");
        end

        function textConvertsToPluginSpec(testCase)
            % MATLAB converts a value to a property's class by calling that class's
            % constructor, so a type name becomes a PluginSpec automatically.
            t = bpm.model.Track(Instrument="bpm.instruments.Synth", Effects="bpm.effects.Delay");
            testCase.verifyEqual(t.instrument, testCase.Synth);
            testCase.verifyEqual(t.effects, testCase.Delay);
            % The type name is still validated during that conversion. MATLAB wraps
            % our invalidType error in its own "unable to convert" error.
            testCase.verifyError(@() bpm.model.Track(Instrument="not a type"), ...
                "MATLAB:validation:UnableToConvert");
        end

        function addSetRemoveEffects(testCase)
            t = bpm.model.Track();
            t = t.addEffect(testCase.LowPass).addEffect(testCase.Delay);
            testCase.verifyEqual([t.effects.type], ["bpm.effects.LowPass", "bpm.effects.Delay"]);

            t = t.setEffect(1, testCase.Delay);
            testCase.verifyEqual([t.effects.type], ["bpm.effects.Delay", "bpm.effects.Delay"]);

            t = t.removeEffect(2);
            testCase.verifyEqual([t.effects.type], "bpm.effects.Delay");
            t = t.removeEffect(1);
            testCase.verifySize(t.effects, [1 0]);
        end

        function effectIndexMustExist(testCase)
            t = bpm.model.Track().addEffect(testCase.Delay);
            testCase.verifyError(@() t.removeEffect(2), "bpm:model:Track:effectIndexOutOfRange");
            testCase.verifyError(@() t.setEffect(3, testCase.Delay), "bpm:model:Track:effectIndexOutOfRange");
            testCase.verifyError(@() t.removeEffect(0), "MATLAB:validators:mustBePositive");
        end

        function methodsDoNotChangeTheOriginal(testCase)
            original = bpm.model.Track(Name="Bass");
            changed = original.addEffect(testCase.Delay);
            testCase.verifySize(original.effects, [1 0]);
            testCase.verifySize(changed.effects, [1 1]);
        end
    end
end
