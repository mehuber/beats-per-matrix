classdef Track
    %TRACK One track of a song: an instrument, its effects, and its mixer settings.
    %   Like a channel strip on a mixing desk, a track has:
    %
    %       instrument  the sound source (a PluginSpec), or empty for none
    %       effects     effects applied in order, left to right (PluginSpec row)
    %       volumeDb    loudness change in decibels (0 = unchanged, -6 = about half)
    %       pan         left/right position: -1 = full left, 0 = center, +1 = full right
    %       mute, solo  mute silences this track; solo silences all the OTHER tracks
    %
    %   The notes the track plays (regions) arrive in task V1-03.
    %
    %   Example:
    %       synth = bpm.model.PluginSpec("bpm.instruments.Synth");
    %       t = bpm.model.Track(Name="Lead", Instrument=synth, Pan=0.25);
    %       t = t.addEffect(bpm.model.PluginSpec("bpm.effects.Delay"));
    %
    %   Shortcut: plain text is turned into a PluginSpec automatically, because
    %   MATLAB converts a value to a property's class by calling that class's
    %   constructor. So Track(Instrument="bpm.instruments.Synth") also works.
    %
    %   This is a value class: methods return a modified copy, so write
    %   t = t.addEffect(...), not just t.addEffect(...).

    properties
        % Stable unique id within a project, e.g. "trk-0001". Usually left empty
        % and filled in by Project.addTrack.
        id (1,1) string = ""

        name (1,1) string = "Track"

        % mustBeScalarOrEmpty: either exactly one PluginSpec or none at all.
        instrument bpm.model.PluginSpec {mustBeScalarOrEmpty} = bpm.model.PluginSpec.empty

        % (1,:) means "a row": zero or more specs side by side.
        effects (1,:) bpm.model.PluginSpec = bpm.model.PluginSpec.empty(1, 0)

        % -Inf dB is allowed and means total silence. +6 dB is the upper limit.
        volumeDb (1,1) double {mustBeReal, mustBeNonNan, mustBeLessThanOrEqual(volumeDb, 6)} = 0

        pan (1,1) double {mustBeInRange(pan, -1, 1)} = 0

        mute (1,1) logical = false
        solo (1,1) logical = false
    end

    methods
        function obj = Track(options)
            %TRACK Create a track. All settings are optional name-value arguments.
            arguments
                options.Id = ""
                options.Name = "Track"
                options.Instrument = bpm.model.PluginSpec.empty
                options.Effects = bpm.model.PluginSpec.empty(1, 0)
                options.VolumeDb = 0
                options.Pan = 0
                options.Mute = false
                options.Solo = false
            end
            % The arguments above are deliberately not type-checked: assigning them
            % to the properties below runs the property validators, so every rule
            % lives in exactly one place (the properties block).
            obj.id = options.Id;
            obj.name = options.Name;
            obj.instrument = options.Instrument;
            obj.effects = options.Effects;
            obj.volumeDb = options.VolumeDb;
            obj.pan = options.Pan;
            obj.mute = options.Mute;
            obj.solo = options.Solo;
        end

        function obj = addEffect(obj, spec)
            %ADDEFFECT Return a copy with SPEC added at the end of the effect chain.
            arguments
                obj (1,1) bpm.model.Track
                spec (1,1) bpm.model.PluginSpec
            end
            obj.effects(end + 1) = spec;
        end

        function obj = setEffect(obj, index, spec)
            %SETEFFECT Return a copy with effect number INDEX replaced by SPEC.
            arguments
                obj (1,1) bpm.model.Track
                index (1,1) double {mustBeInteger, mustBePositive}
                spec (1,1) bpm.model.PluginSpec
            end
            obj.checkEffectIndex(index);
            obj.effects(index) = spec;
        end

        function obj = removeEffect(obj, index)
            %REMOVEEFFECT Return a copy with effect number INDEX taken out of the chain.
            arguments
                obj (1,1) bpm.model.Track
                index (1,1) double {mustBeInteger, mustBePositive}
            end
            obj.checkEffectIndex(index);
            obj.effects(index) = [];   % assigning [] deletes that element
        end
    end

    methods (Access = private)
        function checkEffectIndex(obj, index)
            if index > numel(obj.effects)
                error("bpm:model:Track:effectIndexOutOfRange", ...
                    "Track ""%s"" has %d effect(s); there is no effect %d.", ...
                    obj.name, numel(obj.effects), index);
            end
        end
    end
end
