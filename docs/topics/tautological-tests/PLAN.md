# Test-value guards: stop tautological AI-written tests

## Brief

### TLDR

Extend the `testing` plugin, with small changes in `mutation-testing` and `review`, so AI agents
stop writing tautological and other low-value tests. Proactive: one rules skill, two opt-in hook
guards on test files, and new deterministic scanner rules. Reactive: an end-of-task judge, a cleanup
skill, and mutation testing for test-only changes. The first release ships prevention plus a
fixture corpus that proves it. The bar: something Matt Pocock would approve of.

Research: `.work/tautological-tests/RESEARCH.md` and `RESEARCH-synthesis.md` (verified; most design
evidence is medium confidence, so the proof corpus is part of the contract).

### Goal

Agents writing unit, integration or e2e tests in any repo with the plugin produce tests whose
expected values come from the spec, a literal, or an independent calculation, never from the code
under test. When one slips through, it is caught before the task ends, and existing suites can be
cleaned up safely.

### Constraints

- Q1: Extend `testing`; no new plugin. Any new hook is opt-in through `userConfig`, off by default.
- Q2: Never edit CLAUDE.md or AGENTS.md in consumer repos. The opt-in hook injects a short
  `additionalContext` note on test-file writes; `setup check` prints an optional line to paste.
  Review reads a plugin-owned standards file.
- Q3: Two hook guards on test files, TDD or not:
  - a post-write scan of the written file, with findings fed back to the agent at once;
  - a pre-edit check that flags removed assertions, added skips or changed expected values and
    asks for a reason.

  Guidance lives in skills too. Split mode is opt-in: a spec-only test-writer subagent writes the
  tests, a validity check runs before they are frozen, and the implementer cannot edit them.
- Q4: Only deterministic, high-precision signals may block: deleted or skipped tests,
  assertion-free tests, and self-identical assertions. Everything else stays advisory until
  measured. The LLM judge never blocks until a calibration set exists.
- Q5: Wave 1 is C#/.NET (xUnit, NUnit, MSTest), JS/TS (Vitest, Jest, Playwright), Python (pytest)
  and Bash (bats, `*.test.sh`). Wave 2 is Go, Rust and Java/Kotlin.
- Q6: Test-file detection uses framework filename conventions only, never bare `test/` or `tests/`
  folders.
  - Defaults sit in the hook `if` filter, so a non-matching edit spawns nothing. There is one
    pattern list shared with `testing:audit`.
  - `.claude/testing.yaml` adds or removes patterns through the config-cascade layers
    (`docs/conventions/config-cascade`): user-global, team and local overlay.
  - Removals apply in-script. Additions reach the hook through a consumer hook entry printed by
    `setup check`.
  - The note is injected once per file per session.
- Q7: Model judgment escalates only as needed:
  - every test write gets the script scan;
  - a doubtful hit makes the writing agent justify the expected value in the same turn;
  - once at task end, a separate judge reviews the tests still in doubt.

  The judge runs on a different model and asks only where each expected value came from. It
  answers FLAG, PASS or UNKNOWN, quoting evidence before the verdict, and is advisory only.
- Q8: The guidance lives in one model-invoked rules skill in `testing`. It loads three ways:
  auto-invocation, `skills:` preload in the implementer, phase-verifier and code-reviewer agents,
  and the hook note. Other skills get one pointer line and never a copy. The phase-verifier checks
  new tests against it. `debugging:debug` requires a regression test whose expected value comes
  from the bug report.
- Q9: Cleanup rewrites by default. It deletes only a test that protects no observable behavior,
  and each deletion or merge lists its reason and waits for approval. The per-test order is:
  quarantine flaky tests, rewrite, delete, merge confirmed duplicates, keep the rest.
- Q10: A new `testing:cleanup` skill reads `testing:audit` findings and runs a mutation check before
  and after, one PR per module or folder.
- Q11: `mutation-testing:audit` gains a scope that mutates the production code the changed tests
  exercise. Its survivor report classifies why each mutant lived: no assertion, expected value
  taken from the code under test, or an input gap.
- Q12: Proof is a committed per-language fixture corpus in CI: bad tests must be flagged and good
  tests must stay silent. Real repos are run for precision before any signal may block. Every
  false positive found in use becomes a good fixture. The judge's labeled set is reviewed by two
  people.
- Q13: The release order is:
  1. Prevention plus proof.
  2. The judge and the mutation scope.
  3. Cleanup, split mode and wave 2.

### Acceptance criteria

- Pocock's examples are required bad fixtures and must be flagged:
  - constant restatement (the 280-character limit);
  - a test reading source text to check order;
  - the AudioContext mock that cannot fail;
  - the anti-patterns in his tdd skill (`tests.md`).
- The wave-1 fixture corpus holds at least one bad and one good fixture for each deterministic
  variant (the taxonomy in `.work/tautological-tests/taxonomy/`) in each wave-1 language.
  - Every bad fixture is flagged, and every good fixture produces zero findings.
- The ten planted variants that `testing:audit` currently misses are flagged by the new rules or
  by required lint. This excludes variants the taxonomy marks as needing reasoning.
- An edit to a file that matches no test pattern spawns zero hook processes, measured by the
  hook-budget strace test.
- Every false positive found after release becomes a committed good fixture before it is fixed.
- The hook note appears at most once per test file per session.
- Removing a default pattern in `.claude/testing.yaml` silences the hook and the audit for that
  pattern with no plugin change.
- No consumer CLAUDE.md or AGENTS.md is modified by any skill or hook.
- IF the scan script errors or times out, THEN the edit proceeds and the failure is logged; the
  hook never blocks on its own failure.
- WHILE the hook is not opted in, the plugin adds zero hook processes to any tool call.

### Captured assumptions

- The Pocock examples come from his AI Engineer Paris 2026 talk (~7:16-7:40) and his tdd
  skill's `tests.md`; the implementation fetches both before writing fixtures.
- Hook `if` filters skip the spawn when they do not match (hooks docs, medium confidence). The plan
  re-verifies this against the current Claude Code version.
- Files written through Bash scripts or MCP tools bypass the hooks. Guardrails covers shell writes;
  MCP and scripts are a known gap, caught later by the audit and the judge.
- No published LLM judge for tautology has been validated against human labels, so the judge
  stays advisory until the local labeled set exists.
- Surface-page defects seen during this interview are tracked separately (issue #5009 and a
  findings log to be filed); they do not affect this plan.

### Out-of-scope

- Editing consumer CLAUDE.md or AGENTS.md files.
- Red-first (TDD-order) enforcement with a model call per edit, as TDD Guard and Probity do.
- Blocking on any LLM-judge verdict before calibration.
- Wave 2 languages, cleanup and split mode in the first release.
- Separate maintenance found during research: `mutation-testing` `tooling.md` staleness and the
  `testing:audit` coverage-counter discrepancy.

### Deferred questions

- none

## Plan
