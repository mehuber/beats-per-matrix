classdef (Abstract) BpmTestCase < matlab.unittest.TestCase
    % Base class for all Beats Per Matrix tests. Every test class should
    % inherit from this instead of matlab.unittest.TestCase.
    %
    % Why: runtests('tests') changes MATLAB's current folder to tests/ while
    % the tests run, so the repo root (which holds the +bpm namespace) is no
    % longer on the path. This fixture adds the repo root for the duration of
    % each test class and removes it afterwards.
    %
    % Abstract classes are not run as tests, so this file adds no tests itself.

    properties (Constant)
        RepoRoot = string(fileparts(fileparts(mfilename("fullpath"))))
    end

    methods (TestClassSetup)
        function addRepoRootToPath(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.RepoRoot));
        end
    end
end
