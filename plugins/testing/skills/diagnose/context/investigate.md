# Investigate Test Failures

When tests fail, investigate. Never dismiss, never retry blindly. Activates when a test failure needs diagnosis.

## Protocol

1. **Capture the full error**. Read the complete stack trace, assertion message, test output. Don't truncate. The diagnosis is often in the details. Before any rerun, copy the first failure's artifacts out of the runner's output directory, which the next run may overwrite: trace, screenshot, error context, and the seed or order line the runner printed. See [Reruns and replay](#reruns-and-replay)

2. **Classify the failure type:**

   | Symptom | Likely cause | Investigation path |
   |---------|-------------|-------------------|
   | Assertion mismatch (expected vs actual) | Logic bug or stale expectation | Compare expected/actual, trace the code path |
   | NullReferenceException in test | Missing setup or DI registration | Check Arrange section, verify DI container |
   | Process-global singleton "frozen" / "already initialized" error | Multiple WebApplicationFactory (or equivalent) instances | Check the consuming project's fixture conventions. Apply the named fixture/collection pattern; avoid ad-hoc workarounds |
   | "Unknown option" from test runner | Bad CLI flags (e.g. `--nologo` against a Microsoft Testing Platform run, where the banner switch is `--no-banner`) | Strip the offending flag; confirm which runner and version the project uses. An unrecognized option exits 5, an invalid-argument code, not a zero-test result |
   | Timeout / hung test | Async deadlock, missing cancellation | Check for sync-over-async (`.Result` / `.Wait()`) |
   | Intermittent pass/fail | Shared static state, race condition | Check for process-global singletons, parallel execution |
   | FileNotFoundException for assembly | Missing project reference or build | Run the ecosystem's build by invoking `/toolchain:check` via the Skill tool first; verify project references |

3. **Reproduce deterministically**. Run the failing test in isolation. Use the ecosystem's per-framework filter syntax (e.g. `--filter "FullyQualifiedName~TestClassName.TestMethodName"` for xUnit; `-k <pattern>` for pytest; `--testNamePattern` for vitest).

   If it passes in isolation but fails with others: shared state problem. Check the consuming project's fixture conventions for known workarounds.

   When the runner shuffles order or seeds randomness, replay with the seed the first failure printed before trying anything else. Read the flag from the runner's own docs; two examples: pytest-randomly's `--randomly-seed=<seed>` ([README](https://github.com/pytest-dev/pytest-randomly#readme)), and Go's `go test -shuffle=<N>` ([testing flags](https://pkg.go.dev/cmd/go/internal/test)). As of 2026-10-06. Recheck trigger: either page renames or drops the flag.

4. **Trace the root cause**. Read the code path from test setup through assertion. Add logging or breakpoints if needed. Tag every debug log with a unique short prefix (e.g. `[DEBUG-a4f2]`) so cleanup before commit is a single grep. Understand *why* it fails, not just *where*

5. **Check for siblings**. Is this a pattern? Could the same root cause exist in similar code paths?

## The retry-is-not-a-fix rule

If a test passed on retry, the root cause is still present. It WILL surface again in CI at the worst time.

**Anti-patterns:**

- "It works on my machine": environment difference is a real bug
- "Probably a timing issue": timing issues are deterministic if you look hard enough
- `Thread.Sleep()` to "fix" a race: you're hiding the bug, not fixing it
- Ignoring flaky tests: every flaky test is a latent production bug

## Reruns and replay

Fix rounds are capped by `maxRounds` in [fix-until-green.md](fix-until-green.md). Diagnostic reruns of an unchanged test have their own cap:

- **Rerun to measure, never to get green.** Rerun an unchanged test only to measure its flake rate, over a number of runs fixed before the first one, and report the count as `<failed>/<runs>`. A pass inside that batch is a data point, not a result; the failure stays open. Raising a low reproduction rate is `/debugging:debug` Phase 1's job.
- **Artifacts first.** Preserve the first failure's trace, screenshot, error context and printed seed (step 1) before the first rerun. A rerun that overwrites them leaves only the run that passed.
- **Seed before rerun.** When the first failure printed a seed or order, replay it (step 3). A failure that reproduces under its seed is deterministic and needs no flake-rate batch.

A pass earned by rerunning still hides the break: Google reports that marking a test failed only after three consecutive failures encourages ignoring flakiness and delays when a break surfaces ([Flaky Tests at Google](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html), 2016, Google's internal CI). As of 2026-10-06. Recheck trigger: Google publishes a successor flaky-test post.

## Process-global static state (parallel test runners)

Most test runners parallelize across test classes / assemblies / modules. Process-global singletons mutated by different test classes will race.

**Rule**: only reset shared state in test classes that actually mutate it. Defensive reset in classes that don't touch the singleton introduces the race condition.

**Repo-specific instances** of this pattern are usually catalogued in the consuming project's testing conventions (fixture token, reason, forbidden alternative). Consult them before inventing a new pattern.

## After investigation

- If root cause found: proceed to the loop phase ([loop.md](loop.md)) for the fix cycle
- If root cause is in test infrastructure: fix the test, not the production code
- If root cause is a genuine bug: document it, then fix by invoking `/implementation:implement fix` via the Skill tool
- If intermittent and not reproducible: document the mechanism with root cause analysis. Never close as "cannot reproduce"
