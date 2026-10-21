classdef Project
    %PROJECT A whole song: its tracks, master effects, and global settings.
    %   This is the top of the data model. Everything the app knows about a song
    %   lives in a Project, and saving a project (task V1-18) saves exactly this.
    %
    %       name            song title
    %       sampleRate      audio samples per second: 44100, 48000 or 96000
    %       lengthBeats     song length in beats (1 beat = 1 quarter note)
    %       tracks          the tracks, in mixer order (a row of Track objects)
    %       masterEffects   effects applied to the final mix (PluginSpec row)
    %       masterVolumeDb  overall loudness change in decibels
    %
    %   Tempo and time signature are added in task V1-02.
    %
    %   Example:
    %       p = bpm.model.Project(Name="Demo");
    %       p = p.addTrack(bpm.model.Track(Name="Lead"));   % gets id "trk-0001"
    %       lead = p.track("trk-0001");
    %       lead.pan = -0.5;
    %       p = p.setTrack(lead);                           % put the edited copy back
    %
    %   This is a value class: every method returns a modified COPY and leaves
    %   the original untouched. That makes undo easy: keep the old copy.

    properties (Constant)
        % File-format version written into saved projects (PLAN.md section 4).
        FORMAT_VERSION = 1

        % Sample rates the engine supports (PLAN.md decision 8).
        SUPPORTED_SAMPLE_RATES = [44100 48000 96000]
    end

    properties (SetAccess = private)
        % Read-only from outside: only the class itself (and later the loader) sets it.
        formatVersion (1,1) double = 1
    end

    properties
        name (1,1) string = "Untitled"
        % The list is written out because MATLAB does not allow validators to refer to
        % class constants. A test checks it matches SUPPORTED_SAMPLE_RATES.
        sampleRate (1,1) double {mustBeMember(sampleRate, [44100 48000 96000])} = 44100
        lengthBeats (1,1) double {mustBePositive, mustBeFinite} = 16
        tracks (1,:) bpm.model.Track = bpm.model.Track.empty(1, 0)
        masterEffects (1,:) bpm.model.PluginSpec = bpm.model.PluginSpec.empty(1, 0)
        masterVolumeDb (1,1) double {mustBeReal, mustBeNonNan, mustBeLessThanOrEqual(masterVolumeDb, 6)} = 0
    end

    properties (Access = private)
        % Next number for an automatic track id. It only ever goes up, so a
        % deleted track's id is never handed to a new track.
        nextTrackNumber (1,1) double = 1
    end

    methods
        function obj = Project(options)
            %PROJECT Create a project. All settings are optional name-value arguments.
            arguments
                options.Name = "Untitled"
                options.SampleRate = 44100
                options.LengthBeats = 16
                options.MasterVolumeDb = 0
            end
            % Not type-checked here: the property validators check each value.
            obj.name = options.Name;
            obj.sampleRate = options.SampleRate;
            obj.lengthBeats = options.LengthBeats;
            obj.masterVolumeDb = options.MasterVolumeDb;
        end

        function obj = addTrack(obj, track)
            %ADDTRACK Return a copy with TRACK added at the end.
            %   If the track has no id, a new unique one ("trk-0001", ...) is assigned.
            arguments
                obj (1,1) bpm.model.Project
                track (1,1) bpm.model.Track
            end
            if track.id == ""
                [track.id, obj.nextTrackNumber] = obj.newTrackId();
            end
            obj.tracks(end + 1) = track;   % set.tracks checks the id is unique
        end

        function obj = removeTrack(obj, id)
            %REMOVETRACK Return a copy without the track that has this ID.
            arguments
                obj (1,1) bpm.model.Project
                id (1,1) string
            end
            obj.tracks(obj.indexOf(id)) = [];
        end

        function track = track(obj, id)
            %TRACK Return (a copy of) the track that has this ID.
            arguments
                obj (1,1) bpm.model.Project
                id (1,1) string
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
                id (1,1) string
            end
            tf = any(trackIds(obj.tracks) == id);
        end

        function obj = set.tracks(obj, value)
            % Every track needs an id, and no two tracks may share one.
            ids = trackIds(value);
            if any(ids == "")
                error("bpm:model:Project:missingTrackId", ...
                    "Every track in a project needs an id. Use addTrack to assign one automatically.");
            end
            if numel(unique(ids)) < numel(ids)
                error("bpm:model:Project:duplicateTrackId", ...
                    "Track ids must be unique. Duplicated: %s.", strjoin(unique(ids(duplicated(ids))), ", "));
            end
            obj.tracks = value;
        end
    end

    methods (Access = private)
        function index = indexOf(obj, id)
            % Position of the track with this id; error if there isn't one.
            index = find(trackIds(obj.tracks) == id, 1);
            if isempty(index)
                error("bpm:model:Project:trackNotFound", "No track with id ""%s"".", id);
            end
        end

        function [id, nextNumber] = newTrackId(obj)
            % Pick the next unused "trk-NNNN" id. Also look at existing ids, in case
            % tracks with hand-made "trk-..." ids were added directly.
            % Take ids that start with "trk-", strip that prefix, and read the rest as a
            % number. Anything that isn't a whole number (e.g. "trk-abc") becomes NaN
            % or a fraction and is ignored.
            ids = trackIds(obj.tracks);
            used = str2double(erase(ids(startsWith(ids, "trk-")), "trk-"));
            used = used(~isnan(used) & used == round(used));
            number = max([obj.nextTrackNumber, used(:)' + 1]);
            id = sprintf("trk-%04d", number);   % %04d pads with zeros: 1 -> "0001"
            nextNumber = number + 1;
        end
    end
end

function ids = trackIds(tracks)
    % All track ids as a string row. [tracks.id] gathers the id of every track;
    % wrapping it in string() keeps the result a string even when there are no tracks.
    ids = string([tracks.id]);
    ids = reshape(ids, 1, []);
end

function tf = duplicated(values)
    % True for each element that also appears earlier in VALUES.
    [~, firstIndex] = unique(values, "stable");
    tf = true(size(values));
    tf(firstIndex) = false;
end
