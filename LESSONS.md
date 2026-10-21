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
