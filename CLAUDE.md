# Beats Per Matrix: instructions for AI coding agents

> `CLAUDE.md` and `AGENTS.md` are identical (Claude Code reads `CLAUDE.md`; other agents read `AGENTS.md`).
> A test (`tests/RepoHygieneTest.m`) fails if they differ, so **edit both together.**

## Project summary
Beats Per Matrix is a music production app (a DAW) modeled on Logic Pro, written in MATLAB.
The agent writes all of the code. Humans review every change through pull requests:
- **Meghan:** product owner and reviewer. Engineering professor, strong in MATLAB and signal processing,
  newer to Git.
- **Thomas:** architecture and code reviewer. Senior software developer, strong in architecture, testing
  and tooling, newer to MATLAB.

The full design, data format, roadmap and recorded decisions are in **`PLAN.md`**. Read it before starting a task.
If a task conflicts with PLAN.md, stop and ask; don't silently diverge.

## Architecture (summary; details in PLAN.md)
Layers, each calling only downward:
**UI (`bpm.ui`, v2) → Session → Engine (`bpm.engine`) → Plugins (`bpm.plugins`, `bpm.instruments`,
`bpm.effects`) → DSP helpers (`bpm.dsp`) → Model (`bpm.model`).**
- Model classes are **value classes**: pure data, no audio state, JSON-serializable. Methods return modified copies.
- Plugins and the engine are **handle classes** that carry DSP state.
- The model stores plugin **specs** (`type` + `params` + `bypass`), never plugin objects.
- All model times are in **beats**. Only the engine converts to seconds or samples (via `TempoMap`).
- Plugins are **block-based**: `Instrument.process(events, numFrames)` and `Effect.process(x)`.
  Buffers are always `numFrames x 2` (stereo).
- New instruments and effects are new classes in `+bpm/+instruments` or `+bpm/+effects`.
  The registry discovers them automatically.

## Conventions
- **Plain `.m` files only.** No `.mlx`, `.mlapp`, or other binary MATLAB formats (they don't merge in Git).
- **GUI is built programmatically** (`uifigure`, `uigridlayout`, `uiaxes`, ...). No App Designer.
- **Everything lives in the `+bpm` namespace** (e.g. `bpm.engine.render`). Only the repo root goes on the path.
- **Base MATLAB first.** Minimum release R2025a.
  - Toolbox-dependent code is isolated in clearly named places (e.g. `+bpm/+realtime/`), guarded by
    `bpm.util.hasToolbox(...)`, and **flagged in the PR description**.
  - Its tests call `testCase.assumeTrue(bpm.util.hasToolbox(...))`, so they skip on machines without it.
  - The core (model, engine, v1/v2 plugins) must never require a toolbox. DSP in the core is hand-written.
- Naming: `lowerCamelCase` for functions, methods, properties and variables; `UpperCamelCase` for classes;
  `UPPER_CASE` only for constants.
- Use `arguments` blocks for input validation and name-value arguments.
- **Code for experts, comments for students.** Use any idiomatic or advanced MATLAB when it's the best
  implementation (vectorization, `arguments` blocks, class features, clever indexing). Write comments so a
  freshman MATLAB student can follow: what each function or block does and why, the DSP idea in plain words,
  and an explanation of any advanced trick the first time it appears in a file. (PLAN.md decision 6.)
- Sample rate is never hard-coded: support 44100, 48000 and 96000 Hz, and test DSP at more than one rate.
- Note velocity is MIDI 1–127 everywhere.
- No global variables. No `eval`.

## Tests
- Run all tests from the repo root:
  ```
  matlab -batch "runtests('tests')"
  ```
- **Every feature ships with tests** (`matlab.unittest`, class-based, one class per unit).
- **Every test class inherits from `BpmTestCase`** (`tests/BpmTestCase.m`), not `matlab.unittest.TestCase`.
  `runtests('tests')` changes the current folder to `tests/`, and `BpmTestCase` puts the repo root back on the path.
- **Never call `bpm.*` code in a test class's property defaults.** Defaults are evaluated when the class loads,
  before `BpmTestCase` fixes the path. Build shared test objects in a `TestClassSetup` method instead.
- `tests/` is a **flat** folder (`runtests('tests')` does not search subfolders). Name files by area,
  e.g. `ModelProjectTest.m`, `EffectsDelayTest.m`.
- **See every test fail at least once.** A test that can't fail proves nothing. For validation
  tests, check that each case really reaches the rule it targets (e.g. break the rule on
  purpose in a scratch copy and confirm a test fails). See LESSONS.md.
- Test audio with numeric checks and tolerances (levels, FFT-measured responses, impulse responses),
  not golden WAV files.
- All tests must pass locally before pushing. CI runs them on every pull request and every push to `main`.

## Git workflow
- **Never commit directly to `main`.** One branch per task/issue, one pull request per branch.
- Small, focused commits with clear messages.
- Open a PR for every change. Meghan and Thomas review from separate machines.
- `main` is protected: merging needs 1 approval (new pushes clear it) and passing `Tests (base)` and
  `Tests (full)` checks. PR authors can't approve their own PRs.

## No-secrets rule (the repository is public)
- **Never write URLs, tokens, webhook addresses, API keys, or passwords into any file.**
  This includes code, comments, docs, tests, examples and workflow files.
- Read secrets only from **environment variables** (locally) or **GitHub Actions secrets** (in CI),
  e.g. the `DISCORD_WEBHOOK` environment variable and secret.
- Build any links at runtime from context (e.g. GitHub Actions `github.server_url`), never as literals.
- `tests/RepoHygieneTest.m` scans tracked files for webhook and token patterns.

## Meghan's learning goals (follow these in every PR)
Meghan's goal is to learn how to **direct and evaluate AI-built software**. So:
1. **Every PR description explains the key design decisions and the alternatives you rejected, and why.**
2. **Flag anything you're unsure about, or that deserves extra scrutiny in review** (a "Review focus" section).
3. **When review or CI catches a mistake you made, add an entry to `LESSONS.md`**: what went wrong, how it
   was caught, the fix, and the takeaway.
4. Every PR lists the files it created or changed, and any manual steps the humans must take.

## Notifications
- `.claude/settings.json` has a `Stop` hook that posts a one-line summary to Discord, reading the webhook
  from the `DISCORD_WEBHOOK` environment variable. It always exits 0 and never blocks work.
- CI (`.github/workflows/ci.yml`) posts a pass/fail summary with the branch name to Discord, using the
  `DISCORD_WEBHOOK` Actions secret.
