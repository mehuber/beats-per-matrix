classdef PluginSpec
    %PLUGINSPEC A saved description of an instrument or effect (not the live object).
    %   A PluginSpec records WHICH plugin to use and HOW it is set up:
    %
    %       type    full class name, e.g. "bpm.effects.Delay"
    %       params  struct of settings, e.g. struct("timeMs", 250, "mix", 0.3)
    %       bypass  true = keep the plugin in the chain but skip it
    %
    %   The engine turns a spec into a working plugin object at render time
    %   (bpm.plugins.create, task V1-06). Keeping only this small description in
    %   the project means a project can be saved as plain JSON (PLAN.md D2).
    %
    %   Example:
    %       spec = bpm.model.PluginSpec("bpm.effects.LowPass", struct("cutoffHz", 1800));
    %       spec = spec.withParam("q", 0.7);   % methods return a modified COPY
    %
    %   This is a value class: assigning it (b = a) makes an independent copy,
    %   so changing b never changes a.

    properties
        % Full class name of the plugin. Checked by set.type below.
        type (1,1) string = ""

        % Plugin settings. Each field must be JSON-friendly (see mustBeJsonFriendly).
        params (1,1) struct = struct()

        % When true the engine passes audio through this plugin unchanged.
        bypass (1,1) logical = false
    end

    methods
        function obj = PluginSpec(type, params, options)
            %PLUGINSPEC Create a spec. TYPE is required; PARAMS defaults to no settings.
            arguments
                type (1,1) string
                params (1,1) struct = struct()
                options.Bypass (1,1) logical = false
            end
            obj.type = type;          % runs set.type, which validates the name
            obj.params = params;      % runs set.params, which validates the values
            obj.bypass = options.Bypass;
        end

        function obj = withParam(obj, name, value)
            %WITHPARAM Return a copy of the spec with one setting added or changed.
            arguments
                obj (1,1) bpm.model.PluginSpec
                name (1,1) string {mustBeValidVariableName}
                value
            end
            p = obj.params;
            % s.(name) is "dynamic field" syntax: it uses the TEXT in name as the
            % field name, so name = "mix" means the same as p.mix.
            p.(name) = value;
            obj.params = p;
        end

        function obj = set.type(obj, value)
            % A set method runs every time the property is assigned (but not for the
            % default value above, which is why the constructor requires a type).
            if ~bpm.model.PluginSpec.isQualifiedName(value)
                error("bpm:model:PluginSpec:invalidType", ...
                    "Plugin type must be a full class name like ""bpm.effects.Delay"", not ""%s"".", value);
            end
            obj.type = value;
        end

        function obj = set.params(obj, value)
            bpm.model.PluginSpec.mustBeJsonFriendly(value);
            obj.params = value;
        end
    end

    methods (Static)
        function tf = isQualifiedName(name)
            %ISQUALIFIEDNAME True for dotted MATLAB names like "bpm.effects.Delay".
            %   Regular expression, piece by piece:
            %     [A-Za-z]\w*        a name: a letter, then letters/digits/underscores
            %     (\.[A-Za-z]\w*)*   then any number of ".name" parts
            %     ^ ... $            the WHOLE text must match, not just part of it
            tf = isStringScalar(name) && ~isempty(regexp(name, "^[A-Za-z]\w*(\.[A-Za-z]\w*)*$", "once"));
        end

        function mustBeJsonFriendly(params)
            %MUSTBEJSONFRIENDLY Error unless every setting can be saved as JSON.
            %   Allowed: numbers, logicals (true/false), and text, as scalars or
            %   row vectors. Not allowed: cells, structs, objects, matrices.
            names = fieldnames(params);
            for k = 1:numel(names)
                v = params.(names{k});
                ok = (isnumeric(v) || islogical(v) || isstring(v) || ischar(v)) ...
                    && (isempty(v) || isrow(v)) && ~(isnumeric(v) && ~isreal(v));
                if ~ok
                    error("bpm:model:PluginSpec:invalidParams", ...
                        "Plugin setting ""%s"" must be a number, logical, or text (scalar or row vector).", names{k});
                end
            end
        end
    end
end
