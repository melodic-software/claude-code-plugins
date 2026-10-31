# Feedback Loop: Reproduce -> Fix -> Retest -> Regression

The cycle for fixing an identified bug and proving it fixed.

## The Loop

```
1. REPRODUCE ──→ Write a failing test that captures the exact bug
       │
2. ISOLATE ───→ Narrow to root cause (not symptom)
       │
3. FIX ───────→ Minimal change addressing root cause
       │
4. RETEST ────→ The originally failing test must now pass
       │
5. REGRESSION ─→ Run ALL affected tests (not just the fix)
       │
6. EVALUATE ──→ All green? Exit. New failure? Loop back to step 1
```

### Step 1: Reproduce

Write a test that fails for the exact same reason as the bug, named for the bug:

- `Should_ReturnError_When_InputIsNull` (good)
- `TestFix42` (bad)

A bug you can't reproduce in a test, you can't prove fixed. For intermittent failures, instrument the code path to capture the race condition or timing dependency.

**Commit the failing test** (optional): it proves the bug existed in git history.

### Step 2: Isolate

Fix the root cause, not the symptom:

- **Null check at the call site** is fixing the symptom. **Fix why the value is null** is fixing the cause
- Trace backward from the failure to the origin of the incorrect state
- If the failure involves multiple systems, bisect: which system produced the wrong output?

### Step 3: Fix

Change the smallest amount of code that fixes the root cause. NOT a refactoring opportunity:

- Fix the production code, not the test's assertion. A test edited to pass is not a fix. If the test itself is wrong, correct it deliberately and say so
- Fix the bug, nothing more
- Leave unrelated cleanup in the files you touch for a separate commit
- If the fix reveals a design problem, note it for a separate refactor commit

### Step 4: Retest

The failing test from step 1 must now pass. If it still fails:

- The fix is incomplete: back to step 2
- The fix introduced a different failure: you may be fixing the symptom, not the cause

### Step 5: Regression

Run the full test suite for the affected project(s), not only the test you wrote: the fix can have side effects elsewhere. `/toolchain:check` is SSOT for the exact per-ecosystem command (or the project's own test command when the `toolchain` plugin is absent); the block below is illustrative (.NET):

```bash
# Single project
dotnet test --project path/to/Project.Tests.csproj

# All tests
dotnet test
```

### Step 6: Evaluate

- **All green** → remove tagged debug instrumentation first (grep the `[DEBUG-...]` prefix), then commit fix + test together (atomic). Exit loop. Suggest `/verification:confirm` for comprehensive validation
- **New failure** → a sibling bug or a side effect. Loop back to step 1 with the new failure
- **Same test still fails** → the fix was insufficient; re-examine the root cause

## Check for siblings

After fixing one instance, ask whether the same bug exists in similar code paths. If yes:

- Write tests for each sibling case
- Fix them all in the same commit
- Run full regression again

## Commit discipline

- **Failing test committed separately** (optional). Proves the bug existed
- **Fix + green test committed together**. The fix and its proof are atomic
- **Each loop iteration is a potential commit**. If you fixed one bug but found another, commit the first fix before starting the second loop

## When to escalate

If after 3 iterations the fix keeps breaking other things:

- The code may need redesign, not a patch
- Route back to the planning skill (invoke `/planning:plan review` via the Skill tool when enabled) for a broader replanning
- Don't push through: that is how technical debt compounds

## Integration with /implementation:implement

When `/implementation:implement` encounters a test failure during its TDD cadence:

- `/implementation:implement` recognizes the failure
- Chains to `/testing:diagnose` for the reproduce→fix→retest cycle
- Returns to `/implementation:implement` after the loop exits green

When the loop is invoked standalone (outside `/implementation:implement`):

- The loop drives the full cycle including code edits
- After exit, suggests `/verification:confirm` for comprehensive validation
