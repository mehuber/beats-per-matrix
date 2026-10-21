classdef Project
    %PROJECT A whole song: its tracks, master effects, and global settings.
    %   This is the top of the data model. Everything the app knows about a song
    %   lives in a Project, and saving a project (task V1-18) saves exactly this.
    %
    %       name            song title
    %       sampleRate      audio samples per second: 44100, 48000 or 96000
    %       lengthBeats     song length in beats (1 beat = 1 quarter note)
    %       tracks          the tracks, in mixer order (read-only; see below)
    %       masterEffects   effects applied to the final mix (PluginSpec row)
    %       masterVolumeDb  overall level change in decibels
    %
    %   Tempo and time signature are added in task V1-02.
    %
    %   The track list can only be changed through methods, so the project can
    %   guarantee that no two tracks share an id, and that an automatic id
    %   ("trk-0001", ...) is never handed out twice, even after its track is
    %   deleted. (addTrack does accept a hand-made or re-added id, such as a cut
    %   track pasted back, as long as no current track uses it.)
    %       p = bpm.model.Project(Name="Demo");
    %       p = p.addTrack(bpm.model.Track(Name="Lead"));   % gets id "trk-0001"
    %       lead = p.track("trk-0001");                     % a copy of the track
    %       lead.pan = -0.5;
    %       p = p.setTrack(lead);                           % put the edited copy back
    %       p = p.removeTrack("trk-0001");
    %
    %   This is a value class: every method returns a modified COPY and leaves
    %   the original untouched. That makes undo easy: keep the old copy.

    % Constant properties are fixed values that belong to the class itself;
    % read them as bpm.model.Project.FORMAT_VERSION.
    properties (Constant)
        % File-format version written into saved projects (PLAN.md section 4).
        FORMAT_VERSION = 1

        % Sample rates the engine supports (PLAN.md decision 8).
        SUPPORTED_SAMPLE_RATES = [44100 48000 96000]
    end

    properties (SetAccess = private)
        % SetAccess = private: code outside this class can READ these but not change
        % them. The project loader (V1-18) will restore them through a method of
        % this class.

        % File-format version of this project.
        formatVersion (1,1) double = 1

        % The tracks, in mixer order. Change them with addTrack / setTrack /
        % removeTrack, which keep every id unique. Track.empty(1, 0) is a row with
        % no tracks in it (every class has a built-in "empty" method).
        tracks (1,:) bpm.model.Track = bpm.model.Track.empty(1, 0)

        % Number used for the next automatic track id ("trk-0001", "trk-0002", ...).
        % It only ever goes up, so an automatic id is never handed out twice, even
        % after its track is deleted. It is saved with the project so this still
        % holds after reloading.
        nextTrackNumber (1,1) double {mustBeInteger, mustBePositive} = 1
    end

    properties
        name (1,1) string {mustBeNonmissing} = "Untitled"

        % mustBeSupportedSampleRate is a small validation function at the bottom of
        % this file. (MATLAB won't accept a constant as a validator *argument*, as in
        % mustBeMember(sampleRate, Project.SUPPORTED_SAMPLE_RATES), but a validator
        % function may read the constant, so the list lives in one place.)
        sampleRate (1,1) double {mustBeReal, mustBeSupportedSampleRate} = 44100

        lengthBeats (1,1) double {mustBePositive, mustBeFinite} = 16
        masterEffects (1,:) bpm.model.PluginSpec = bpm.model.PluginSpec.empty(1, 0)
        masterVolumeDb (1,1) double {mustBeReal, mustBeNonNan, mustBeLessThanOrEqual(masterVolumeDb, 6)} = 0
    end

    methods
        function obj = Project(options)
            %PROJECT Create a project. All settings are optional name-value arguments.
            % An arguments block lists a function's inputs and their defaults.
            % "options.Name" declares an optional name-value argument, which a caller
            % writes as Project(Name="Demo"); any that are left out get the default.
            arguments
                options.Name = "Untitled"
                options.SampleRate = 44100
                options.LengthBeats = 16
                options.MasterVolumeDb = 0
            end
            % Not type-checked here: the property validators check each value, so
            % every rule lives in one place (the properties block).
            obj.name = options.Name;
            obj.sampleRate = options.SampleRate;
            obj.lengthBeats = options.LengthBeats;
            obj.masterVolumeDb = options.MasterVolumeDb;
        end

        function obj = addTrack(obj, track)
            %ADDTRACK Return a copy with TRACK added at the end.
            %   If the track has no id, a new unique one ("trk-0001", ...) is assigned.
            %   A track whose id is already in the project is rejected.
            arguments
                obj (1,1) bpm.model.Project
                track (1,1) bpm.model.Track
            end
            if track.id == ""
                % A function can return several outputs; the square brackets on the
                % left catch them in order (the id, then the updated counter).
                [track.id, obj.nextTrackNumber] = obj.newTrackId();
            else
                if obj.hasTrack(track.id)
                    error("bpm:model:Project:duplicateTrackId", ...
                        "This project already has a track with id ""%s"".", track.id);
                end
                % A hand-made (or re-added) "trk-0007" moves the counter past 7, so
                % that id is never handed out again even after the track is deleted.
                % max() matters: re-adding an OLD id must never move the counter back.
                n = trackNumbers(track.id);
                if ~isnan(n)
                    obj.nextTrackNumber = max(obj.nextTrackNumber, n + 1);
                end
            end
            % end + 1 is "one past the last element", so this appends the track.
            obj.tracks(end + 1) = track;
        end

        function obj = removeTrack(obj, id)
            %REMOVETRACK Return a copy without the track that has this ID.
            arguments
                obj (1,1) bpm.model.Project
                id (1,1) string {mustBeNonmissing}
            end
            obj.tracks(obj.indexOf(id)) = [];   % assigning [] deletes that element
        end

        function track = track(obj, id)
            %TRACK Return (a copy of) the track that has this ID.
            arguments
                obj (1,1) bpm.model.Project
                id (1,1) string {mustBeNonmissing}
            end
            track = obj.tracks(obj.indexOf(id));
        end

        function obj = setTrack(obj, track)
            %SETTRACK Return a copy where the track with TRACK's id is replaced by TRACK.
            %   Typical edit: t = p.track(id); change t; p = p.setTrack(t).
            arguments
                obj (1,1) bpm.model.Project
                track (1,1) bpm.model.Track
            end
            obj.tracks(obj.indexOf(track.id)) = track;
        end

        function tf = hasTrack(obj, id)
            %HASTRACK True if a track with this ID exists.
            arguments
                obj (1,1) bpm.model.Project
                id (1,1) string {mustBeNonmissing}
            end
            tf = any(trackIds(obj.tracks) == id);
        end
    end

    % Private methods can only be called from inside this class.
    methods (Access = private)
        function index = indexOf(obj, id)
            % Position of the track with this id; error if there isn't one.
            % find(mask, 1) gives the position of the first true element.
            index = find(trackIds(obj.tracks) == id, 1);
            if isempty(index)
                error("bpm:model:Project:trackNotFound", "No track with id ""%s"".", id);
            end
        end

        function [id, nextNumber] = newTrackId(obj)
            % The next automatic id comes from the counter. If that id is somehow
            % taken already (e.g. a very long hand-made id the counter ignores), keep
            % counting until a free one turns up, so ids are always unique.
            number = obj.nextTrackNumber;
            id = sprintf("trk-%04d", number);   % %04d pads with zeros: 1 -> "0001"
            while obj.hasTrack(id)
                number = number + 1;
                id = sprintf("trk-%04d", number);
            end
            nextNumber = number + 1;
        end
    end
end

function mustBeSupportedSampleRate(rate)
    % Validation function for Project.sampleRate. A validator is any function
    % that errors when the value is not allowed and does nothing when it is.
    mustBeMember(rate, bpm.model.Project.SUPPORTED_SAMPLE_RATES);
end

function ids = trackIds(tracks)
    % All track ids as a string row. [tracks.id] gathers the id of every track;
    % wrapping it in string() keeps the result a string even when there are no tracks.
    ids = reshape(string([tracks.id]), 1, []);
end

function n = trackNumbers(ids)
    % The number inside each automatic id ("trk-0042" -> 42), or NaN for ids in
    % any other form. "trk-" + digitsPattern(1, 15) is a text pattern meaning
    % "trk-" followed by 1 to 15 digits, and matches() is true only when the WHOLE
    % id fits it, so odd ids like "trk-Inf", "trk-1e20" or "trk-0x10" are ignored.
    % (15 digits is the most a double holds exactly; ids never get that long.)
    n = NaN(size(ids));
    isAuto = matches(ids, "trk-" + digitsPattern(1, 15));
    % ids(isAuto) keeps only the elements where isAuto is true ("logical indexing").
    n(isAuto) = str2double(extractAfter(ids(isAuto), "trk-"));
end
