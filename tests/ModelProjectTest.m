classdef ModelProjectTest < BpmTestCase
    % Tests for bpm.model.Project.

    properties (TestParameter)
        % Each test that takes "rate" runs once per value (PLAN.md decision 8).
        rate = {44100, 48000, 96000}
    end

    methods (Test)
        function hasSensibleDefaults(testCase)
            p = bpm.model.Project();
            testCase.verifyEqual(p.formatVersion, bpm.model.Project.FORMAT_VERSION);
            testCase.verifyEqual(p.name, "Untitled");
            testCase.verifyEqual(p.sampleRate, 44100);
            testCase.verifyEqual(p.lengthBeats, 16);
            testCase.verifySize(p.tracks, [1 0]);
            testCase.verifySize(p.masterEffects, [1 0]);
            testCase.verifyEqual(p.masterVolumeDb, 0);
        end

        function constructsFromNameValueArguments(testCase)
            p = bpm.model.Project(Name="Demo", SampleRate=48000, LengthBeats=32, MasterVolumeDb=-1);
            testCase.verifyEqual(p.name, "Demo");
            testCase.verifyEqual(p.sampleRate, 48000);
            testCase.verifyEqual(p.lengthBeats, 32);
            testCase.verifyEqual(p.masterVolumeDb, -1);
        end

        function acceptsSupportedSampleRates(testCase, rate)
            testCase.verifyEqual(bpm.model.Project(SampleRate=rate).sampleRate, rate);
        end

        function validatorMatchesSupportedRatesConstant(testCase)
            % The sampleRate validator lists rates by hand; it must match the constant.
            for r = bpm.model.Project.SUPPORTED_SAMPLE_RATES
                testCase.verifyEqual(bpm.model.Project(SampleRate=r).sampleRate, r);
            end
            % Common rates NOT in the constant must be rejected by the validator.
            for r = setdiff([8000 16000 22050 32000 44100 48000 88200 96000 192000], ...
                    bpm.model.Project.SUPPORTED_SAMPLE_RATES)
                testCase.verifyError(@() bpm.model.Project(SampleRate=r), "MATLAB:validators:mustBeMember");
            end
        end

        function rejectsUnsupportedSampleRates(testCase)
            for bad = [22050 44101 0]
                testCase.verifyError(@() bpm.model.Project(SampleRate=bad), "MATLAB:validators:mustBeMember");
            end
        end

        function lengthMustBePositiveAndFinite(testCase)
            testCase.verifyError(@() bpm.model.Project(LengthBeats=0), "MATLAB:validators:mustBePositive");
            testCase.verifyError(@() bpm.model.Project(LengthBeats=Inf), "MATLAB:validators:mustBeFinite");
        end

        function formatVersionIsReadOnly(testCase)
            p = bpm.model.Project();
            function assignVersion()
                p.formatVersion = 2;
            end
            testCase.verifyError(@assignVersion, "MATLAB:class:SetProhibited");
        end

        function addTrackAssignsSequentialIds(testCase)
            p = bpm.model.Project();
            p = p.addTrack(bpm.model.Track(Name="A")).addTrack(bpm.model.Track(Name="B"));
            testCase.verifyEqual([p.tracks.id], ["trk-0001", "trk-0002"]);
            testCase.verifyEqual([p.tracks.name], ["A", "B"]);
        end

        function addTrackKeepsAGivenId(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Id="drums"));
            testCase.verifyEqual(p.tracks.id, "drums");
        end

        function idsAreNeverReused(testCase)
            p = bpm.model.Project();
            p = p.addTrack(bpm.model.Track()).addTrack(bpm.model.Track());   % trk-0001, trk-0002
            p = p.removeTrack("trk-0002");
            p = p.addTrack(bpm.model.Track());
            testCase.verifyEqual([p.tracks.id], ["trk-0001", "trk-0003"]);
        end

        function newIdsSkipHandMadeTrkIds(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Id="trk-0007"));
            p = p.addTrack(bpm.model.Track());
            testCase.verifyEqual(p.tracks(2).id, "trk-0008");
        end

        function duplicateIdsAreRejected(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Id="trk-0001"));
            testCase.verifyError(@() p.addTrack(bpm.model.Track(Id="trk-0001")), ...
                "bpm:model:Project:duplicateTrackId");
        end

        function tracksAssignedDirectlyAreChecked(testCase)
            p = bpm.model.Project();
            function assignDuplicates()
                p.tracks = [bpm.model.Track(Id="x"), bpm.model.Track(Id="x")];
            end
            function assignMissingId()
                p.tracks = bpm.model.Track();
            end
            testCase.verifyError(@assignDuplicates, "bpm:model:Project:duplicateTrackId");
            testCase.verifyError(@assignMissingId, "bpm:model:Project:missingTrackId");
        end

        function trackLookupAndHasTrack(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Name="Lead"));
            testCase.verifyEqual(p.track("trk-0001").name, "Lead");
            testCase.verifyTrue(p.hasTrack("trk-0001"));
            testCase.verifyFalse(p.hasTrack("trk-0099"));
            testCase.verifyFalse(bpm.model.Project().hasTrack("trk-0001"));
        end

        function missingTrackErrors(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track());
            testCase.verifyError(@() p.track("nope"), "bpm:model:Project:trackNotFound");
            testCase.verifyError(@() p.removeTrack("nope"), "bpm:model:Project:trackNotFound");
            testCase.verifyError(@() p.setTrack(bpm.model.Track(Id="nope")), "bpm:model:Project:trackNotFound");
            testCase.verifyError(@() bpm.model.Project().track("trk-0001"), "bpm:model:Project:trackNotFound");
        end

        function editTrackThroughSetTrack(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Name="A")).addTrack(bpm.model.Track(Name="B"));
            t = p.track("trk-0002");
            t.pan = -0.5;
            p = p.setTrack(t);
            testCase.verifyEqual(p.track("trk-0002").pan, -0.5);
            testCase.verifyEqual(p.tracks(2).name, "B", "Track order must not change.");
        end

        function removeTrackKeepsOrder(testCase)
            p = bpm.model.Project();
            for name = ["A", "B", "C"]
                p = p.addTrack(bpm.model.Track(Name=name));
            end
            p = p.removeTrack("trk-0002");
            testCase.verifyEqual([p.tracks.name], ["A", "C"]);
        end

        function methodsDoNotChangeTheOriginal(testCase)
            original = bpm.model.Project();
            withTrack = original.addTrack(bpm.model.Track());
            testCase.verifySize(original.tracks, [1 0]);
            testCase.verifySize(withTrack.tracks, [1 1]);

            removed = withTrack.removeTrack("trk-0001");
            testCase.verifySize(withTrack.tracks, [1 1]);
            testCase.verifySize(removed.tracks, [1 0]);
        end

        function masterEffectsHoldPluginSpecs(testCase)
            p = bpm.model.Project();
            p.masterEffects(end + 1) = bpm.model.PluginSpec("bpm.effects.Reverb", struct("mix", 0.2));
            testCase.verifyEqual(p.masterEffects.type, "bpm.effects.Reverb");
        end
    end
end
