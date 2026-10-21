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
  covers 19 bad values, and checks each error message names the reason.
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
