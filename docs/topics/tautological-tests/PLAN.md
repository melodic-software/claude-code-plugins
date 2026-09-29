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
  - Amended 2026-09-28 during planning. User: "we need to make sure Bash is covered. I mean, all
    the languages that we use, and also how the plugin is designed to be extensible and
    configurable for other languages and platforms/frameworks." A fleet inventory found hand-rolled
    Bash (~800 files), C# xUnit v3, Vitest and `node:test`, Python unittest and pytest, PowerShell
    Pester (65 files) and Go stdlib `testing` (65 files). Wave 1 adds Pester, `node:test`,
    unittest and Go stdlib `testing`. Wave 2 keeps Rust, Java/Kotlin and Go testify. Languages
    and frameworks are added through declarative adapters (`design/design-resolution.md`).
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
- WHILE the hook is not opted in, the plugin adds zero hook processes to a tool call on a non-test
  path, and at most one launcher process, which exits at once, per test-file write. (Reworded at plan
  approval 2026-09-28: a hook `if` row cannot read a userConfig value.)

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

### Goal

**What**: Release 1 of the Brief (prevention plus proof). The scanner is rebuilt on declarative
language adapters and covers every language the fleet uses. It gains four new advisory rules,
alongside a lint-presence check in `/testing:setup`. Two opt-in hook guards run on test files, and
one rules skill is preloaded where tests get written and reviewed. A committed fixture corpus
proves the rules flag bad tests and stay silent on good ones. Releases 2 and 3 are outlined and get
their own plans later.
**Why**: Agents write tests whose expected values come from the code under test. The current audit
flags 0 of 10 planted variants beyond its core rules, and nothing runs while a test is being written.
**Done when**: every Release 1 acceptance criterion in the Brief has a passing mechanical check in
CI, except the false-positive-becomes-a-fixture rule, which is enforced by process (Phase 8). The
changed plugins are version-bumped with CHANGELOG entries, and the precision-run report is committed.

- Design contracts: `design/design-resolution.md` (early exit accepted 2026-09-28).
- Evidence: `.work/tautological-tests/RESEARCH-synthesis.md` and
  `.work/tautological-tests/extensibility/RESEARCH.md`.
- The engine choice rests on local timings and first-party docs. The verifier failed row 4
  (corroboration) on the extensibility slice, so the timings carry medium confidence. Two checks
  could overturn the choice: the Phase 1 parity run and the Phase 2 latency budget.

### Standards grounding

| Surface | Sections cited | Layer provenance |
|---|---|---|
| Hooks | `docs/conventions/hook-precision` rules 1 (diff-scope Edit checks), 3 (bounded stdin), 6 (skip gitignored paths); `docs/conventions/hook-budget` "The budget", "What enforces it"; `docs/conventions/hook-config-delivery` | team |
| Consumer config | `docs/conventions/config-cascade` (layer order, additive merge) | team |
| Findings | `docs/conventions/detector-findings` "Rule ids and thresholds", "The severity crosswalk", "The remedy is pinned by an assertion, in every scope it fires in" | team |
| Shell tests | `docs/conventions/shell-test-helpers` (per-plugin helpers, no cross-plugin imports) | team |
| Skill bodies | `.claude/rules/skill-bodies-state-current-rules.md` (`## Next` section, volatile-specific records) | team |
| PRs | `AGENTS.md` (draft PRs), `.claude/rules/pr-body-contract.md` | team |

### Test strategy

- Red first for every adapter and rule: write the bad and good fixtures, watch the suite fail, then
  implement.
- Test boundaries, all driven through their command line:
  - `plugins/testing/skills/audit/scripts/cant-fail-scan.sh` (existing), plus a new `--file <path>`
    mode: findings and exit codes.
  - `plugins/testing/hooks/test-scan.sh` and `test-weaken.sh` (new): hook JSON in, hook JSON out, exit code.
  - `plugins/testing/scripts/resolve-config.sh` (new): merged config on stdout.
  - `plugins/testing/scripts/gen-hook-filters.sh --check` (new): exit code.
- Corpus: `plugins/testing/skills/audit/evals/fixtures/corpus/<adapter-id>/{bad,good}/`, one test per
  file. Each bad file carries an `expect: <rule-id>` header. `cant-fail-scan.test.sh` names every
  corpus basename, which satisfies `scripts/check-orphaned-fixtures.sh`. It runs `--file` on each
  file and asserts exact rule sets.
- A coverage grid, `corpus/GRID.md` (deterministic taxonomy variant × adapter), marks each cell `pair`
  or `n/a: <reason>`. `plugins/testing/skills/audit/scripts/check-corpus-grid.sh` fails when a `pair` cell lacks a bad and a good
  file (acceptance criterion 2).
- awk portability: every scanner test also runs under `mawk` when it is on PATH. A gawk-only pass
  does not count.
- Tests that resolve config set `HOME` to a temp directory, so the real user layer never leaks in.

### Phase 1: Adapter engine, behavior-preserving [DONE]

Move the JS/TS, Python and C# knowledge out of `cant-fail-scan.awk` into adapter files, with no
change in findings.

- First item, pre-flight on the scanner's output contract. Record in the PR body whether each
  reader stays unchanged or is updated in the same PR:
  - `plugins/review/agents/code-reviewer.md:56`
  - `plugins/testing/skills/audit/evals/evals.json` (rule set, exit semantics)
  - `docs/conventions/detector-findings/README.md` crosswalk row (~line 741)
  - `plugins/ai-slop/skills/audit/scripts/emit-findings.sh:162` (identical frontmatter predicate)
- Add `--file <path>` to scan exactly one file. Its exit codes match whole-tree mode.
- Add an awk loader for a documented YAML subset: block maps, block lists, one-line flow lists
  `[a, b]`, and dotted keys. It strips `\r` and rejects anything else with exit 2, naming the file
  and line. It also validates adapter regexes against a portable ERE subset that works in gawk,
  mawk and BSD awk: no `\s`, no backreferences, and no intervals unless mawk passes them.
- Schema fits the subset:
  - `equality` becomes two lists, `equality.call2` and `equality.receiver`; `equality.pipeline` is
    reserved (design-resolution section 2).
  - Adapter precedence: the adapter whose `detect.any_regex` matches wins; on a tie, the one declared
    first in load order wins. A fixture covers `*.test.ts` under Vitest versus Jest.
- Split the engine into rules, per-language lexers (`js`, `cs`, `python`) and block models (`brace`,
  `indent`).
- Write `js-vitest`, `js-jest`, `py-pytest` and `cs-xunit` adapters that reproduce today's `*_ERE` values.
- `collect_files` (`cant-fail-scan.sh:207-221`) takes the deduplicated union of adapter `files:`.
- `scripts/parity-check.sh`:
  - runs the `main` scanner (extracted with `git archive` into `.work/`) and the working-tree scanner
    once per fixture subdirectory (`config exempt mock-only negative positive sanity`), and once over
    this repo's tree;
  - asserts each run examined more than 0 files and exited 0 or 1;
  - diffs the output, under gawk and mawk.

| File | Action |
|---|---|
| [ ] `plugins/testing/skills/audit/scripts/cant-fail-scan.awk` | MODIFY |
| [ ] `plugins/testing/skills/audit/scripts/cant-fail-scan.sh` | MODIFY |
| [ ] `plugins/testing/skills/audit/scripts/adapter-load.awk` | CREATE |
| [ ] `plugins/testing/skills/audit/adapters/{js-vitest,js-jest,py-pytest,cs-xunit}.yaml` | CREATE |
| [ ] `plugins/testing/skills/audit/scripts/parity-check.sh` | CREATE |
| [ ] `plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` | MODIFY (loader, `--file` and precedence cases) |
| [ ] `plugins/testing/skills/audit/scripts/mask-js.awk`, `runner-config-scan.awk` | KEEP |

**Sanity Check:**

- `bash plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` exits 0, and
  `git diff main -- plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh | grep -c '^-[^-]'` returns 0.
- `grep -cE '_ERE *=' plugins/testing/skills/audit/scripts/cant-fail-scan.awk` returns 0.
- `bash plugins/testing/skills/audit/scripts/parity-check.sh` exits 0 and prints `examined>0` for every run.

### Phase 2: `test-scan` hook, end to end on existing rules [TODO]

The integration slice: an opt-in PostToolUse hook runs `cant-fail-scan.sh --file` on the written
test file and feeds findings back.

- Add `userConfig.test_guards_enabled` (boolean, default `false`) to `plugins/testing/.claude-plugin/plugin.json`.
- Copy `hooks/exec-bash.mjs` in through `scripts/sync-exec-bash.sh` and register it there.
- Add `plugins/testing/hooks/hooks.json`: an exec-form `test-scan` on PostToolUse
  `Write|Edit|MultiEdit`, with `--require-true TEST_GUARDS_ENABLED` and `if` rows generated by
  `gen-hook-filters.sh`. The generator deduplicates globs, and no two rows may match one path.
- Live probe, recorded in `docs/topics/tautological-tests/probes.md` with the Claude Code version.
  One `claude -p --debug` run confirms:
  - a non-matching path spawns nothing;
  - basename globs (`test_*.py`, `*_test.go`, `*Tests.cs`, `*.Tests.ps1`) match;
  - the hook input carries `agent_id` for a subagent.
- `test-scan.sh`:
  - reads stdin through the bounded reader (hook-precision rule 3);
  - skips gitignored paths (rule 6);
  - normalizes the path, so Windows backslashes and `C:\` compare equal to `/c/`;
  - for Edit, locates each `new_string` occurrence (`replace_all` may give several) and reports only
    findings in blocks that overlap them;
  - for Write, reports all blocks on create and only changed blocks on update (`tool_response.type`);
  - injects the rules-skill note once per `session_id` + `agent_id` + path, using an atomic `mkdir`
    marker under `${CLAUDE_PLUGIN_DATA}`, and prunes markers older than 7 days;
  - on a doubtful hit (`rule-recomputed-expectation`, and `rule-constant-restatement` from Phase 4),
    asks the agent to state where the expected value comes from, in the same turn (Q7 tier 2);
  - runs the scanner under its own timeout, set below the hooks.json `timeout`. A timeout or error
    logs a line and exits 0;
  - caps `additionalContext` below 10,000 characters.
- Latency budget: `test-scan` p95 per matching write is at most 150 ms on WSL and at most 1 s on
  Windows (judgment, from the 89 ms WSL measurement). The earlier 3 S budget
  (`docs/conventions/hook-budget` unit S) cannot hold where a bash spawn costs under 1 ms but the
  node launcher every exec-form hook needs costs 20-30 ms (user decision, 2026-09-28). Measured on
  WSL here, and on one Windows fleet machine through `/fleet:reach` (user-approval gate).

| File | Action |
|---|---|
| [ ] `plugins/testing/.claude-plugin/plugin.json` | MODIFY |
| [ ] `plugins/testing/hooks/hooks.json` | CREATE |
| [ ] `plugins/testing/hooks/exec-bash.mjs` | CREATE (synced copy) |
| [ ] `scripts/sync-exec-bash.sh` | MODIFY (add testing) |
| [ ] `plugins/testing/hooks/test-scan.sh` + `test-scan.test.sh` | CREATE |
| [ ] `plugins/testing/scripts/gen-hook-filters.sh` + `gen-hook-filters.test.sh` | CREATE |
| [ ] `docs/topics/tautological-tests/probes.md` | CREATE |

**Sanity Check:**

- `bash plugins/testing/hooks/test-scan.test.sh` exits 0. It asserts that:
  - (a) with the option unset, a test-file payload produces no output;
  - (b) a zero-assertion Vitest write returns `additionalContext` naming `rule-zero-assertion`;
  - (c) a second write to the same file with the same `session_id` and `agent_id` carries no note, and a different `agent_id` gets one;
  - (d) an Edit touching one block leaves a pre-existing bad block elsewhere silent;
  - (e) a hanging scanner (a `sleep` stub) gives exit 0 and a log line before the hooks.json timeout;
  - (f) a gitignored test path produces no output;
  - (g) the doubtful-hit prompt appears for a recomputed expectation.
- `bash plugins/testing/scripts/gen-hook-filters.sh --check` exits 0. Its test asserts that every row has an `if`, that no glob matches `src/app.ts`, and that no two rows match one path.
- `bash scripts/sync-exec-bash.sh --check`, `bash scripts/check-hook-exec-form.sh`, `bash scripts/check-hook-userconfig-argv.sh`, `bash scripts/check-hooks-description.sh` and `bash scripts/check-hook-wiring-liveness.sh` exit 0.
- `grep -c 'p95' docs/topics/tautological-tests/probes.md` is at least 2 (WSL and Windows), at most 150 ms on WSL and 1 s on Windows.

### Phase 3: Wave-1 adapters for every fleet language [TODO]

- Add the `shell` lexer family and the `file` block model to the awk engine.
- `rule-recomputed-expectation` exists today for JS and Python only (`cant-fail-scan.awk:277,315`).
  Extend it to C#, Bash, PowerShell and Go through the adapter `equality` lists. This is rule work,
  red first.
- Add these adapters:
  - `bash-harness`:
    - assertion calls `pass|fail|assert_*`;
    - idioms such as `echo .*FAIL` followed by `exit [1-9]` within two lines;
    - delegation such as `gate_test::run_suite`, `source .*test-helpers`, and `node|python3?|pytest|exec` running a suite file.
  - `bash-bats`, `pwsh-pester` (`Should`, `Should -Invoke`) and `go-testing` (`t.Error*`, `t.Fatal*`).
  - `js-node-test` (`node:assert`), `js-playwright` and `py-unittest`.
  - `cs-nunit` and `cs-mstest`. The C# adapters carry Shouldly, FluentAssertions, NSubstitute, Moq
    and Verify vocabulary.
- Red first: a bad and a good corpus file per adapter for `rule-zero-assertion` and
  `rule-recomputed-expectation`, recorded in `GRID.md`.
- Bash false-positive ceiling, measured now rather than in Phase 8:
  - Scan every `*.test.sh` in this repo and classify each zero-assertion finding.
  - Every false positive becomes a good fixture and an adapter fix.
  - The phase closes at 0 known false positives on this repo, recorded in a "This repo, Bash" section of `docs/topics/tautological-tests/precision-run.md`, which this phase creates.
- `bash-harness` findings stay advisory in Release 1. They sit beside
  `scripts/check-discriminating-test-skips.sh`, which keeps skip-vacating; this scanner owns
  assertions. The coverage text says so.
- Regenerate the hook filters.

**Sanity Check:**

- `bash plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` exits 0, including the corpus loop.
- `ls plugins/testing/skills/audit/adapters/*.yaml | wc -l` returns 13.
- `bash plugins/testing/skills/audit/scripts/check-corpus-grid.sh` and `bash scripts/check-orphaned-fixtures.sh --check` exit 0.
- `bash plugins/testing/skills/audit/scripts/cant-fail-scan.sh --file plugins/knowledge/skills/docpage-digest/scripts/check-fences-exact.test.sh` reports 0 findings.
- `CANT_FAIL_SCAN_ROOT=. bash plugins/testing/skills/audit/scripts/cant-fail-scan.sh | grep -c 'rule-zero-assertion.*\.test\.sh'` equals the true-positive count recorded in `docs/topics/tautological-tests/precision-run.md` "This repo, Bash".
- `bash plugins/testing/scripts/gen-hook-filters.sh --check` exits 0.

### Phase 4: New rules, Pocock fixtures, planted variants [TODO]

- First item: fetch Pocock's AI Engineer Paris 2026 talk (~7:16-7:40) and his tdd skill's
  `tests.md`. Map each example to a named rule in `GRID.md`:
  - the 280-character constant: `rule-constant-restatement`;
  - the source-text order check: `rule-source-text-read`;
  - the AudioContext mock: `rule-mock-only-oracle`, re-checked against the example;
  - each `tests.md` anti-pattern: a rule.
- If an example needs reasoning and no deterministic rule can catch it, stop and put the conflict
  with acceptance criterion 1 to the user. Do not drop it.
- Split the 12 planted tests from `.work/tautological-tests-verify/taxonomy/fx/` into one test per
  file under `corpus/planted/`, and commit them. Mark the variants the taxonomy says need reasoning.
- Red, then implement `rule-inert-assertion`, `rule-constant-restatement`, `rule-source-text-read` and
  `rule-snapshot-only`, all advisory. For each rule:
  - a crosswalk row and eval coverage;
  - positive and negative `Action` remedy assertions in every scope it fires in (detector-findings);
  - the README crosswalk counts, updated;
  - `evals.json` expectations, updated.

**Sanity Check:**

- `bash plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` exits 0.
- `grep -rl 'source: pocock' plugins/testing/skills/audit/evals/fixtures/corpus/*/bad | wc -l` is at least 4, and every Pocock row in `GRID.md` names a rule.
- `bash plugins/testing/skills/audit/scripts/check-corpus-grid.sh`, `bash scripts/check-orphaned-fixtures.sh --check`, `bash scripts/check-detector-findings-crosswalk.sh` and `bash scripts/check-detector-eval-coverage.sh` exit 0.

### Phase 5: Config cascade and `/testing:setup` [TODO]

- `plugins/testing/scripts/resolve-config.sh` merges `~/.claude/testing.yaml`,
  `.claude/testing.yaml` and `.claude/testing.local.yaml` additively. It is modeled on
  `plugins/docs-hygiene/scripts/resolve-config.sh`, not imported from it.
- The scanner and both hooks honor `adapters.enable`, `adapters.disable`, `paths.include`,
  `paths.exclude`, `extend`, `adapter_dirs` and `rules.<id>`.
- Path globs use one matcher, specified with tests: `**` matches across `/`, `*` does not, and paths
  are normalized first.
- Probe whether a consumer settings hook receives `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_OPTION_*`.
  Record the result in `probes.md`. If it does not, the printed consumer entry passes `--enabled` and
  locates the plugin through a stable shim `[FALLBACK]`.
- New `plugins/testing/skills/setup/SKILL.md`, `check | apply`, with
  `disable-model-invocation: true` (modeled on `plugins/mutation-testing/skills/setup`). `check`
  prints:
  - the resolved config;
  - lint-rule presence per language: eslint-plugin-jest/vitest/playwright, xUnit2021, NUnit2009,
    ruff PLR0124. Bash, Pester and Go are marked "no maintained rule";
  - the optional instruction line to paste (Q2);
  - a consumer hook entry for any added glob that no hook filter covers (Q6).
- The audit report lists consumer globs that no hook filter covers.

**Sanity Check:**

- `bash plugins/testing/scripts/resolve-config.test.sh` exits 0. It covers layer order, list concatenation, `**` matching and a Windows-style path.
- A `cant-fail-scan.test.sh` case writes `.claude/testing.yaml` containing an `exclude` list with `**/*.test.ts`. It asserts 0 findings from the scanner and no `test-scan.sh` output for a bad `.test.ts` fixture.
- A setup test runs `check` and a scripted `apply` in a temp repo and asserts that no file named `CLAUDE.md` or `AGENTS.md` changed.
- `grep -c 'CLAUDE_PLUGIN_ROOT' docs/topics/tautological-tests/probes.md` is at least 1.
- `bash scripts/check-changed-skills.sh origin/main` exits 0.

### Phase 6: `test-weaken` hook [TODO]

- PreToolUse on `Edit|MultiEdit|Write`, with the same option gate, filters and precision rules as `test-scan`.
- Compares old and new content to detect a removed assertion, an added skip marker (adapter
  `test_skip`), a removed test block, or a changed expected literal.
- Release 1 output: `additionalContext` asking for the reason, with no `permissionDecision` field
  (`allow` would skip the user's permission prompt).
- The deny path for deleted or skipped tests sits behind `rules.test-weaken-block: error`, which is
  off by default and stays off in Release 1 (D4, D5). With it on, an edit carrying a
  `test-change: <reason>` marker is allowed.
- Known limitation, stated in the skill: the agent can write that marker itself. The marker makes
  the reason visible to reviewers; it does not prove the reason.

**Sanity Check:**

- `bash plugins/testing/hooks/test-weaken.test.sh` exits 0. It asserts that:
  - (a) removing an `expect(` line yields `additionalContext` naming the removed assertion, and `jq -e '.hookSpecificOutput.permissionDecision'` fails (the field is absent);
  - (b) with `rules.test-weaken-block: error`, adding `it.skip` yields `permissionDecision: deny`, and the same edit carrying `test-change: <reason>` has no decision;
  - (c) a forced script error gives exit 0 with no decision;
  - (d) a hang hits the internal timeout and gives exit 0.

### Phase 7: Rules skill and pointers (parallel-safe) [TODO]

- New model-invoked `plugins/testing/skills/test-value/SKILL.md`, kept to at most 120 lines because
  every preload carries it (the figure is judgment). It covers where expected values must come from,
  the taxonomy, Pocock's examples, and when a mock is acceptable (the EF Core carve-out). It ends
  with `## Next`.
- Add `testing:test-value` to the `skills:` list of `plugins/implementation/agents/implementer.md`,
  `plugins/implementation/agents/phase-verifier.md` and `plugins/review/agents/code-reviewer.md`. Add
  one `phase-verifier` line saying new tests are checked against it.
- One "(if installed)" pointer line each in `testing:write`, `testing:plan` and `testing:diagnose`.
- `debugging:debug` Phase 5: the regression test's expected value comes from the bug report.
- Version bumps and CHANGELOG entries for `implementation`, `review` and `debugging`.

**Sanity Check:**

- `grep -l 'testing:test-value' plugins/implementation/agents/implementer.md plugins/implementation/agents/phase-verifier.md plugins/review/agents/code-reviewer.md | wc -l` returns 3.
- `grep -c 'testing:test-value' plugins/testing/skills/write/SKILL.md plugins/testing/skills/plan/SKILL.md plugins/testing/skills/diagnose/SKILL.md` returns 1 for each file.
- `awk '/^## Phase 5/,/^## Phase 6/' plugins/debugging/skills/debug/SKILL.md | grep -c 'bug report'` is at least 1.
- `wc -l < plugins/testing/skills/test-value/SKILL.md` is at most 120.
- `bash scripts/check-changed-skills.sh origin/main`, `bash scripts/check-skill-count-claims.sh --check`, `bash scripts/check-changelog-parity.sh --check` and `bash scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.

### Phase 8: Precision run and release [TODO]

- User-approval gate: this phase reads other repos and a fleet host.
- Pre-check which wave-1 languages each candidate repo holds. Run the scanner over the whole tree of
  `melodic-software/claude-code-plugins`, `melodic-software/medley` and `melodic-software/ci-runner`,
  read-only, together covering every wave-1 language in real use.
- Classify every finding as true or false positive in `docs/topics/tautological-tests/precision-run.md`.
- Each false positive becomes a good corpus fixture before it is fixed. The PR checklist enforces
  this by process (acceptance criterion 5).
- Blocking stays off. The report names which deterministic rules qualify to block, excluding
  `bash-harness` zero-assertion. That switch ships in a later minor version (D4).
- Bump `testing` to 0.10.1 with a CHANGELOG entry, and update its README and plugin description.

**Sanity Check:**

- `grep -cE '^\| (claude-code-plugins|medley|ci-runner) \|' docs/topics/tautological-tests/precision-run.md` returns 3.
- `bash scripts/run-plugin-tests.sh` exits 0.
- `bash scripts/check-changelog-parity.sh --check` and `bash scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.
- `jq -r .version plugins/testing/.claude-plugin/plugin.json` prints `0.10.1`.

### Release 2 outline: task-end judge and mutation scope [TODO]

Re-planned as its own sub-topic PLAN once the Release 1 precision data exists.

- A Stop or SubagentStop judge on a different model reviews tests still in doubt. It judges
  provenance only, answers FLAG, PASS or UNKNOWN with quoted evidence, and stays advisory. First
  item: probe whether the `prompt` or `agent` hook types fit (Brief open question).
- A labeled calibration set, reviewed by two people.
- `mutation-testing:audit` gains a scope that mutates the production code the changed tests exercise,
  and classifies each survivor.
- Resolve which ImpossibleBench variant the ">79%" figure belongs to (arXiv 2510.20270, Section 5)
  before quoting it anywhere.
- Evaluate PostToolUse `bashEditDiff` (beta) to narrow the Bash-write gap.

**Sanity Check:**

- `test -f docs/topics/tautological-tests-judge/PLAN.md` passes before any Release 2 code lands.

### Release 3 outline: cleanup, split mode, wave 2 [TODO]

- `testing:cleanup` reads audit findings and applies the per-test order (Q9). It runs a mutation check
  before and after, with one PR per module or folder.
- Opt-in split mode (Q3): a spec-only test-writer subagent, a validity check before the tests are
  frozen, and an implementer that cannot edit them.
- Wave 2 adapters: Rust, Java/Kotlin and Go testify. The ast-grep backend comes in only if research
  switch S1 fires.

**Sanity Check:**

- `test -f docs/topics/tautological-tests-cleanup/PLAN.md` passes before any Release 3 code lands.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| ast-grep as the scanner engine | No PowerShell grammar ships; adds an 8-16 MB install to every consumer | A prebuilt PowerShell grammar ships, or ast-grep is on most fleet machines (research S2, S3) |
| Semgrep | About 1 s per file, a 365 MB install, and PowerShell needs the paid edition | Never on the hook path; a CI-only cross-file rule might use it (S4) |
| JSON adapters read with `jq` | Consumers would write two formats. Sibling hooks already use `jq` behind a notice, so the dependency itself is not the blocker | The YAML-subset loader fails its portability tests under mawk |
| Broad hook fallback filter for consumer globs | Needs a bare `test/` pattern, which Q6 forbids | Q6 is revised through an interview |
| `rule-lint-missing` as a scanner rule | It reads lint config, not test bodies, and has no answer for Bash, Pester or Go | A lint config needs per-file findings |
| Per-case checks for hand-rolled Bash | Only 1 of 461 Bash test files here defines test functions | A shared case helper becomes common in the fleet |

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The engine refactor changes existing findings | Med | High | Phase 1 parity run per subdirectory and over a real tree, under gawk and mawk |
| The hook driver is slow on Windows Git Bash (about 46 ms per call on WSL; S about 80 ms on Windows) | Med | Med | Phase 2 p95 budget (150 ms WSL, 1 s Windows), measured before later phases build on it |
| Lexical rules false-fire on real suites | High | Med | All new rules advisory; Bash ceiling in Phase 3; precision run; false-positive-to-fixture rule |
| Bash and MCP writes bypass the hooks | Known | Med | Guardrails `block-hook-bypass` covers shell writes; the audit and the Release 2 judge cover the rest |
| Adapter globs drift from hook filters, or overlap | Med | Med | `gen-hook-filters.sh --check` with dedup and overlap tests |
| The consumer hook entry gets no plugin variables | Med | Low | Phase 5 probe and `[FALLBACK]` shim |

## Blast radius

HIGH.

- Opt-in hooks on every test-file write in any consumer repo.
- A refactor of a scanner that CI and `code-reviewer` depend on.
- Agent preloads in three other plugins.
- Four plugin version bumps.

## Stress-test summary

A fresh-context plan-reviewer (20 findings: 2 critical, 14 important) and a `/planning:devils-advocate`
pass (15 findings: 1 critical, 7 high) both ran, and both critical findings were confirmed against the code:

- The scanner takes no path argument and prunes `evals/fixtures`, so the first parity check was vacuous.
- A userConfig option cannot be read by a hook `if` row.

The revised plan applies every confirmed finding. Three of them need the user at approval: the
acceptance-criterion-10 wording, moving `rule-lint-missing` into setup, and the Phase 8 steps outside
this checkout.

## Execution shape

- Phases 1-6 and 8 run in order on the `testing` plugin: each changes the scanner or its hooks, and
  they share `cant-fail-scan.{sh,awk}`, `hooks.json` and the corpus.
- Phase 7 touches only `plugins/testing/skills/test-value/`, three agent files, three skill pointer
  lines and `debugging:debug`. It can run in parallel from Phase 1 onward. Two agents instead of one
  roughly doubles token use for that stretch.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | engine refactor, parity judgment |
| 2 | main session | hook contract and live probes |
| 3 | sub-agent worker per adapter group (bash+pwsh, go+node-test, C#, Python) after the shell lexer lands | mechanical adapter data plus fixtures; file-disjoint by `adapters/<id>.yaml` and `corpus/<id>/` |
| 4 | main session | Pocock mapping may need a user decision |
| 5 | main session | config contract |
| 6 | sub-agent worker | follows the Phase 2 pattern |
| 7 | sub-agent worker, parallel | file-disjoint from 1-6 |
| 8 | main session | outside-checkout approval |

## Open questions

- None beyond the approval items listed at Step 5.

## Handoff to implementation

Approval: attended. Approved by Kyle Sexton on 2026-09-28. Each listed change was answered
separately: X1, reword acceptance criterion 10; X2, lint presence moves to `/testing:setup check`;
X3, the wave-1 amendment is confirmed; X4, the fleet-host and other-repo steps are approved, with
each run gated again when it happens.

### User-approval gates

- Phase 2 and Phase 8: running on a Windows fleet machine through `/fleet:reach`.
- Phase 8: scanning `medley` and `ci-runner`, read-only.
- Phase 4: any Pocock example that no deterministic rule can catch.
- Phase 5 `[FALLBACK]`: the consumer-entry shim, if the probe shows plugin variables are missing.

### Execution shape ([EXEC-SHAPE] tagged)

- `[EXEC-SHAPE]` PR slicing, each opened as a draft:
  - PR A: Phase 1 (testing patch bump to 0.9.5).
  - PR B: Phases 2-6 (testing minor bump to 0.10.0, committed per phase).
  - PR C: Phase 7 (implementation, review and debugging bumps).
  - PR D: Phase 8 (testing patch bump to 0.10.1).
- `[EXEC-SHAPE]` Phase 3 fan-out scope fences:

| Worker | ALLOWED | FORBIDDEN |
|---|---|---|
| bash+pwsh | `adapters/{bash-harness,bash-bats,pwsh-pester}.yaml`, `corpus/{bash-harness,bash-bats,pwsh-pester}/**` | awk engine, `cant-fail-scan.test.sh`, `GRID.md`, PLAN.md |
| go+node | `adapters/{go-testing,js-node-test,js-playwright}.yaml`, `corpus/` same ids | same |
| C# | `adapters/{cs-nunit,cs-mstest}.yaml`, `adapters/cs-xunit.yaml` vocabulary, `corpus/cs-*/**` | same |
| Python | `adapters/py-unittest.yaml`, `corpus/py-unittest/**` | same |

  The main session owns the engine, the test file, `GRID.md` and PLAN.md, and merges the worker
  output. Sequential fallback: if a worker breaches its fence or cannot finish, the main session does
  that adapter group itself.

### Mechanical work

- Commit per phase with `git commit -F - --cleanup=verbatim`.
- Tick the phase tag here in the same commit.
- Run `bash scripts/run-plugin-tests.sh` before each push.
