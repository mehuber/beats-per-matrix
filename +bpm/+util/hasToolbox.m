function tf = hasToolbox(name)
%HASTOOLBOX True if a MathWorks toolbox is both installed and licensed.
%   tf = bpm.util.hasToolbox(name) returns a logical scalar. NAME is a short
%   name used in this project:
%
%       "audio"   Audio Toolbox
%       "signal"  Signal Processing Toolbox
%       "dsp"     DSP System Toolbox
%
%   Use it to guard toolbox-dependent code, and in tests:
%
%       testCase.assumeTrue(bpm.util.hasToolbox("audio"), ...
%           "Audio Toolbox not available; skipping.")
%
%   Both checks are needed: a license can exist without the toolbox being
%   installed, and an installed toolbox may have no license available.

    arguments
        name (1,1) string
    end

    % Lookup table: short name -> {product name shown by ver, license feature name}.
    % A dictionary maps keys to values, like a two-column table you can look up by
    % the first column. Each value is a 1x1 cell wrapping a {name, feature} pair,
    % because a dictionary stores one value per key; we unwrap it below with {1}.
    known = dictionary( ...
        "audio",  {{"Audio Toolbox",             "Audio_System_Toolbox"}}, ...
        "signal", {{"Signal Processing Toolbox", "Signal_Toolbox"}}, ...
        "dsp",    {{"DSP System Toolbox",        "Signal_Blocks"}});

    key = lower(name);
    if ~isKey(known, key)
        error("bpm:util:hasToolbox:unknownToolbox", ...
            "Unknown toolbox ""%s"". Known names: %s.", ...
            name, strjoin(keys(known), ", "));
    end

    info = known(key);
    info = info{1};
    productName = info{1};
    licenseFeature = info{2};

    % ver() lists every installed product. {ver().Name} collects all their names into
    % one cell array, and strcmp compares each name to ours (true where it matches).
    installed = any(strcmp({ver().Name}, productName));
    tf = installed && license("test", licenseFeature) == 1;
end
