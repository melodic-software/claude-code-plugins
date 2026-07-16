# Investigate Test Failures

When tests fail, investigate — never dismiss, never retry blindly. Activates when a test failure needs diagnosis.

## Protocol

1. **Capture the full error** — read the complete stack trace, assertion message, test output. Don't truncate. The diagnosis is often in the details

2. **Classify the failure type:**

   | Symptom | Likely cause | Investigation path |
   |---------|-------------|-------------------|
   | Assertion mismatch (expected vs actual) | Logic bug or stale expectation | Compare expected/actual, trace the code path |
   | NullReferenceException in test | Missing setup or DI registration | Check Arrange section, verify DI container |
   | Process-global singleton "frozen" / "already initialized" error | Multiple WebApplicationFactory (or equivalent) instances | Check the consuming project's fixture conventions — apply the named fixture/collection pattern; avoid ad-hoc workarounds |
   | "Unknown option" from test runner | Bad CLI flags (e.g. `--nologo` against xUnit v3 MTP) | Strip the offending flag; confirm the runner version the project uses |
   | Timeout / hung test | Async deadlock, missing cancellation | Check for sync-over-async (`.Result` / `.Wait()`) |
   | Intermittent pass/fail | Shared static state, race condition | Check for process-global singletons, parallel execution |
   | FileNotFoundException for assembly | Missing project reference or build | Run the ecosystem's build via `/toolchain:build` first; verify project references |

3. **Reproduce deterministically** — run the failing test in isolation. Use the ecosystem's per-framework filter syntax (e.g. `--filter "FullyQualifiedName~TestClassName.TestMethodName"` for xUnit; `-k <pattern>` for pytest; `--testNamePattern` for vitest).

   If it passes in isolation but fails with others: shared state problem — check the consuming project's fixture conventions for known workarounds.

4. **Trace the root cause** — read the code path from test setup through assertion. Add logging or breakpoints if needed. Understand *why* it fails, not just *where*

5. **Check for siblings** — is this a pattern? Could the same root cause exist in similar code paths?

## The retry-is-not-a-fix rule

If a test passed on retry, the root cause is still present. It WILL surface again in CI at the worst time.

**Anti-patterns:**

- "It works on my machine" — environment difference is a real bug
- "Probably a timing issue" — timing issues are deterministic if you look hard enough
- `Thread.Sleep()` to "fix" a race — you're hiding the bug, not fixing it
- Ignoring flaky tests — every flaky test is a latent production bug

## Process-global static state (parallel test runners)

Most test runners parallelize across test classes / assemblies / modules. Process-global singletons mutated by different test classes will race.

**Rule**: only reset shared state in test classes that actually mutate it. Defensive reset in classes that don't touch the singleton introduces the race condition.

**Repo-specific instances** of this pattern are usually catalogued in the consuming project's testing conventions (fixture token, reason, forbidden alternative) — consult them before inventing a new pattern.

## After investigation

- If root cause found: proceed to the loop phase ([loop.md](loop.md)) for the fix cycle
- If root cause is in test infrastructure: fix the test, not the production code
- If root cause is a genuine bug: document it, then fix via `/implementation:implement fix`
- If intermittent and not reproducible: document the mechanism with root cause analysis. Never close as "cannot reproduce"

## Marketplace plugin skills (invoke only when installed)

- **`dotnet-diag:analyzing-dotnet-performance`** — scan for ~50 performance anti-patterns (async deadlocks, memory pressure, GC stalls) when tests timeout or run intermittently slow
- **`dotnet-msbuild:binlog-failure-analysis`** — replay MSBuild binary logs to diagnose build infrastructure failures masquerading as test failures (missing references, wrong TFM, analyzer conflicts)
