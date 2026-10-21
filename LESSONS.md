# Lessons Learned

This is a log of mistakes the AI agent made that **code review or CI caught**. It exists so that:

- Meghan can see what kinds of errors AI-built code tends to contain, and how they get caught.
- Future agent sessions can avoid repeating them (agents are told to read and update this file).

Add an entry whenever a reviewer or a CI run catches an agent mistake. Newest entries go at the top.

## Entry template

```
### YYYY-MM-DD: short title
- **What went wrong:**
- **How it was caught:** (review by Meghan / review by Thomas / CI / local test run)
- **Fix:** (link to the commit or PR by number)
- **Takeaway:** (what to do differently next time)
```

---

### 2026-10-22: DSP tests that couldn't tell right from wrong (V1-07)
- **What went wrong:** Several of my DSP tests checked only values that are the same whatever
  the code does. The bandpass/notch/peaking/shelf tests checked points where q has no effect,
  so a wrong bandwidth passed. The allpass test checked only level, so a filter that does
  nothing passed. And the aliasing measurement skipped ±3 FFT bins around each harmonic when
  the window spreads a harmonic over ±4, so the measurement's own error (about −55 dB) hid a
  wrong triangle formula. Its comment was wrong too.
- **How it was caught:** Automated pre-merge review of PR #23 (mutation testing: 21 of 85
  mutants survived; skeptic agents confirmed each by experiment).
- **Fix:** PR #23. Every filter type is now compared with the Cookbook's analog formula at many
  frequencies, q values and gains. There's an allpass phase test, and the aliasing measurement
  uses ±5 bins with a test of its own noise floor (−87 dB). Exact sample-value checks pin the
  PolyBLEP and PolyBLAMP corrections.
- **Takeaway:** For each test, ask "which wrong implementation would still pass this?" A test of
  a measurement needs its own check that the measurement can see the effect it's looking for.

### 2026-10-22: DSP code that worked for the test cases but not for its real callers (V1-07)
- **What went wrong:** Three assumptions broke down for the code that will call these
  functions. `adsr` never reported "finished" for zero-sustain envelopes (drums, plucks), so
  those voices would never be freed. The oscillator's running-sum phase made 64-frame and
  1024-frame block renders drift apart over long notes. With a changing frequency, the PolyBLEP
  correction after a jump used the wrong step size.
- **How it was caught:** Automated pre-merge review of PR #23 (downstream-fitness and
  DSP-correctness lenses), confirmed by MATLAB experiments.
- **Fix:** PR #23: a zero-sustain "finished" rule; phase computed by multiplication for a fixed
  frequency; the previous step used after a jump; and a `StartLevel` option, so the Synth can
  retrigger or steal a voice without a click.
- **Takeaway:** Before calling a helper done, walk through how each future caller (task board,
  "Needs first") will use it: block sizes, long notes, modulation, voice management.

### 2026-10-21: CI never posted to Discord, and nothing said so
- **What went wrong:** The repo had no `DISCORD_WEBHOOK` Actions secret, so all 10 CI runs since
  setup skipped the Discord message. The workflow treated a missing secret as normal (it assumed
  only fork PRs lack secrets): it printed a quiet notice and the "Discord summary" check stayed
  green. My setup plan listed "one Discord message arrives" as a check, and I never confirmed it.
  I even told Meghan to wait for a message that could not come.
- **How it was caught:** Meghan, who noticed no CI message ever arrived. Reading the job log showed
  `DISCORD_WEBHOOK:` empty and "skipping Discord" on every run.
- **Fix:** The workflow now fails the "Discord summary" job, with a clear error, when the secret is
  missing (fork PRs excepted) or Discord rejects the message. It's not a required check, so this is
  visible without blocking merges. Meghan adds the secret.
- **Takeaway:** A green check is not proof that a side effect happened. Verify notifications, files
  and messages end to end (look for the actual message). Make "skipped" loud unless skipping is
  truly expected.

### 2026-10-21: A test that could not fail (`rejectsNonJsonParams`)
- **What went wrong:** The test meant to prove that five kinds of bad plugin setting are
  rejected built each case with `struct("x", {badValues(k)})`. `badValues(k)` (parentheses)
  is a 1x1 *cell*, so every case actually tested "a cell is rejected". The struct, matrix,
  complex and column cases never ran, and a comment on that line claimed the opposite.
- **How it was caught:** Automated pre-merge review of PR #20. This is a multi-agent stand-in
  for human review, used because Meghan chose to merge with admin bypass instead of waiting
  for Thomas. A reviewer *mutation-tested* it: it broke the validator on purpose, and all tests
  still passed.
- **Fix:** PR #20. The test now uses `p.x = badValues{k}` (curly braces take the value out),
  covers 22 bad values, and checks each error message names the reason.
- **Takeaway:** A passing test proves nothing until you have seen it fail. For validation
  tests, check each case actually reaches the rule it targets. Mutation checks are cheap.

### 2026-10-21: Hidden state that couldn't be saved (`Project.nextTrackNumber`)
- **What went wrong:** The track-id counter was a *private* property. `jsonencode` can't see
  it and a loader can't set it, but `isequal` compares it, so V1-18's round-trip test would
  have failed for every real project. After a reload, a deleted track's id would also have
  been reused.
- **How it was caught:** Automated pre-merge review of PR #20 (forward-compatibility lens),
  confirmed by a skeptic agent's MATLAB experiment.
- **Fix:** PR #20. The counter is public to read and private to set (`SetAccess = private`),
  it's part of the PLAN.md file format, and V1-18 restores it through a method of `Project`.
  Hand-made `trk-N` ids also advance it. A second review round then found that ids could still
  be reused when `p.tracks` was assigned directly, so `tracks` is now read-only too, and every
  change goes through `addTrack` / `setTrack` / `removeTrack`.
- **Takeaway:** Any state that affects equality or behavior must be part of the saved format.
  Ask "how does this survive save/load?" for every new property. A rule about a list (unique,
  never reused) only holds if every way of changing the list enforces it.

### 2026-10-21: Refuting a reviewer with the wrong experiment
- **What went wrong:** A reviewer said the sample-rate list didn't need writing out by hand.
  I "refuted" this with an experiment that used a function call as a validator *argument*,
  which MATLAB rejects. But the reviewer meant a custom validator *function*, which works.
  I then wrote the wrong conclusion into a code comment and a PR note.
- **How it was caught:** Second round of automated pre-merge review of PR #20. A skeptic agent
  ran the experiment the reviewer actually meant.
- **Fix:** PR #20. `Project.sampleRate` uses a local `mustBeSupportedSampleRate` validator that
  reads `SUPPORTED_SAMPLE_RATES`, so the list lives in one place.
- **Takeaway:** Before disagreeing with a review comment, restate the claim and make sure the
  experiment tests *that claim*, not a nearby one.

### 2026-10-21: A wrong claim in a PR description
- **What went wrong:** PR #20's description said a default-constructed `PluginSpec` could sit
  in an array with an empty type. In fact MATLAB refuses to make one (the constructor
  requires a type), and the error it gave was cryptic.
- **How it was caught:** Automated pre-merge review of PR #20, by experiment.
- **Fix:** PR #20. A clear `typeRequired` error that explains the array-growth case, tests
  for it, and a corrected description.
- **Takeaway:** Check claims about runtime behavior by experiment before putting them in a
  PR, the same way as claims in code.

### 2026-10-20: Assumed `runtests('tests')` keeps the repo root as the current folder
- **What went wrong:** The approved plan said "run from the repo root so `+bpm` is on the path". But
  `runtests('tests')` switches MATLAB's current folder to `tests/` while tests run, so `bpm.util.hasToolbox`
  could not be found and 5 of 9 tests failed.
- **How it was caught:** Local test run, before the first commit. A one-line probe test that printed `pwd`
  confirmed the cause.
- **Fix:** Added `tests/BpmTestCase.m`, an abstract base class that adds the repo root to the path with a
  `PathFixture`. All test classes inherit from it. Updated PLAN.md and CLAUDE.md/AGENTS.md.
- **Takeaway:** Verify assumptions about tool behavior with a tiny experiment before writing them into a plan.
  The placeholder test `bpmNamespaceIsOnPath` now guards this.
