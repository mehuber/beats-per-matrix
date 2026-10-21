classdef RepoHygieneTest < BpmTestCase
    % Enforces two repository rules automatically:
    %   1. CLAUDE.md and AGENTS.md stay identical.
    %   2. No file contains a URL, webhook address, token, or key (the repo is public).
    %
    % The patterns below are assembled from pieces so this file itself never
    % contains a URL or token-shaped string.

    properties (Constant)
        TextExtensions = [".m", ".md", ".yml", ".yaml", ".json", ".sh", ".ps1", ".txt", ".gitattributes"]
    end

    methods (Test)
        function agentInstructionFilesAreIdentical(testCase)
            claude = fileread(fullfile(testCase.RepoRoot, "CLAUDE.md"));
            agents = fileread(fullfile(testCase.RepoRoot, "AGENTS.md"));
            testCase.verifyEqual(agents, claude, ...
                "CLAUDE.md and AGENTS.md must be identical. Edit both together.");
        end

        function noSecretsOrUrlsInFiles(testCase)
            patterns = RepoHygieneTest.forbiddenPatterns();
            files = RepoHygieneTest.textFiles(testCase.RepoRoot, testCase.TextExtensions);
            testCase.assertNotEmpty(files, "Found no files to scan; is RepoRoot right?");

            problems = strings(0, 1);
            for f = files'
                text = fileread(f);
                for k = 1:size(patterns, 1)
                    if ~isempty(regexp(text, patterns{k, 2}, "once"))
                        rel = erase(f, testCase.RepoRoot + filesep);
                        problems(end+1) = rel + ": " + patterns{k, 1}; %#ok<AGROW>
                    end
                end
            end
            testCase.verifyEmpty(problems, ...
                "Forbidden content found (repo is public; read secrets from environment variables):" ...
                + newline + strjoin(problems, newline));
        end
    end

    methods (Static)
        function patterns = forbiddenPatterns()
            % {description, regular expression}
            scheme = "htt" + "ps?" + "://";
            patterns = {
                "URL literal",               scheme
                "Discord webhook path",      "api" + "/web" + "hooks/"
                "GitHub token",              "gh" + "[pousr]_[A-Za-z0-9]{30,}"
                "GitHub fine-grained token", "github" + "_pat_"
                "AWS access key",            "AK" + "IA[0-9A-Z]{16}"
                "Private key block",         "BEGIN [A-Z ]*PRI" + "VATE KEY"
                };
        end

        function files = textFiles(root, extensions)
            % All text files under root, skipping the .git folder.
            listing = dir(fullfile(root, "**", "*"));
            listing = listing(~[listing.isdir]);
            paths = string(fullfile({listing.folder}, {listing.name}))';
            [~, names, exts] = fileparts(paths);
            % Dotfiles like ".gitattributes" have an empty name and the whole name as extension.
            isText = ismember(exts, extensions) | ismember(names + exts, extensions);
            inGit = contains(paths, filesep + ".git" + filesep);
            files = paths(isText & ~inGit);
        end
    end
end
