# Test-value guards: stop tautological AI-written tests

Status: APPROVED by Kyle Sexton 2026-09-28; amendment A1-A14 approved 2026-09-28 and re-approved
2026-09-29 ([Approval](#approval)). Phase 1 is on main (#5205). Phases 2 and 3 are implemented on
branch `feat/testing-test-scan-hook`, rebased onto `origin/main` (`32163c726`), which has no PR
yet. Phases 4a to 8 and Releases 2 and 3 have not started; this document is their approved plan,
and its user gates still hold. It graduated here from the task branch's `docs/topics/tautological-tests/` contract slice
(`PLAN.md` and `design/design-resolution.md`). Paths below under `docs/topics/tautological-tests/`
name working files on an implementing branch; their outcomes graduate into this spec before that
branch merges. Plugin versions are stated relative to main: "one patch above main at merge" means
the number is picked when the PR merges, not here.

## Contents

- [Brief](#brief)
- [Design contracts](#design-contracts)
- [Plan](#plan)
- [Blast radius](#blast-radius)
- [Execution shape](#execution-shape)
- [Approval](#approval)

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
  assertion-free tests, self-identical assertions and inert assertions. Everything else stays
  advisory until measured. The LLM judge never blocks until a calibration set exists.
  - Amended 2026-09-28 at plan amendment (A1, A13): inert assertions join the blocking tier. They
    stay advisory for all of Release 1, and become eligible to gate `--check` in a later minor
    version once the Phase 8 precision run shows 0 false positives on the three repos, as the rest
    of Q12 requires (D4). A separate advisory "change-detector" category holds tests that can fail
    but pin structure (constant restatement, source-text reads); it sits outside the can't-fail
    gate.
- Q5: Wave 1 is C#/.NET (xUnit, NUnit, MSTest), JS/TS (Vitest, Jest, Playwright), Python (pytest)
  and Bash (bats, `*.test.sh`). Wave 2 is Go, Rust and Java/Kotlin.
  - Amended 2026-09-28 during planning. User: "we need to make sure Bash is covered. I mean, all
    the languages that we use, and also how the plugin is designed to be extensible and
    configurable for other languages and platforms/frameworks." A fleet inventory found hand-rolled
    Bash (~800 files), C# xUnit v3, Vitest and `node:test`, Python unittest and pytest, PowerShell
    Pester (65 files) and Go stdlib `testing` (65 files). Wave 1 adds Pester, `node:test`,
    unittest and Go stdlib `testing`. Wave 2 keeps Rust, Java/Kotlin and Go testify. Languages
    and frameworks are added through declarative adapters ([Design contracts](#design-contracts)).
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

- Pocock's examples (ids from `.work/tautological-tests/phase4-pocock-examples.md`) must be
  flagged. An example counts as flagged when a deterministic rule catches it, or, when no text
  signal exists, when it is recorded as a Release 2 judge calibration candidate (amended at A8):
  - rule-flagged: constant restatement (T1, the 280-character limit), a test reading source text to
    check order (T2), and the `tests.md` and SKILL anti-patterns with a text signal (M1, M4, M7's
    sole `toBeDefined()` oracle, M8, S2, S4);
  - judge cases: M5, M6, S3 and S5, and the candidates T3 (the AudioContext mock), M2, M3 and M7's
    database side channel.
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
  skill's `tests.md`, both fetched into `.work/tautological-tests/phase4-pocock-examples.md`. The
  talk code was on slides, so T1-T3 are reconstructed from captions.
- Hook `if` filters skip the spawn when they do not match (hooks docs, medium confidence). The plan
  re-verifies this against the current Claude Code version.
- Files written through Bash scripts or MCP tools bypass the hooks. Guardrails covers shell writes;
  MCP and scripts are a known gap, caught later by the audit and the judge.
- No published LLM judge for tautology has been validated against human labels, so the judge
  stays advisory until the local labeled set exists.
- Surface-page defects seen during the interview are tracked separately (issue #5009 and #5191);
  they do not affect this plan.

### Out-of-scope

- Editing consumer CLAUDE.md or AGENTS.md files.
- Red-first (TDD-order) enforcement with a model call per edit, as TDD Guard and Probity do.
- Blocking on any LLM-judge verdict before calibration.
- Wave 2 languages, cleanup and split mode in the first release.
- Separate maintenance found during research: `mutation-testing` `tooling.md` staleness and the
  `testing:audit` coverage-counter discrepancy.
- Pseudo-tested code (G11): no static signal. Candidate follow-up, not filed: an extreme-mutation
  mode for `mutation-testing:audit`; filing it needs the user's OK (A12).
- `plugins/architecture/skills/improve/research/deepening/dependencies.md:15` recommends SQLite and
  PGLite stand-ins, which contradicts the `tdd` Khorikov reference. A separate follow-up work item,
  not filed (A7).
- A retro-catalog pointer (adoption ledger row 17): `review:audit-enforceability` does not route to
  scanner rules today (A9).

## Design contracts

The interview (Brief Q1-Q13) fixed the module boundaries: the work extends `testing`, with small
changes in `mutation-testing`, `review`, `implementation` and `debugging`. The user accepted an early
exit from full `/planning:design` on 2026-09-28 and asked for the plugin to be extensible to other
languages and frameworks. Evidence: `.work/tautological-tests/extensibility/RESEARCH.md` (engine
options, measured timings, adapter schema) and the fleet language inventory taken the same day.

### 1. Scanner engine: awk rules, lexers, block models, adapter data

The scanner stays pure bash plus POSIX awk. Measured at 4-5 ms per file, with nothing to install.
All knowledge of individual languages and frameworks moves out of the awk source and into
declarative adapter files.

| Layer | Form | Closed or open | Contents |
|---|---|---|---|
| Rules | awk, language-neutral | closed (plugin release) | zero-assertion, recomputed-expectation, mock-only-oracle, plus the new rules in section 4 |
| Lexers | awk | closed | one per language: `js`, `cs`, `go`, `python`, `bash` (Bash and bats), `pwsh` (PowerShell, `<# #>` and here-strings); wave 2 adds Rust and Java/Kotlin |
| Block models | awk | closed | `brace`, `indent`, `file` (hand-rolled Bash, which has no per-case marker) |
| Adapters | data files | open (consumers add) | globs, detection, test start, skips, assertion calls and idioms, delegation, mocks, snapshots, equality forms |

There is no shared lexer family: every language has its own lexer, because JS and C# need
different comment and string maskers. Adding a language whose lexer exists means writing an adapter
that names that lexer and a block model. A new lexer or block model needs a plugin release.

### 2. Adapter file contract

- Location: `plugins/testing/skills/audit/adapters/<id>.yaml`. Consumer adapters live in
  directories named by `adapter_dirs` and use the same schema.
- Format: a restricted YAML subset: block maps, block lists, one-line flow lists, plain or
  single-quoted scalars, and dotted keys. The loader strips `\r` and validates regexes against a
  portable ERE subset for gawk, mawk and BSD awk. The awk loader parses exactly that subset and
  rejects anything else with exit 2, naming the file and line. This adds no dependency (`jq`, `yq`,
  Python). The loader's header comment (`scripts/adapter-load.awk`) is the schema of record.
- Fields: `id`, `extends`, `language`, `block_model`, `advisory`, `files`, `detect.any_regex`,
  `test_start`, `test_skip`, `body_skip`, `suite_skip`, `assertion.calls`, `assertion.idioms`,
  `assertion.async`, `assertion.inert`, `assertion.weak`, `assertion.count`, `assertion.fail`,
  `delegation`, `mock.create`, `mock.verify`, `mock.strip`, `snapshot`, `equality.call2`,
  `equality.receiver`, `equality.pipeline`, `property_markers`, `rules_off`, `suppress_marker`.
  - `language` names the lexer: `js`, `cs`, `python`, `bash`, `pwsh`, `go`.
  - `block_model` is `brace`, `indent` (Python only) or `file` (Bash only: the whole file is one
    test, for a harness with no per-case marker). C# `brace` uses the attribute-then-signature
    state machine; every other `brace` adapter opens a block on its `test_start` line.
  - `advisory: true` keeps the adapter's findings out of the `--check` gate unless `--strict`.
  - `test_skip` matches the start line or the decorators and attributes above it; `body_skip`
    matches inside the body (`t.Skip`, bats `skip`, Playwright `test.skip(`).
  - `assertion.idioms` and `delegation` match raw text, strings and comments included, over a
    window of three consecutive body lines. The other regex fields match masked code.
  - Every list field is a list of EREs, except `files` (basename globs), `equality.call2` (helper
    names matched as substrings; for `bash` and `pwsh` also the command form `fn A B`),
    `equality.receiver` (`<wrapper>.<matcher>`, as in `expect.toBe`), `rules_off` (rule slugs) and `equality.pipeline`
    (literal matchers after a pipe, as in `A | Should -Be B`).
  - `extends: <id>` inherits every field the adapter does not set. When several adapters claim a
    file, the first in load order (sorted file names) whose `detect.any_regex` matches wins;
    otherwise the first claimant with no `detect` list, and failing that the first claimant.
- `additional_test_blocks` is reserved: the loader rejects it until engine code reads it, so a
  value is never dropped silently.
- `assertion.async` matches the start of a statement that asserts nothing unless it is awaited or
  returned (an unawaited `expect(p).resolves`, a Playwright web-first matcher, `Assert.ThrowsAsync`
  in xUnit). `assertion.inert` matches the start of a statement that looks like an assertion and
  never asserts (Python `m.called_once_with(`, a bare `.Should();`). Both feed
  `rule-inert-assertion`; language-syntax forms (the Python tuple assert, bats `run` and `!`) stay
  in the engine.
- `assertion.weak` and `snapshot` match a whole assertion call: a block whose only assertions they
  cover has a weak or a snapshot oracle (`rule-weak-oracle`, `rule-snapshot-only`). Two snapshot
  forms need their library in reach, which the engine checks as language syntax: C# `Verify(`
  counts only in a file that imports `VerifyXunit`, `VerifyNUnit`, `VerifyMSTest` or `VerifyTests`
  (or carries `[UsesVerify]`) and declares no `Verify` method of its own; Python `== snapshot`
  counts only when `snapshot` is a parameter of the test (the syrupy fixture).
  For `rule-recomputed-derived`, an input read only as a length (`.length`, `.Length`, `.Count`,
  `.size`, `len()`) or copied whole by a `{ ...x }` or `{**x}` spread is not an input.
  `assertion.count` matches a length or count check, which clears `rule-conditional-assertion` for
  a loop; `assertion.fail` matches a call that fails the test outright, which is the assertion of
  the `if` or `catch` around it.
- `property_markers` match any raw line of a file whose tests derive expected values on purpose
  (Hypothesis `@given`, fast-check, FsCheck, `testing/quick`); such a file never reports
  `rule-recomputed-derived`. `rules_off` lists rule slugs an adapter never reports:
  `js-playwright` turns off `recomputed-derived` (seed data), and the C#, Go and Pester adapters
  turn off `constant-restatement` (their constants need a declaration lookup).
- `astgrep_rules` is reserved and not implemented. It is research switch SW1: an optional
  ast-grep backend for one rule, added only when the fixture corpus shows awk missing
  argument-structure cases.

Wave-1 adapters, taken from the fleet inventory (Brief Q5 as amended 2026-09-28): `bash-harness`
(hand-rolled `*.test.sh`), `bash-bats`, `pwsh-pester`, `cs-xunit`, `cs-nunit`, `cs-mstest` (with
Shouldly, FluentAssertions, NSubstitute, Moq and Verify vocabulary), `js-vitest`, `js-jest`,
`js-node-test`, `js-playwright`, `py-pytest`, `py-unittest`, `go-testing`. Wave 2 is Rust,
Java/Kotlin and Go testify.

### 3. Test-file pattern list and `.claude/testing.yaml`

- One source: the union of every shipped adapter's `files:` globs. `hooks/hooks.json` `if` filters
  are generated from that union by `scripts/gen-hook-filters.sh`. A `--check` mode fails CI when the
  two drift. No bare `test/` or `tests/` folder pattern is allowed (Q6).
- `.claude/testing.yaml` resolves through the config-cascade layers: `~/.claude/testing.yaml`, then
  `${CLAUDE_PROJECT_DIR}/.claude/testing.yaml`, then `.claude/testing.local.yaml`. Merge semantics
  are additive: lists concatenate, and a scalar in a later layer overrides an earlier one. The
  resolver is a plugin-local script modeled on `plugins/docs-hygiene/scripts/resolve-config.sh`. It
  is not imported from that plugin (shell-test-helpers convention: no cross-plugin imports).
- Keys: `adapters.enable`, `adapters.disable`, `paths.include`, `paths.exclude`, `extend.<adapter>.<field>`,
  `adapter_dirs`, `rules.<rule-id>: off | warn | error`. `adapters.enable` is an allowlist and
  `adapters.disable` wins over it. `paths.include` walks past the scanner's directory prunes (never
  `.git` or `node_modules`), and an included file still needs an adapter that claims it.
  `rules.<rule-id>` takes `testing/audit/rule-<slug>` or `rule-<slug>`. A glob that starts with `*`
  is single-quoted, because a bare leading `*` is YAML alias syntax.
- Removals (`adapters.disable`, `paths.exclude`) apply inside the script, so hook and audit go silent
  with no plugin change.
- Additions (`paths.include`, consumer adapters with new globs) reach the audit at once. They reach
  the hook only through a consumer hook entry that `/testing:setup check` prints for pasting (Q6).
  The audit report lists any consumer glob that no hook filter covers, so a skip is never silent.

### 4. New scanner rules (release 1)

Rule IDs follow `testing/audit/rule-<name>` (detector-findings contract). Every new rule needs a
severity-crosswalk row and eval coverage.

Release 1 adds seven rules in three categories (A1). All seven are report-only in Release 1: their
findings print, and they gate neither `--check` nor `--check --strict`. Scope, tier and rung per
rule are in the Phase 4a table.

| Rule | Detects | Category |
|---|---|---|
| `rule-inert-assertion` | Python tuple assert, bare `.Should()`, unawaited or never-evaluated async matcher, bats `run` with no status check, Python mock attributes that are not assertions | blocking tier: eligible to gate `--check` in a later minor version after 0 false positives in Phase 8 (D4, A13) |
| `rule-constant-restatement` | expected value equals a literal defined in the production module the test imports, or a local literal tested with no call | change-detector |
| `rule-source-text-read` | test reads a tracked, non-test production source file as text (`readFileSync`, `open(...).read()`, `File.ReadAllText`, `Get-Content`, `cat`) | change-detector |
| `rule-conditional-assertion`, `rule-weak-oracle`, `rule-snapshot-only`, `rule-recomputed-derived` | Phase 4b | advisory |
| existing `rule-zero-assertion`, `rule-recomputed-expectation` | as today, now driven by adapters | gate `--check` as today; `rule-recomputed-expectation` is the blocking tier's existing rule (A1); any further blocking waits for the precision run (D4) |

### 5. Hooks

Both hooks are gated by `userConfig.test_guards_enabled` (boolean, default `false`), read in the
script as `CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED`. They are exec-form, with `if` filters
generated as described in section 3. A script error or timeout lets the edit proceed and logs the
failure.

| Hook | Event | Input | Output |
|---|---|---|---|
| `test-scan` | PostToolUse `Write\|Edit` | written file path; for Edit, the new hunk | findings whose test block overlaps the changed hunk (hook-precision rule 1), fed back through `additionalContext`. For a doubtful hit it asks the agent to state where the expected value comes from, in the same turn (Q7 tier 2). The first test-file write per file per session also injects the rules-skill note (Q2). |
| `test-weaken` | PreToolUse `Write\|Edit` | `old_string` and `new_string`, or the old file versus the new content | removed assertion, added skip, removed test block, or changed expected value. Release 1: allow and inject context that asks the agent for its reason. After the precision run, deleted or skipped tests may deny with a reason, and the agent retries with a `test-change: <reason>` marker (D5). |

Once-per-session state lives under `${CLAUDE_PLUGIN_DATA}`, keyed by `session_id`, `agent_id` and
the normalized file path. The marker is a file created with bash `noclobber` (`O_EXCL`), not `mkdir`, which is not atomic under uutils coreutils; markers older than 7 days are pruned.
`test-weaken` returns `additionalContext` with no `permissionDecision` field while advisory.

Lint-rule presence (eslint-plugin-jest/vitest/playwright, xUnit2021, NUnit2009, ruff PLR0124) is
reported by `/testing:setup check`, not by the scanner. It reads lint config, not test bodies, and
Bash, Pester and Go have no maintained rule.

The option gate uses exec-form `--require-true TEST_GUARDS_ENABLED`. A hook `if` row cannot read a
userConfig value, so while the option is off each matching test-file write starts one launcher
process that exits at once. Non-test paths start none.

### 6. Rules skill

`testing:test-value` is model-invoked. It holds the one statement of what makes a test worth
keeping: where expected values come from, the taxonomy, and Pocock's examples. Three things load
it: auto-invocation, a `skills:` preload in `implementer`, `phase-verifier` and `code-reviewer`, and
the hook note. Other skills carry a one-line pointer.

## Plan

### Goal

**What**: Release 1 of the Brief (prevention plus proof). The scanner is rebuilt on declarative
language adapters and covers every language the fleet uses. It gains seven new rules in three
categories (one blocking-tier rule, eligible to gate in a later minor version once Phase 8 shows 0
false positives; two change-detector; four advisory). All seven are report-only in Release 1. A
lint-presence check lands in `/testing:setup`. Two opt-in hook guards run on test files, and
one rules skill is preloaded where tests get written and reviewed. A committed fixture corpus
proves the rules flag bad tests and stay silent on good ones. Releases 2 and 3 are outlined and get
their own plans later.
**Why**: Agents write tests whose expected values come from the code under test. The current audit
flags 0 of 10 planted variants beyond its core rules, and nothing runs while a test is being written.
**Done when**: every Release 1 acceptance criterion in the Brief has a passing mechanical check in
CI, except the false-positive-becomes-a-fixture rule, which is enforced by process (Phase 8).
Acceptance criterion 1's judge half is satisfied by the `GRID.md` record; flagging those cases is
deferred to Release 2. The changed plugins are version-bumped with CHANGELOG entries, and the
precision-run report is committed.

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

On main: #5205 (squash `d6e040a4c`).

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
    reserved ([Design contracts](#design-contracts) section 2).
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
| [x] `plugins/testing/skills/audit/scripts/cant-fail-scan.awk` | MODIFY |
| [x] `plugins/testing/skills/audit/scripts/cant-fail-scan.sh` | MODIFY |
| [x] `plugins/testing/skills/audit/scripts/adapter-load.awk` | CREATE |
| [x] `plugins/testing/skills/audit/adapters/{js-vitest,js-jest,py-pytest,cs-xunit}.yaml` | CREATE |
| [x] `plugins/testing/skills/audit/scripts/parity-check.sh` | CREATE |
| [x] `plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` | MODIFY (loader, `--file` and precedence cases) |
| [x] `plugins/testing/skills/audit/scripts/mask-js.awk`, `runner-config-scan.awk` | KEEP |

**Sanity Check:**

- `bash plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` exits 0, and
  `git diff main -- plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh | grep -c '^-[^-]'` returns 0.
- `grep -cE '_ERE *=' plugins/testing/skills/audit/scripts/cant-fail-scan.awk` returns 0.
- `bash plugins/testing/skills/audit/scripts/parity-check.sh` exits 0 and prints `examined>0` for every run.

### Phase 2: `test-scan` hook, end to end on existing rules [IMPLEMENTED, not on main]

Implemented on branch `feat/testing-test-scan-hook`, which has no PR yet. The branch is rebased onto
`origin/main` (`32163c726`), without the three pre-squash Phase 1 commits.

The integration slice: an opt-in PostToolUse hook runs `cant-fail-scan.sh --file` on the written
test file and feeds findings back.

- Add `userConfig.test_guards_enabled` (boolean, default `false`) to `plugins/testing/.claude-plugin/plugin.json`.
- Copy `hooks/exec-bash.mjs` in through `scripts/sync-exec-bash.sh` and register it there.
- Add `plugins/testing/hooks/hooks.json`: an exec-form `test-scan` on PostToolUse
  `Write|Edit` (MultiEdit dropped: no `if` row can name it usefully), with `--require-true TEST_GUARDS_ENABLED` and `if` rows generated by
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
  - injects the rules-skill note once per `session_id` + `agent_id` + path, using a `noclobber`
    (`O_EXCL`) marker file under `${CLAUDE_PLUGIN_DATA}`, and prunes markers older than 7 days;
  - on a doubtful hit (`rule-recomputed-expectation`; `rule-constant-restatement` from Phase 4a and
    `rule-recomputed-derived` from Phase 4b), asks the agent to state where the expected value
    comes from, in the same turn (Q7 tier 2);
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
| [x] `plugins/testing/.claude-plugin/plugin.json` | MODIFY |
| [x] `plugins/testing/hooks/hooks.json` | CREATE |
| [x] `plugins/testing/hooks/exec-bash.mjs` | CREATE (synced copy) |
| [x] `scripts/sync-exec-bash.sh` | no change: it finds copies by glob |
| [x] `plugins/testing/hooks/test-scan.sh` + `test-scan.test.sh` | CREATE |
| [x] `plugins/testing/scripts/gen-hook-filters.sh` + `gen-hook-filters.test.sh` | CREATE |
| [x] `docs/topics/tautological-tests/probes.md` | CREATE |

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

### Phase 3: Wave-1 adapters for every fleet language [IMPLEMENTED, not on main]

Implemented on branch `feat/testing-test-scan-hook`, which has no PR yet.

- Add the `bash`, `pwsh` and `go` lexers and the `file` block model to the awk engine
  ([Design contracts](#design-contracts) section 1).
- `rule-recomputed-expectation` exists today for JS and Python only (`cant-fail-scan.awk:306,325,337`).
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

### Phase 4a: Pocock mapping, planted split, first three rules [IMPLEMENTED, not on main]

Implemented on branch `feat/testing-test-scan-hook`. `rule-constant-restatement` is `n/a` for
`cs-xunit`, `cs-nunit`, `cs-mstest`, `go-testing` and `pwsh-pester`: their constants are not
SCREAMING_SNAKE, so a finding needs a declaration lookup the engine does not have. NUnit
`Assert.ThrowsAsync` is not in `assertion.async`, because it returns a Task only from NUnit 5.

Inputs: `.work/tautological-tests/phase4-pocock-examples.md` (the Pocock mapping),
`.work/tautological-tests/pocock-critique/RESEARCH.md` with its `RESEARCH-gaps.md` (G1-G11) and
`RESEARCH-matrix.md` (bad and good forms per framework).

- First item: add a `GRID.md` row per Pocock example naming its rule or `judge`, as acceptance
  criterion 1 lists them. M7 gets two rows: `M7-weak` (rule) and `M7-side-channel` (judge). Judge
  cases live only as `GRID.md` rows, not corpus files, so the corpus loop and
  `check-orphaned-fixtures.sh` never see them. Each is recorded as a Release 2 judge calibration
  candidate; Release 2 builds its calibration set from them. An example that fits neither a rule
  nor the judge list goes to the user.
- Fixtures:
  - M1 is kept verbatim as a lexing fixture (it is invalid Jest: `jest.mock` takes a module path),
    beside a corrected runnable version. Each file's header says which one it is.
  - T1-T3 are re-authored. `tests.md` and SKILL snippets are copied verbatim, with no credit file;
    provenance lives only in `docs/upstream/mattpocock-skills.md`. Each Pocock bad fixture carries a
    `source: pocock <id>` tag, which traces test data to acceptance criterion 1 and is not a credit.
    Pocock fixtures for Phase 4b rules land in Phase 4b.
  - Every wave-1 framework gets a bad and a good fixture for each `RESEARCH-matrix.md` cell marked
    signal yes, for the rules each phase adds.
- Split the 12 planted tests from `.work/tautological-tests-verify/taxonomy/fx/` into one test per
  file under `corpus/planted/`, and commit them. Mark the variants the taxonomy says need reasoning.
- Rule categories (A1). All seven new rules are report-only in Release 1: their findings print, and
  they gate neither `--check` nor `--check --strict`, because Q4 keeps them advisory until measured.
  `--strict` keeps its current meaning (`rule-mock-only-oracle`,
  `plugins/testing/skills/audit/SKILL.md:42-44`).
  - Blocking tier: v1 self-identical `rule-recomputed-expectation` (existing, gates `--check`) and
    new `rule-inert-assertion`, covering unawaited or never-evaluated assertions (G3), bats `run`
    with no status check and a `!` not on the last line (G4), and Python mock attributes that are
    not assertions, such as `m.called_once_with` (G5). `rule-inert-assertion` is advisory for all
    of Release 1, and eligible to gate `--check` in a later minor version once the Phase 8
    precision run shows 0 false positives on the three repos (Q12, A13, D4).
  - Change-detector: these tests can fail, so they sit outside the can't-fail gate.
    - `rule-constant-restatement`, which also covers testing the fixture: a local literal as the
      subject, with no call (G8). A contract constant is exempted with the scanner's existing
      `cant-fail-ok:` annotation (`suppress_marker`; its default is set in `load_adapter` in `cant-fail-scan.awk`).
    - `rule-source-text-read`, which fires only when the path read is a tracked, non-test source
      file, and never when the test reads through a glob or directory walk (a policy test;
      `RESEARCH-matrix.md:151-153`). Without that gate, 107 grep lines in this repo's Bash tests
      are false positives.
  - Advisory: the four Phase 4b rules.
  - Not scanner rules: G7 (stub pass-through) and G10 (mocking types you don't own) go to the
    Release 2 judge. G11 is out of scope.
- Crosswalk tier and enforcement rung per rule (A14). Every "keep the detector" row uses rung
  `analyzer-pack-rule`, as the existing `ai-slop:audit` rows do.

| Rule | Tier (detector-findings crosswalk) | Rung and owner (`audit-enforceability` crosswalk) | Phase |
|---|---|---|---|
| `rule-inert-assertion` | IMPORTANT (can't fail) | `analyzer-pack-rule`, owner the test-framework analyzer pack already in the project: it mirrors xUnit2021, `valid-expect` and SC2314, as `rule-zero-assertion` does (`crosswalk.md:42`) | 4a |
| `rule-constant-restatement` | SUGGESTION (change-detector: can fail) | already deterministic: keep the `testing:audit` detector | 4a |
| `rule-source-text-read` | SUGGESTION (change-detector: can fail) | already deterministic: keep the `testing:audit` detector | 4a |
| `rule-conditional-assertion` | IMPORTANT (can't fail) | already deterministic: keep the `testing:audit` detector | 4b |
| `rule-recomputed-derived` | IMPORTANT (can't fail) | already deterministic: keep the `testing:audit` detector | 4b |
| `rule-snapshot-only` | SUGGESTION | already deterministic: keep the `testing:audit` detector | 4b |
| `rule-weak-oracle` | SUGGESTION | already deterministic: keep the `testing:audit` detector | 4b |
| `rule-flaky-passes-suite` (existing) | unchanged | already deterministic: keep the `testing:audit` detector; no analyzer pack reads Playwright `retries` against `failOnFlakyTests` (judgment) | 4b |
| `rule-only-not-forbidden` (existing) | unchanged | `analyzer-pack-rule`, owner the project's ESLint config: eslint-plugin-playwright `no-focused-test` flags a committed `test.only` (judgment; confirm the rule id when the row is written) | 4b |

- Red, then implement each rule. For each rule:
  - a detector-findings README crosswalk row at the tier above, and eval coverage;
  - positive and negative `Action` remedy assertions in every scope it fires in (detector-findings);
  - the README crosswalk counts, updated;
  - `evals.json` expectations, updated.
- Eval coverage for `rule-*` ids: `scripts/check-detector-eval-coverage.sh` registers only the
  `claude-config` pair (`PAIRS_DEFAULT`, `:238`) and discovers only `[A-Z]…[0-9]` ids, so it cannot
  see these rules. `cant-fail-scan.test.sh` asserts that every rule id the scanner can emit,
  extracted from the scanner and adapter sources, appears in a positive `evals.json` expectation.
- `test-scan.sh` wiring (Q7 tier 2): the doubtful-hit prompt at `test-scan.sh:101` matches only
  `rule-recomputed-expectation`. Extend it to `rule-constant-restatement`, with a
  `test-scan.test.sh` case. Phase 4b adds `rule-recomputed-derived` the same way.
- Source-text precision: scan this repo and record the `rule-source-text-read` true positives in a
  "This repo, source-text read" section of `docs/topics/tautological-tests/precision-run.md`.
- Commit 4a on its own.

**Sanity Check:**

- `bash plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` exits 0. It asserts that:
  - (a) for each 4a rule, `--check` and `--check --strict` both exit 0 on its bad fixture, and the
    finding prints;
  - (b) `rule-source-text-read` gives 0 findings on a test that reads a file it wrote itself, and on
    a test that reads through a glob or directory walk;
  - (c) a whole-tree run over a temp git repo holding the bad T2 fixture beside the tracked source
    it reads reports `rule-source-text-read`;
  - (d) a `rule-constant-restatement` bad form under a `cant-fail-ok:` line is reported as exempt;
  - (e) every rule id the scanner can emit appears in a positive `evals.json` expectation.
- `bash plugins/testing/hooks/test-scan.test.sh` exits 0, including a case where a
  `rule-constant-restatement` hit carries the doubtful-hit prompt.
- Every Pocock row in `GRID.md` names a rule or `judge`, and
  `for id in M5 M6 S3 S5 T3 M2 M3 M7-side-channel; do grep -qE "^\| $id \|.*judge" plugins/testing/skills/audit/evals/fixtures/corpus/GRID.md || echo "$id"; done`
  prints nothing.
- `CANT_FAIL_SCAN_ROOT=. bash plugins/testing/skills/audit/scripts/cant-fail-scan.sh | grep -c 'rule-source-text-read'` equals the count recorded in `precision-run.md` "This repo, source-text read".
- `bash plugins/testing/skills/audit/scripts/check-corpus-grid.sh`, `bash scripts/check-orphaned-fixtures.sh --check`, `bash scripts/check-detector-findings-crosswalk.sh --check`, `bash scripts/check-detector-eval-coverage.sh --check` and `bash scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.

### Phase 4b: Remaining rules, crosswalk rows, audit docs [IMPLEMENTED, not on main]

Implemented on branch `feat/testing-test-scan-hook`. All four rules are `n/a` for `bash-bats` and
`bash-harness`: shell `if` and `for` close with `fi` and `done`, derived and golden-file
provenance is invisible, and a shell check has no weak-matcher vocabulary. `rule-snapshot-only` is
`n/a` for `pwsh-pester` (a golden file read with `Get-Content`). NUnit `Assert.That(x,
Is.EqualTo(y))` is not parsed as an equality yet, so the NUnit derived pair uses
`ClassicAssert.AreEqual`.

- Advisory rules, report-only in Release 1 (A2, A4, A5):
  - `rule-conditional-assertion`: assertions only inside `if`, `catch` or a loop, with no length
    check (G1, G2);
  - `rule-weak-oracle`: a weak matcher as the sole oracle, or an over-broad exception check (G6,
    G9);
  - `rule-snapshot-only`, whose finding reads "snapshot is the only oracle: review it as code".
    It never fires on image forms (`toHaveScreenshot`), where visual comparison is the primary e2e
    oracle;
  - `rule-recomputed-derived`, with its own crosswalk row: an expected value derived from the same
    inputs as the call under test (`reduce`, `sum`, `a + b`). It exempts property-based tests
    (Hypothesis `@given`, fast-check `fc.assert`/`fc.property`, FsCheck, CsCheck, Go
    `testing/quick`) and the `js-playwright` adapter, where the expected value comes from seed
    data. The exemption is judgment, not research-proven.
- Each rule gets the Phase 4a per-rule items (tier from the Phase 4a table), its matrix fixtures,
  and the Pocock bad fixtures whose rule lands here (`M7-weak` among them).
  `rule-conditional-assertion` and `rule-weak-oracle` have no matrix section; their `GRID.md` cells
  are set red first, `pair` or `n/a: <reason>`.
- `test-scan.sh`: add `rule-recomputed-derived` to the doubtful-hit prompt, with a
  `test-scan.test.sh` case.
- `plugins/review/skills/audit-enforceability/context/crosswalk.md` (A11, A14): a row for every new
  rule, plus `rule-flaky-passes-suite` and `rule-only-not-forbidden`, which lack rows, each at the
  rung in the Phase 4a table. `review` gets a patch bump and CHANGELOG entry in PR B.
- `plugins/testing/skills/audit/SKILL.md`: update the description and add a rule table with tier and
  gating columns (the seven new rules: report-only in Release 1). Update the scanner `--help` text.
- Commit 4b on its own.

**Sanity Check:**

- `bash plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` exits 0. It asserts that:
  - (a) for each 4b rule, `--check` and `--check --strict` both exit 0 on its bad fixture, and the
    finding prints;
  - (b) the snapshot-only finding contains `snapshot is the only oracle: review it as code`, and a
    `toHaveScreenshot` test gives 0 findings;
  - (c) a `rule-recomputed-derived` bad form inside a `@given`, `fc.property` or `testing/quick`
    test, or in a `js-playwright` file, gives 0 findings;
  - (d) an assertion inside a loop with a length check gives 0 findings
    (`rule-conditional-assertion`);
  - (e) `toBeDefined()` beside a value assertion gives 0 findings (`rule-weak-oracle`);
  - (f) the Phase 4a eval-coverage assertion holds for all seven rules.
- `bash plugins/testing/hooks/test-scan.test.sh` exits 0, including a case where a
  `rule-recomputed-derived` hit carries the doubtful-hit prompt.
- Acceptance criterion 1, per id:
  `for id in T1 T2 M1 M4 M7-weak M8 S2 S4; do grep -rlw "source: pocock $id" plugins/testing/skills/audit/evals/fixtures/corpus/*/bad | xargs -r grep -l 'expect: rule-' | grep -q . || echo "$id"; done`
  prints nothing, and each file found names in `expect:` the rule its `GRID.md` row names.
- `` grep -c 'keep the `testing:audit` detector' plugins/review/skills/audit-enforceability/context/crosswalk.md `` returns 7 (six new rules plus `rule-flaky-passes-suite`), and the `rule-inert-assertion` and `rule-only-not-forbidden` rows name `analyzer-pack-rule`.
- `for r in inert-assertion constant-restatement source-text-read conditional-assertion recomputed-derived snapshot-only weak-oracle; do bash plugins/testing/skills/audit/scripts/cant-fail-scan.sh --help | grep -q "rule-$r" || echo "$r"; done` prints nothing, and so does the same loop over `plugins/testing/skills/audit/SKILL.md`.
- `bash plugins/testing/skills/audit/scripts/check-corpus-grid.sh`, `bash scripts/check-orphaned-fixtures.sh --check`, `bash scripts/check-detector-findings-crosswalk.sh --check`, `bash scripts/check-detector-eval-coverage.sh --check` and `bash scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.

### Phase 5: Config cascade and `/testing:setup` [IMPLEMENTED, not on main]

Implemented on branch `feat/testing-test-scan-hook`. The test-scan p95 with a config file present
was measured only under load (181-196 ms at load 22-27, where the pre-change code measured 164-189
ms); the idle re-measure against the 150 ms budget moves to Phase 8.

- `plugins/testing/scripts/resolve-config.sh` merges `~/.claude/testing.yaml`,
  `.claude/testing.yaml` and `.claude/testing.local.yaml` additively. It is modeled on
  `plugins/docs-hygiene/scripts/resolve-config.sh`, not imported from it.
- The scanner and both hooks honor `adapters.enable`, `adapters.disable`, `paths.include`,
  `paths.exclude`, `extend`, `adapter_dirs` and `rules.<id>`.
- Path globs use one matcher, specified with tests: `**` matches across `/`, `*` does not, and paths
  are normalized first.
- Probe whether a consumer settings hook receives `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_OPTION_*`.
  Record the result in `probes.md`. If it does not, the printed consumer entry passes `--enabled` and
  locates the plugin through a stable shim `[FALLBACK]`. Taken: Claude Code 2.1.284 gives a settings
  hook only `CLAUDE_PROJECT_DIR` (probes.md), so the entry passes `--enabled` and finds the newest
  cached `testing/*/hooks/test-scan.sh`.
- New `plugins/testing/skills/setup/SKILL.md`, `check | apply`, with
  `disable-model-invocation: true` (modeled on `plugins/mutation-testing/skills/setup`). `check`
  prints:
  - the resolved config;
  - lint-rule presence per language: eslint-plugin-jest/vitest/playwright, xUnit2021, NUnit2009,
    ruff PLR0124. Bash, Pester and Go are marked "no maintained rule". A missing test-lint rule
    (eslint-plugin-jest/vitest `valid-expect`, xUnit2021, ruff PT and F631) is reported as a
    finding, not a neutral absence (adoption ledger row 18, A13);
  - the optional instruction line to paste (Q2);
  - a consumer hook entry for any added glob that no hook filter covers (Q6).
- The audit report lists consumer globs that no hook filter covers.

**Sanity Check:**

- `bash plugins/testing/scripts/resolve-config.test.sh` exits 0. It covers layer order, list concatenation, `**` matching and a Windows-style path.
- A `cant-fail-scan.test.sh` case writes `.claude/testing.yaml` containing an `exclude` list with `'**/*.test.ts'`. It asserts 0 findings from the scanner and no `test-scan.sh` output for a bad `.test.ts` fixture.
- A setup test runs `check` and a scripted `apply` in a temp repo and asserts that no file named `CLAUDE.md` or `AGENTS.md` changed.
- `grep -c 'CLAUDE_PLUGIN_ROOT' docs/topics/tautological-tests/probes.md` is at least 1.
- `bash scripts/check-changed-skills.sh origin/main` exits 0.

### Phase 6: `test-weaken` hook [IMPLEMENTED, not on main]

Implemented on branch `feat/testing-test-scan-hook`. Detection reads a new scanner mode,
`cant-fail-scan.sh --file <path> --inventory <text>...`, so no token list is copied. `suite_skip`
(`describe.skip`) is not yet counted as an added skip. p95 was measured only under load (194-219
ms at load 33-36); the idle re-measure moves to Phase 8.

- PreToolUse on `Write|Edit`, with the same option gate, filters and precision rules as `test-scan`.
- Compares old and new content to detect a removed assertion, an added skip marker (adapter
  `test_skip`), a removed test block, or a changed expected literal.
- Release 1 output: `additionalContext` asking for the reason, with no `permissionDecision` field
  (`allow` would skip the user's permission prompt).
- The deny path for deleted or skipped tests sits behind `rules.test-weaken-block: error`, which is
  off by default and stays off in Release 1 (D4, D5). With it on, an edit carrying a
  `test-change: <reason>` marker gets context only, with no decision. The key is
  `rules.test-weaken-block` (or `rule-test-weaken-block`), and only `error` changes behavior.
- Known limitation, stated in the skill: the agent can write that marker itself. The marker makes
  the reason visible to reviewers; it does not prove the reason.

**Sanity Check:**

- `bash plugins/testing/hooks/test-weaken.test.sh` exits 0. It asserts that:
  - (a) removing an `expect(` line yields `additionalContext` naming the removed assertion, and `jq -e '.hookSpecificOutput.permissionDecision'` fails (the field is absent);
  - (b) with `rules.test-weaken-block: error`, adding `it.skip` yields `permissionDecision: deny`, and the same edit carrying `test-change: <reason>` has no decision;
  - (c) a forced script error gives exit 0 with no decision;
  - (d) a hang hits the internal timeout and gives exit 0.

### Phase 7: Rules skill and pointers [TODO]

Starts after PR B merges ([Execution shape](#execution-shape)).

- New model-invoked `plugins/testing/skills/test-value/SKILL.md`, kept to at most 120 lines because
  every preload carries it (the figure is judgment). It ends with `## Next`. It covers (A6):
  - the expected value names its independent source (literal, worked example, spec, bug report,
    hand-computed value); no independent source means no unit test;
  - call-count or interaction checks are legitimate at unmanaged, state-changing boundaries
    (Khorikov);
  - a managed database uses a real instance, and a direct DB read after the act step is
    legitimate state verification. The named exception is the EF Core carve-out: mocking
    `DbContext` is acceptable for non-query writes;
  - refactoring stays in the TDD loop (Beck, Canon TDD step 4), not outside it as Pocock's skill
    says;
  - the taxonomy, with examples keyed to rule ids.

  The Khorikov, Beck step 4 and EF Core carve-out claims each carry the skill-bodies four-part
  verification record (claim, basis, as-of date, recheck trigger), within the 120-line cap.
- Existing copies: `plugins/testing/skills/write/context/write.md:78` becomes a pointer to
  `testing:test-value`. `plugins/review/agents/code-reviewer.md:56` keeps its scan-deference logic
  and drops its list of sources. The `tdd` reference stays as is.
- Add `testing:test-value` to the `skills:` list of `plugins/implementation/agents/implementer.md`,
  `plugins/implementation/agents/phase-verifier.md` and `plugins/review/agents/code-reviewer.md`. Add
  one `phase-verifier` line: when the diff adds or changes tests, a new expected value with no named
  source is reported as a finding outside the brief, not as a PASS/FAIL verdict.
- One "(if installed)" pointer line each in `testing:write`, `testing:plan` and `testing:diagnose`,
  and a `## Next` section in each, which none has today. Successors: `testing:write` names
  `testing:audit`; `testing:plan` and `testing:diagnose` name `testing:write`. None names
  `testing:test-value`, so each file keeps exactly one `testing:test-value` line.
- `debugging:debug` Phase 5 body (`SKILL.md` lines 140-160): the regression test's expected value
  comes from the bug report.
- `plugins/testing/README.md`: line 43 still says the plugin declares no userConfig, and the skill
  count must match the skills on disk.
- Version bumps and CHANGELOG entries for `testing` (the new skill, the pointer lines and the
  README), `implementation`, `review` and `debugging`, each one patch above main at merge.

**Sanity Check:**

- `grep -l 'testing:test-value' plugins/implementation/agents/implementer.md plugins/implementation/agents/phase-verifier.md plugins/review/agents/code-reviewer.md | wc -l` returns 3.
- `grep -c 'testing:test-value' plugins/testing/skills/write/SKILL.md plugins/testing/skills/plan/SKILL.md plugins/testing/skills/diagnose/SKILL.md` returns 1 for each file, and so does `grep -c '^## Next'` on the same files.
- `grep -c 'testing:test-value' plugins/testing/skills/write/context/write.md` is at least 1, and `grep -c 'no userConfig' plugins/testing/README.md` returns 0.
- `grep -c 'outside the brief' plugins/implementation/agents/phase-verifier.md` is at least 1.
- `awk '/^## Phase 5/,/^## Phase 6/' plugins/debugging/skills/debug/SKILL.md | grep -c 'bug report'` is at least 1.
- `wc -l < plugins/testing/skills/test-value/SKILL.md` is at most 120, and `grep -ci 'recheck' plugins/testing/skills/test-value/SKILL.md` is at least 3 (one record each for Khorikov, Beck step 4 and the EF Core carve-out).
- `grep -A3 '^## Next' plugins/testing/skills/write/SKILL.md | grep -c 'testing:audit'` is at least 1, and so is `grep -A3 '^## Next' <file> | grep -c 'testing:write'` for the `plan` and `diagnose` SKILL.md files.
- `bash scripts/check-changed-skills.sh origin/main`, `bash scripts/check-skill-count-claims.sh --check`, `bash scripts/check-changelog-parity.sh --check` and `bash scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.
- `git diff origin/main -- plugins/testing/.claude-plugin/plugin.json | grep -c '^+.*"version"'` returns 1.

### Phase 8: Precision run and release [TODO]

- User-approval gate: this phase reads other repos and a fleet host.
- Pre-check which wave-1 languages each candidate repo holds. Run the scanner over the whole tree of
  `melodic-software/claude-code-plugins`, `melodic-software/medley` and `melodic-software/ci-runner`,
  read-only, together covering every wave-1 language in real use.
- Classify every finding as true or false positive in `docs/topics/tautological-tests/precision-run.md`.
  The report shows examined-file counts per adapter. A rule with 0 findings in a language where its
  forms never occur is marked "unmeasured" there, not "qualifies".
- Each false positive becomes a good corpus fixture before it is fixed. The PR checklist enforces
  this by process (acceptance criterion 5).
- Blocking stays off. The report names which deterministic rules qualify to block, excluding
  `bash-harness` zero-assertion. That switch ships in a later minor version (D4). It includes
  `rule-inert-assertion` gating `--check`, once the report shows it at 0 false positives on the
  three repos (A13).
- Bump `testing` one patch above main at merge, with a CHANGELOG entry, and update its README and
  plugin description.

**Sanity Check:**

- `grep -cE '^\| (claude-code-plugins|medley|ci-runner) \|' docs/topics/tautological-tests/precision-run.md` returns 3.
- `grep -c 'examined' docs/topics/tautological-tests/precision-run.md` is at least 1, and no rule is marked "qualifies" for a language where the report marks it "unmeasured".
- `bash scripts/run-plugin-tests.sh` exits 0.
- `bash scripts/check-changelog-parity.sh --check` and `bash scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.

### Release 2 outline: task-end judge and mutation scope [TODO]

Re-planned as its own sub-topic PLAN once the Release 1 precision data exists.

- A Stop or SubagentStop judge on a different model reviews tests still in doubt. It judges
  provenance only, answers FLAG, PASS or UNKNOWN with quoted evidence, and stays advisory. It
  proposes test fixes and waits for approval; it never commits them (Q9, A10). First item: probe
  whether the `prompt` or `agent` hook types fit (Brief open question).
- A labeled calibration set, reviewed by two people. It starts from the Phase 4a `judge` rows, plus
  G7 (stub pass-through) and G10 (mocking types you don't own).
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
  switch SW1 fires.

**Sanity Check:**

- `test -f docs/topics/tautological-tests-cleanup/PLAN.md` passes before any Release 3 code lands.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| ast-grep as the scanner engine | No PowerShell grammar ships; adds an 8-16 MB install to every consumer | A prebuilt PowerShell grammar ships, or ast-grep is on most fleet machines (research switches SW2, SW3) |
| Semgrep | About 1 s per file, a 365 MB install, and PowerShell needs the paid edition | Never on the hook path; a CI-only cross-file rule might use it (switch SW4) |
| JSON adapters read with `jq` | Consumers would write two formats. Sibling hooks already use `jq` behind a notice, so the dependency itself is not the blocker | The YAML-subset loader fails its portability tests under mawk |
| Broad hook fallback filter for consumer globs | Needs a bare `test/` pattern, which Q6 forbids | Q6 is revised through an interview |
| `rule-lint-missing` as a scanner rule | It reads lint config, not test bodies, and has no answer for Bash, Pester or Go | A lint config needs per-file findings |
| Per-case checks for hand-rolled Bash | Only 1 of 461 Bash test files here defines test functions | A shared case helper becomes common in the fleet |

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The engine refactor changes existing findings | Med | High | Phase 1 parity run per subdirectory and over a real tree, under gawk and mawk |
| The hook driver is slow on Windows Git Bash (about 46 ms per call on WSL; S about 80 ms on Windows) | Med | Med | Phase 2 p95 budget (150 ms WSL, 1 s Windows), measured before later phases build on it |
| Lexical rules false-fire on real suites | High | Med | All new rules ship report-only; `rule-inert-assertion`, which mirrors shipped analyzers (xUnit2021, `valid-expect`, SC2314), becomes eligible to gate `--check` in a later minor version only after 0 false positives in Phase 8; Bash ceiling in Phase 3; precision run; false-positive-to-fixture rule |
| Bash and MCP writes bypass the hooks | Known | Med | Guardrails `block-hook-bypass` covers shell writes; the audit and the Release 2 judge cover the rest |
| Adapter globs drift from hook filters, or overlap | Med | Med | `gen-hook-filters.sh --check` with dedup and overlap tests |
| The consumer hook entry gets no plugin variables | Med | Low | Phase 5 probe and `[FALLBACK]` shim |

## Blast radius

HIGH.

- Opt-in hooks on every test-file write in any consumer repo.
- A refactor of a scanner that CI and `code-reviewer` depend on.
- Agent preloads in three other plugins.
- Four plugin version bumps.

## Execution shape

- Phases 1-6 (4a and 4b in order) run in order on the `testing` plugin: each changes the scanner or
  its hooks, and they share `cant-fail-scan.{sh,awk}`, `hooks.json` and the corpus.
- Phase 7 (PR C) starts after PR B merges; it does not run in parallel with Phases 1-6. It shares
  the testing `plugin.json`, CHANGELOG and README with PR B, and the test-value body keys its
  examples to rule ids that land in PR B.
- Phase 8 follows Phase 7.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | engine refactor, parity judgment |
| 2 | main session | hook contract and live probes |
| 3 | sub-agent worker per adapter group (bash+pwsh, go+node-test, C#, Python) after the shell lexers land | mechanical adapter data plus fixtures; file-disjoint by `adapters/<id>.yaml` and `corpus/<id>/` |
| 4a | main session | rule categories and the Pocock rule-or-judge mapping |
| 4b | main session | remaining rules follow the 4a pattern; crosswalk rungs follow A14 |
| 5 | main session | config contract |
| 6 | sub-agent worker | follows the Phase 2 pattern |
| 7 | sub-agent worker, after PR B merges | shares testing `plugin.json`, CHANGELOG and README with PR B; keyed to PR B rule ids |
| 8 | main session | outside-checkout approval |

PR slicing, each opened as a draft. Every version is one patch or minor above main at merge:

- PR A: Phase 1, a `testing` patch bump, merged as #5205 (squash `d6e040a4c`).
- PR B: Phases 2-6, a `testing` minor bump and a `review` patch bump for the Phase 4b crosswalk
  rows, committed per phase. Its branch `feat/testing-test-scan-hook` is already rebased onto
  `origin/main` (`32163c726`), without the three pre-squash Phase 1 commits (`cb8969646`,
  `3476b39f4`, `6c913d831`).
- PR C: Phase 7, opened after PR B merges, bumps for `testing`, `implementation`, `review` and
  `debugging`.
- PR D: Phase 8, a `testing` patch bump.

## Approval

Approved by Kyle Sexton on 2026-09-28, attended. Each listed change was answered separately: X1,
reword acceptance criterion 10; X2, lint presence moves to `/testing:setup check`; X3, the wave-1
amendment is confirmed; X4, the fleet-host and other-repo steps are approved, with each run gated
again when it happens.

Amendment: attended. Approved by Kyle Sexton on 2026-09-28, from
`.work/tautological-tests/pocock-critique/RESEARCH.md` and
`.work/tautological-tests/test-guidance-map/EXPLORE.md`. Each item was decided separately:

- A1, rule categories: blocking, change-detector, advisory (Brief Q4, Phase 4a).
- A2, `rule-conditional-assertion` and `rule-weak-oracle`; G7 and G10 go to the judge; G11 is out.
- A3, the `rule-source-text-read` tracked-source path gate.
- A4, `rule-snapshot-only` stays advisory, with its finding wording.
- A5, the derived-expectation rule starts advisory, with the property-test exemption.
- A6, the Phase 7 test-value content and the fate of the existing copies.
- A7, the `dependencies.md:15` contradiction is recorded, not filed.
- A8, Pocock fixture handling and the acceptance criterion 1 judge-case wording.
- A9, no retro pointer: adoption ledger row 17 is dropped.
- A10, the judge proposes test fixes and never commits them.
- A11, `audit-enforceability` crosswalk rows in Phase 4b.
- A12, the extreme-mutation mode is a candidate follow-up, not filed.
- A13, conflict reconciliation: Q12 activation, own id for the derived variant, testing bump in
  PR C, precision exemptions, setup lint finding.
- A14, the crosswalk tier and enforcement rung per rule (Phase 4a table): IMPORTANT for the
  can't-fail rules, SUGGESTION for the change-detector rules, `rule-snapshot-only` and
  `rule-weak-oracle`; `analyzer-pack-rule` for `rule-inert-assertion`; argued rungs for the two
  Playwright rows.

Re-approved by Kyle Sexton on 2026-09-29 after a fresh plan review (16 findings fixed). The formal
devils-advocate pass was skipped: the base plan was stress-tested twice and no new rule blocks in
Release 1.

User-approval gates that still hold:

- Phase 2 and Phase 8: running on a Windows fleet machine through `/fleet:reach`.
- Phase 8: scanning `medley` and `ci-runner`, read-only.
- Phase 4a: any Pocock example that fits neither a rule nor the acceptance criterion 1 judge list.
- Phase 5 `[FALLBACK]`: taken; the probe showed a settings hook gets no plugin variables.
