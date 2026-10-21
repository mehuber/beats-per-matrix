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

        % Plugin settings. Checked and tidied by set.params below.
        params (1,1) struct = struct()

        % When true the engine passes audio through this plugin unchanged.
        bypass (1,1) logical = false
    end

    methods
        function obj = PluginSpec(type, params, options)
            %PLUGINSPEC Create a spec. TYPE is required; PARAMS defaults to no settings.
            arguments
                % TYPE has a placeholder default (string(missing), MATLAB's "no
                % value" marker) only so that a call with no inputs reaches the
                % clear error below instead of MATLAB's vague "not enough inputs".
                type (1,1) string = string(missing)
                params (1,1) struct = struct()
                options.Bypass (1,1) logical = false
            end
            % nargin = how many inputs the caller passed. MATLAB also calls this
            % constructor with NO inputs when an array of specs is grown past its
            % end (specs(3) = s when specs has 1 element) to fill the gap.
            if nargin == 0
                error("bpm:model:PluginSpec:typeRequired", ...
                    "A PluginSpec needs a type, e.g. PluginSpec(""bpm.effects.Delay""). " + ...
                    "This also happens if a PluginSpec array is grown past its end; use specs(end+1) = s instead.");
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
            % (The property's (1,1) string rule has already converted VALUE to a
            % string by the time this runs: validation happens before set methods.)
            % isQualifiedName is a Static method, defined further down.
            if ~bpm.model.PluginSpec.isQualifiedName(value)
                shown = value;
                if ismissing(shown)
                    shown = "<missing>";   % a missing string can't be printed as text
                end
                error("bpm:model:PluginSpec:invalidType", ...
                    "Plugin type must be a full class name like ""bpm.effects.Delay"", not ""%s"".", shown);
            end
            obj.type = value;
        end

        function obj = set.params(obj, value)
            obj.params = bpm.model.PluginSpec.normalizeParams(value);
        end
    end

    % Static methods belong to the class, not to one object: call them with the
    % class name, e.g. bpm.model.PluginSpec.isQualifiedName("bpm.effects.Delay").
    methods (Static)
        function tf = isQualifiedName(name)
            %ISQUALIFIEDNAME True for full class names like "bpm.effects.Delay".
            %   The name must have at least two parts separated by dots, and every
            %   part must be a legal MATLAB name (isvarname: starts with a letter,
            %   then letters, digits or underscores, and is not a keyword like "end").
            %   split(name, ".") cuts the text at each dot; arrayfun runs isvarname
            %   on every piece; all(...) is true only if every piece passed.
            if ischar(name) && isrow(name)
                name = string(name);   % accept 'bpm.effects.Delay' as well as "..."
            end
            tf = isStringScalar(name) && ~ismissing(name) && contains(name, ".") ...
                && all(arrayfun(@isvarname, split(name, ".")));
        end

        function params = normalizeParams(params)
            %NORMALIZEPARAMS Check every setting can be saved as JSON, and store it
            %   in one fixed "canonical" form. Saving a setting (jsonencode), loading
            %   it (jsondecode) and passing it back through this function gives
            %   exactly the same value, so a reloaded project equals the saved one.
            %   (The loader must therefore build specs through PluginSpec, never by
            %   copying decoded values in some other way.)
            %
            %   Allowed: real, finite numbers; logicals (true/false); text. Each may
            %   be a single value or a list (vector). Not allowed: complex numbers,
            %   NaN or Inf (JSON can't store them); matrices, structs and other
            %   types (they don't come back from JSON in the same form).
            %
            %   Canonical form:
            %     numbers  -> double (JSON has one number type), lists as rows
            %     logicals -> plain logical, lists as rows
            %     text     -> string, lists as string rows ({'a','b'} -> ["a" "b"])
            %     empty    -> [] (JSON has one empty list, which jsondecode reads as [])
            names = fieldnames(params);
            for k = 1:numel(names)
                original = params.(names{k});
                % canonicalParam is a helper function written after the class (at the
                % end of this file). It returns two outputs, caught in [v, problem].
                [v, problem] = canonicalParam(original);
                if problem ~= ""
                    error("bpm:model:PluginSpec:invalidParams", ...
                        "Plugin setting ""%s"" %s. Allowed: real finite numbers, " + ...
                        "logicals or text, as a single value or a list.", names{k}, problem);
                end
                params.(names{k}) = v;
            end
        end
    end
end

function [v, problem] = canonicalParam(v)
    % Check one setting and convert it to its canonical form (see normalizeParams).
    % PROBLEM is "" when the value is fine, otherwise a short reason for the error.
    % Each check runs BEFORE any conversion, so odd values (tables, cells holding
    % matrices, ...) get a clear error instead of crashing in a conversion step.
    problem = "";

    % One piece of text as a char must be a row ('saw') or the empty text ''.
    % (jsondecode reads an empty string "" in a saved list back as a 0x0 ''.)
    isCharText = @(c) ischar(c) && (isrow(c) || isequal(size(c), [0 0]));

    % A cell counts as text only if every element is a string or char text.
    % cellfun runs a test (here an anonymous function, @(c) ...) on every element,
    % and all(..., "all") is true only if EVERY result is true (not just per column).
    isTextCell = iscell(v) && all(cellfun(@(c) isStringScalar(c) || isCharText(c), v), "all");
    isText = isstring(v) || ischar(v) || isTextCell;
    isNumber = isnumeric(v) || islogical(v);

    if iscell(v) && ~isTextCell
        problem = "is a cell that holds something other than text (only cells of text are allowed)";
    elseif ~(isText || isNumber)
        problem = "is a " + class(v) + ", which is not allowed";
    elseif issparse(v)
        problem = "is a sparse array (JSON can't store those)";
    elseif ~(isempty(v) || isvector(v)) || (ischar(v) && ~isCharText(v))
        % string(size(v)) turns [2 3] into ["2" "3"]; strjoin glues them: "2x3".
        problem = "has size " + strjoin(string(size(v)), "x") + ", but must be a single value or a list";
    elseif isNumber && ~isreal(v)
        problem = "is complex";
    elseif isNumber && ~all(isfinite(v), "all")
        problem = "contains NaN or Inf";
    elseif isText && any(ismissing(string(v)), "all")
        problem = "contains missing text";
    end
    if problem ~= ""
        return
    end

    if isText
        v = string(v);              % 'saw' -> "saw", {'a','b'} -> ["a" "b"]
    elseif isnumeric(v)
        v = double(v);              % int8, single, ... -> double
    else
        v = logical(v);             % also turns logical look-alikes such as
                                    % matlab.lang.OnOffSwitchState into true/false
    end
    if isempty(v)
        v = [];                     % every empty list becomes the same []
    else
        v = reshape(v, 1, []);      % column [1;2;3] -> row [1 2 3]
    end
end
