classdef ModelProjectTest < BpmTestCase
    % Tests for bpm.model.Project.
    %
    % Several tests define a small function INSIDE the test (a "nested function")
    % that tries an assignment, then check that calling it throws the expected
    % error. That's needed because verifyError takes a function to call, and an
    % assignment like p.formatVersion = 2 is a statement, not a function.
    %
    % Other MATLAB features used below:
    %   @() expr        makes a small unnamed function out of an expression, for
    %                   verifyError to call.
    %   [p.tracks.id]   collects the id of every track into one string row.

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
            testCase.verifyEqual(p.nextTrackNumber, 1);
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

        function supportedRatesAreExactlyThePlannedOnes(testCase)
            % PLAN.md decision 8. (Whether the validator reads this constant, rather
            % than its own copy of the list, can't be tested without editing the
            % class; Project.m keeps a single list on purpose.)
            testCase.verifyEqual(bpm.model.Project.SUPPORTED_SAMPLE_RATES, [44100 48000 96000]);
        end

        function onlySupportedRatesAreAccepted(testCase)
            for r = [0 8000 16000 22050 32000 44101 88200 192000]
                testCase.verifyError(@() bpm.model.Project(SampleRate=r), "MATLAB:validators:mustBeMember", ...
                    "Rate " + r);
            end
        end

        function sampleRateIsCheckedOnLaterAssignmentToo(testCase)
            p = bpm.model.Project();
            function assignBadRate()
                p.sampleRate = 22050;
            end
            testCase.verifyError(@assignBadRate, "MATLAB:validators:mustBeMember");
        end

        function sampleRateMustBeReal(testCase)
            testCase.verifyError(@() bpm.model.Project(SampleRate=complex(44100, 0)), "MATLAB:validators:mustBeReal");
        end

        function lengthMustBePositiveAndFinite(testCase)
            testCase.verifyError(@() bpm.model.Project(LengthBeats=0), "MATLAB:validators:mustBePositive");
            testCase.verifyError(@() bpm.model.Project(LengthBeats=Inf), "MATLAB:validators:mustBeFinite");
        end

        function masterVolumeAllowsSilenceButNotOverSixDb(testCase)
            testCase.verifyEqual(bpm.model.Project(MasterVolumeDb=-Inf).masterVolumeDb, -Inf);
            testCase.verifyEqual(bpm.model.Project(MasterVolumeDb=6).masterVolumeDb, 6);
            testCase.verifyError(@() bpm.model.Project(MasterVolumeDb=6.5), "MATLAB:validators:mustBeLessThanOrEqual");
            testCase.verifyError(@() bpm.model.Project(MasterVolumeDb=NaN), "MATLAB:validators:mustBeNonNan");
        end

        function nameMustNotBeMissing(testCase)
            testCase.verifyError(@() bpm.model.Project(Name=string(missing)), "MATLAB:validators:mustBeNonmissing");
        end

        function formatVersionIsReadOnly(testCase)
            p = bpm.model.Project();
            function assignVersion()
                p.formatVersion = 2;
            end
            testCase.verifyError(@assignVersion, "MATLAB:class:SetProhibited");
        end

        function trackCounterIsReadableButReadOnly(testCase)
            % Public to read so it gets saved with the project (V1-18), but only the
            % class itself may change it.
            p = bpm.model.Project().addTrack(bpm.model.Track()).addTrack(bpm.model.Track());
            testCase.verifyEqual(p.nextTrackNumber, 3);
            function assignCounter()
                p.nextTrackNumber = 1;
            end
            testCase.verifyError(@assignCounter, "MATLAB:class:SetProhibited");
        end

        function tracksCanOnlyBeChangedThroughMethods(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Name="A"));
            function assignWholeList()
                p.tracks = bpm.model.Track(Id="x");
            end
            function editInPlace()
                p.tracks(1).pan = 0.5;
            end
            testCase.verifyError(@assignWholeList, "MATLAB:class:SetProhibited");
            testCase.verifyError(@editInPlace, "MATLAB:class:SetProhibited");
            testCase.verifyEqual(p.tracks.pan, 0, "The failed edit must not have changed anything.");
        end

        function projectsBuiltTheSameWayAreEqual(testCase)
            build = @() bpm.model.Project(Name="Same").addTrack(bpm.model.Track(Name="A")).addTrack(bpm.model.Track());
            testCase.verifyEqual(build(), build());
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
            testCase.verifyEqual(p.nextTrackNumber, 1, "A non-trk id must not move the counter.");
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

        function handMadeTrkIdsAreNotReusedAfterDeletion(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Id="trk-0001"));
            p = p.removeTrack("trk-0001").addTrack(bpm.model.Track());
            testCase.verifyEqual(p.tracks.id, "trk-0002");
        end

        function reAddingAnOldTrackDoesNotLowerTheCounter(testCase)
            % E.g. cut and paste: an old track comes back with its old id. The counter
            % must stay where it is, or a deleted id would be handed out again.
            p = bpm.model.Project();
            for k = 1:3
                p = p.addTrack(bpm.model.Track());                  % trk-0001..0003
            end
            first = p.track("trk-0001");
            p = p.removeTrack("trk-0001").removeTrack("trk-0003");
            p = p.addTrack(first);                                  % trk-0001 is back
            testCase.verifyEqual(p.nextTrackNumber, 4);
            p = p.addTrack(bpm.model.Track());
            testCase.verifyEqual(p.tracks(end).id, "trk-0004", "trk-0003 was deleted and must not be reused.");
        end

        function automaticIdFormIsTrkPlusOneTo15Digits(testCase)
            % Ids that count (they move the counter past their number):
            counted = ["trk-5", "trk-12345", "trk-999999999", "trk-123456789012345"];
            expectedNext = [6, 12346, 1000000000, 123456789012346];
            for k = 1:numel(counted)
                p = bpm.model.Project().addTrack(bpm.model.Track(Id=counted(k)));
                testCase.verifyEqual(p.nextTrackNumber, expectedNext(k), "Id " + counted(k));
            end
            % Ids that don't count (counter stays at 1):
            for odd = ["trk-Inf", "trk-1e20", "trk-0x10", "trk-1234567890123456", "trk-", ...
                    "trk-3.5", "trk--4", "TRK-0004", "drums"]
                p = bpm.model.Project().addTrack(bpm.model.Track(Id=odd));
                testCase.verifyEqual(p.nextTrackNumber, 1, "Id " + odd);
            end
        end

        function oddIdsDoNotDisturbAutomaticIds(testCase)
            p = bpm.model.Project();
            for odd = ["trk-Inf", "trk-1e20", "trk-0x10", "trk-", "drums"]
                p = p.addTrack(bpm.model.Track(Id=odd));
            end
            p = p.addTrack(bpm.model.Track());
            testCase.verifyEqual(p.tracks(end).id, "trk-0001");
        end

        function automaticIdsNeverClashWithIgnoredHandMadeIds(testCase)
            % A 16-digit id is too long to move the counter, but the generated id
            % must still skip it rather than duplicate it.
            p = bpm.model.Project().addTrack(bpm.model.Track(Id="trk-1000000000000000"));   % 16 digits
            p = p.addTrack(bpm.model.Track(Id="trk-999999999999999"));                      % 15 digits
            p = p.addTrack(bpm.model.Track());
            testCase.verifyEqual(p.tracks(end).id, "trk-1000000000000001");
            testCase.verifyEqual(numel(unique([p.tracks.id])), numel(p.tracks));
        end

        function automaticIdsSkipSeveralTakenIdsInARow(testCase)
            p = bpm.model.Project();
            for id = ["trk-1000000000000000", "trk-1000000000000001", "trk-999999999999999"]
                p = p.addTrack(bpm.model.Track(Id=id));
            end
            p = p.addTrack(bpm.model.Track());
            testCase.verifyEqual(p.tracks(end).id, "trk-1000000000000002");
            testCase.verifyEqual(numel(unique([p.tracks.id])), numel(p.tracks));
        end

        function trackMethodsTakeExactlyOneTrack(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track());
            two = [bpm.model.Track(Id="a"), bpm.model.Track(Id="b")];
            none = bpm.model.Track.empty;
            testCase.verifyError(@() p.addTrack(two), "MATLAB:validation:IncompatibleSize");
            testCase.verifyError(@() p.addTrack(none), "MATLAB:validation:IncompatibleSize");
            testCase.verifyError(@() p.setTrack(two), "MATLAB:validation:IncompatibleSize");
            testCase.verifyError(@() p.setTrack(none), "MATLAB:validation:IncompatibleSize");
        end

        function trackIdsAreCaseSensitive(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Id="drums"));
            testCase.verifyFalse(p.hasTrack("DRUMS"));
            testCase.verifyError(@() p.track("DRUMS"), "bpm:model:Project:trackNotFound");
            testCase.verifySize(p.addTrack(bpm.model.Track(Id="DRUMS")).tracks, [1 2]);
        end

        function idsKeepWorkingPast9999(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Id="trk-9999"));
            p = p.addTrack(bpm.model.Track()).addTrack(bpm.model.Track());
            testCase.verifyEqual([p.tracks(2:3).id], ["trk-10000", "trk-10001"]);
        end

        function duplicateIdsAreRejectedWithTheIdInTheMessage(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Id="drums"));
            testCase.verifyError(@() p.addTrack(bpm.model.Track(Id="drums")), ...
                "bpm:model:Project:duplicateTrackId");
            try
                p.addTrack(bpm.model.Track(Id="drums"));
            catch err
                testCase.verifySubstring(err.message, """drums""");
            end
        end

        function duplicateCheckLooksAtEveryTrack(testCase)
            p = bpm.model.Project();
            for name = ["A", "B", "C"]
                p = p.addTrack(bpm.model.Track(Name=name));
            end
            testCase.verifyError(@() p.addTrack(bpm.model.Track(Id="trk-0002")), ...
                "bpm:model:Project:duplicateTrackId", "A clash with a middle track must be found.");
        end

        function trackLookupAndHasTrack(testCase)
            p = bpm.model.Project();
            for name = ["Lead", "Bass", "Drums"]
                p = p.addTrack(bpm.model.Track(Name=name));
            end
            testCase.verifyEqual(p.track("trk-0001").name, "Lead");
            testCase.verifyEqual(p.track("trk-0002").name, "Bass");
            testCase.verifyEqual(p.track("trk-0003").name, "Drums");
            testCase.verifyTrue(p.hasTrack("trk-0002"));
            testCase.verifyFalse(p.hasTrack("trk-0099"));
            testCase.verifyFalse(bpm.model.Project().hasTrack("trk-0001"));
        end

        function missingTrackErrors(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track());
            testCase.verifyError(@() p.track("nope"), "bpm:model:Project:trackNotFound");
            testCase.verifyError(@() p.removeTrack("nope"), "bpm:model:Project:trackNotFound");
            testCase.verifyError(@() p.setTrack(bpm.model.Track(Id="nope")), "bpm:model:Project:trackNotFound");
            testCase.verifyError(@() p.setTrack(bpm.model.Track()), "bpm:model:Project:trackNotFound");
            testCase.verifyError(@() bpm.model.Project().track("trk-0001"), "bpm:model:Project:trackNotFound");
            try
                p.track("nope");
            catch err
                testCase.verifySubstring(err.message, """nope""", "The message should name the id.");
            end
        end

        function missingIdLookupsGiveAClearError(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track());
            m = string(missing);
            testCase.verifyError(@() p.track(m), "MATLAB:validators:mustBeNonmissing");
            testCase.verifyError(@() p.removeTrack(m), "MATLAB:validators:mustBeNonmissing");
            testCase.verifyError(@() p.hasTrack(m), "MATLAB:validators:mustBeNonmissing");
        end

        function editTrackThroughSetTrack(testCase)
            p = bpm.model.Project();
            for name = ["A", "B", "C"]
                p = p.addTrack(bpm.model.Track(Name=name));
            end
            t = p.track("trk-0002");
            t.pan = -0.5;
            p = p.setTrack(t);
            testCase.verifyEqual([p.tracks.pan], [0 -0.5 0], "Only the middle track should change.");
            testCase.verifyEqual([p.tracks.name], ["A", "B", "C"], "Track order must not change.");
        end

        function editingAReturnedTrackDoesNotChangeTheProject(testCase)
            p = bpm.model.Project().addTrack(bpm.model.Track(Name="A"));
            t = p.track("trk-0001");
            t.name = "Changed";
            testCase.verifyEqual(p.track("trk-0001").name, "A");

            p2 = p.setTrack(t);
            testCase.verifyEqual(p.track("trk-0001").name, "A", "setTrack must return a copy.");
            testCase.verifyEqual(p2.track("trk-0001").name, "Changed");
        end

        function removeTrackRemovesOnlyThatTrack(testCase)
            p = bpm.model.Project();
            for name = ["A", "B", "C"]
                p = p.addTrack(bpm.model.Track(Name=name));
            end
            p = p.removeTrack("trk-0002");
            testCase.verifyEqual([p.tracks.name], ["A", "C"]);
            testCase.verifyEqual([p.tracks.id], ["trk-0001", "trk-0003"]);
        end

        function methodsDoNotChangeTheOriginal(testCase)
            original = bpm.model.Project();
            withTrack = original.addTrack(bpm.model.Track());
            testCase.verifySize(original.tracks, [1 0]);
            testCase.verifyEqual(original.nextTrackNumber, 1);
            testCase.verifySize(withTrack.tracks, [1 1]);

            removed = withTrack.removeTrack("trk-0001");
            testCase.verifySize(withTrack.tracks, [1 1]);
            testCase.verifySize(removed.tracks, [1 0]);
        end

        function masterEffectsHoldPluginSpecs(testCase)
            p = bpm.model.Project();
            p.masterEffects(end + 1) = bpm.model.PluginSpec("bpm.effects.Reverb", struct("mix", 0.2));
            testCase.verifyEqual(p.masterEffects.type, "bpm.effects.Reverb");
            % (1,:) turns a column of specs into a row.
            p.masterEffects = [bpm.model.PluginSpec("bpm.a.B"); bpm.model.PluginSpec("bpm.a.C")];
            testCase.verifySize(p.masterEffects, [1 2]);
        end
    end
end
