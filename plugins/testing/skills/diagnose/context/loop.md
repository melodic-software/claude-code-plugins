# Feedback Loop: Reproduce -> Fix -> Retest -> Regression

The disciplined cycle for fixing test failures. Activates when a bug has been identified and needs to be fixed with verification. Where Kent Beck's Red-Green-Refactor meets the engineering discipline of "prove it's fixed."

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

Write a test that fails for the exact same reason as the bug. The test name should describe the bug:

- `Should_ReturnError_When_InputIsNull` (good)
- `TestFix42` (bad)

If you can't reproduce it in a test, you can't prove you fixed it. For intermittent failures, instrument the code path to capture the race condition or timing dependency.

**Commit the failing test** — this proves the bug exists in git history. Optional but valuable for traceability.

### Step 2: Isolate

Don't fix the symptom. Find the root cause:

- **Null check at the call site** is fixing the symptom. **Fix why the value is null** is fixing the cause
- Trace backward from the failure to the origin of the incorrect state
- If the failure involves multiple systems, bisect: which system produced the wrong output?

### Step 3: Fix

Change the smallest amount of code that fixes the root cause. NOT a refactoring opportunity:

- Fix the bug, nothing more
- Boy Scout Rule applies to files you touch, but keep behavioral changes focused
- If the fix reveals a design problem, note it for a separate refactor commit

### Step 4: Retest

The failing test from step 1 must now pass. If it still fails:

- The fix is incomplete — back to step 2
- The fix introduced a different failure — you may be fixing the symptom, not the cause

### Step 5: Regression

Run the full test suite for the affected project(s). Not just the test you wrote — ALL tests that could be impacted.

```bash
# Single project
dotnet test --project path/to/Project.Tests.csproj

# All tests
dotnet test
```

**Why all tests?** Your fix may have side effects. A change that fixes one test but breaks three others is not a fix.

### Step 6: Evaluate

- **All green** → commit fix + test together (atomic). Exit loop. Suggest `/verification:confirm` for comprehensive validation
- **New failure** → you've found a sibling bug or a side effect. Loop back to step 1 with the new failure
- **Same test still fails** → re-examine the root cause. The fix was insufficient

## Check for siblings

After fixing one instance, ask: is this a pattern? Could the same bug exist in similar code paths? If yes:

- Write tests for each sibling case
- Fix them all in the same commit
- Run full regression again

## Commit discipline

- **Failing test committed separately** (optional) — proves the bug existed
- **Fix + green test committed together** — the fix and its proof are atomic
- **Each loop iteration is a potential commit** — if you fixed one bug but found another, commit the first fix before starting the second loop

## When to escalate

If after 3 iterations the fix keeps breaking other things:

- The code may need redesign, not a patch
- Route back to the planning skill (`/planning:plan review` when installed) for a broader replanning
- Don't push through — that's how technical debt compounds

## Integration with /implementation:implement

When `/implementation:implement` encounters a test failure during its TDD cadence:

- `/implementation:implement` recognizes the failure
- Chains to `/testing:diagnose` for the reproduce→fix→retest cycle
- Returns to `/implementation:implement` after the loop exits green

When the loop is invoked standalone (outside `/implementation:implement`):

- The loop drives the full cycle including code edits
- After exit, suggests `/verification:confirm` for comprehensive validation

## Marketplace plugin skills (invoke only when installed)

These are .NET-ecosystem plugin skills — applicable when your stack is .NET:

- **`dotnet-test:mtp-hot-reload`** — enable MTP hot reload for rapid test iteration without rebuilding. Requires `Microsoft.Testing.Extensions.HotReload` package + `TESTINGPLATFORM_HOTRELOAD_ENABLED=1`. Use `dotnet run --project` (not `dotnet test`) for hot reload mode
- **`dotnet-diag:analyzing-dotnet-performance`** — scan for async deadlocks, timing races, and GC pressure when intermittent failures suggest performance-related root causes
