# Bugfix Implementation

Bug fixes follow a bottom-up approach: reproduce, isolate, fix, prove. Temptation is to jump to the fix — resist it.

## Sequence

1. **Reproduce first (test-first, always)** — write a failing test that demonstrates the bug before touching any production code. If you can't reproduce it in a test, you can't prove you fixed it. Test name should describe the bug: `Should_ReturnError_When_InputIsNull`, not `TestFix42`. Invoke `/tdd:principles` via Skill tool (when the `tdd` plugin is installed) for test design guidance (what kind of test, where it goes, what to assert). Bug fixes are the strongest case for test-first — the failing test IS the bug report
2. **Isolate the cause** — read the code path, add logging or breakpoints if needed. Understand *why* it fails, not just *where*. A fix that addresses the symptom instead of the cause will break again
3. **Fix minimally** — change the smallest amount of code that fixes the root cause. Bug fixes are not refactoring opportunities. Boy Scout Rule applies to the files you touch, but keep behavioral changes focused
4. **Verify the fix** — the failing test from step 1 should now pass. Run the full test suite for the affected project — your fix may have side effects
5. **Check for siblings** — is this a pattern? Could the same bug exist in similar code paths? If so, fix them all in the same commit with tests for each

## Checkpoints

- Failing test committed (proves the bug exists — optional but valuable for git history)
- Fix + green test committed together (the fix and its proof are atomic)

## Common pitfalls

- **Fixing without a test** — "I can see the bug, the fix is obvious" leads to regressions. Write the test first
- **Expanding scope** — a bug fix that also refactors the surrounding code is two changes. Commit the fix first, refactor separately
- **Fixing the symptom** — null check at the call site instead of fixing why the value is null in the first place

## Marketplace plugin skills (invoke only when installed)

- **`dotnet-diag:analyzing-dotnet-performance`** — when the bug involves async deadlocks, memory pressure, or timing issues, invoke for systematic anti-pattern scanning (~50 patterns across async, memory, strings, collections)
- **`dotnet-msbuild:binlog-failure-analysis`** — when a build system failure masquerades as a code bug (wrong assembly loaded, missing reference, analyzer conflict), invoke to replay the MSBuild binary log for diagnosis
