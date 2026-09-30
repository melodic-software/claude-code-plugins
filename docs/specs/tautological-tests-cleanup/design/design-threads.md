# Design threads: tautological-tests-cleanup (Release 3)

Contract: the Brief in `docs/specs/tautological-tests.md` (Q1-Q13, amendments A1-A14), whose
"Release 3 outline" (spec:879-890) names three items: `testing:cleanup`, opt-in split mode, and the
wave 2 adapters. Research (gitignored, main checkout): `.work/tautological-tests/cleanup/`,
`.work/tautological-tests/context-separation/`, `.work/tautological-tests/mutation/`. Release 2
design (read-only, unmerged): `docs/specs/tautological-tests-judge/` on branch
`docs/tautological-tests-judge-design`.

Status values: resolved, directional, deferred.

Every thread was answered in one unattended run. Each carries "Recommended answer taken unattended
(2026-09-30)" and stays open to the user's redirection at plan approval.

## Round 1

### DT1. Release 3 order: cleanup, then split mode, then wave 2 (resolved)

Decision: build `testing:cleanup` first, split mode second, and defer wave 2 (DT2). Cleanup is the
reactive half the user asked for ("being able to execute a skill that cleans up those types of
things") and applies to every suite already in the fleet. Split mode is prevention for new work,
which Release 1's hooks and the Release 2 judge already cover in part. The items share no files
except the testing `plugin.json`, CHANGELOG and README, so they ship as separate PRs.

Recommended answer taken unattended (2026-09-30). Basis: spec:105-108 (Q13 order: cleanup, split
mode and wave 2 form one release, with no order inside it); spec:96-97 (Q10); judgment for the
order inside the release.

Decided 2026-09-30 (user): Release 3 builds cleanup only. Split mode is deferred by A16 (DT13) and
wave 2 by A15 (DT2).

### DT2. Wave 2 adapters and SW1: defer all four, with switch conditions (deferred)

This thread proposes amendment A15 to Q5 and Q13. It is not a design decision, and the spec stays
unedited here (another PR owns it).

Evidence: the 17 local clones under `~/repos/github.com` (the fleet as `repos-sync` checks it out)
hold no `Cargo.toml`, no `pom.xml` and no `build.gradle*`, and no `go.mod` or `*_test.go` file that
imports `github.com/stretchr/testify` (0 of 69 `_test.go` files). The brief's inventory (about 65
Go files) matches the 69 found here, so the clones represent the fleet. Wave 2 would ship adapters
nobody runs.

| Item | Cost if built now | Switch condition |
|---|---|---|
| Go testify | one adapter over the existing `go` lexer; no plugin release is required for a consumer, because consumer adapters use the same schema (spec:195-196) | a fleet repo imports testify in a `_test.go` file, or a consumer asks. Until then `go-testing.yaml` already counts `require.X(t, ...)` and `assert.X(t, ...)` as assertions through its `(require\|Require)` and `[Aa]ssert` tokens, so a testify test is not reported as assertion-free |
| Rust | a new lexer and a plugin release (spec:189-191) | a fleet repo adds a `Cargo.toml` with tests |
| Java/Kotlin | a new lexer and a plugin release | a fleet repo adds `pom.xml` or `build.gradle*` with tests |
| ast-grep backend (SW1) | reserved field `astgrep_rules`, not implemented (spec:260-262) | the fixture corpus shows awk missing argument-structure cases. It has not fired: the nine `n/a` cells in `plugins/testing/skills/audit/evals/fixtures/corpus/GRID.md` are declaration lookups (C#, Go, Pester constants), an engine-exempt case (Playwright seed data) and bash block-tracking limits, none of them argument structure |

Recommended answer taken unattended (2026-09-30): defer all four, record A15 with these switch
conditions, and re-check the switches at each Release 3 PR. Research tag: the evidence that settles
it is a fleet repo adopting Rust, Java/Kotlin or testify (an org-wide `gh search code` plus a
`find`/`grep` over the `repos-sync` clones), a marketplace consumer outside the fleet filing an issue
for one of them, or the user choosing to build ahead of use. Basis: `find` and `grep` over the 17 clones
this session (0 hits); `go-testing.yaml` assertion `calls` (Explore report this session);
GRID.md `n/a` cells read this session; spec:63-71 (Q5 as amended).

Decided 2026-09-30 (user): A15 approved. Wave 2 and SW1 leave Release 3 until a switch condition
above fires; the next PR that edits the spec records A15 (PLAN Phase 1).

## Round 2: `testing:cleanup`

### DT3. Inputs (resolved)

Decision: one batch is one folder. Cleanup reads three inputs, all gathered before any edit:

1. `testing:audit` findings for the folder: the scanner's `--findings` output, the same
   `type: review-findings` table `--persist-findings` writes (rule id, `file:line`, proposed
   repair). Every can't-fail, change-detector and advisory rule counts as a candidate.
2. Release 2 judge findings, when present: a findings file on the current branch in the
   detector-findings shape (Release 2 PLAN Phase 3 step 4). A FLAG verdict makes its test a
   candidate. A PASS verdict does not clear a scanner finding. The judge's proposed diff is only a
   candidate rewrite (DT5).
3. Flaky tests: the folder's tests run three times on unmodified code before the baseline. A test
   that both passes and fails is flaky. The user may name more.

Recommended answer taken unattended (2026-09-30). Basis: `plugins/testing/skills/audit/SKILL.md`
"Persisting findings" and `cant-fail-scan.sh` `emit_findings_file()` (Explore report);
`docs/conventions/detector-findings/README.md` :44-53 (format-only contract); Release 2
PLAN.md:233-234; Fowler 2011, "Eradicating Non-Determinism in Tests"
(<https://martinfowler.com/articles/nonDeterminism.html>, via
`.work/tautological-tests/cleanup/RESEARCH-suite-types.md:71-100`) for flakiness defined as mixed
outcomes on the same code. Nothing in the repo detects flaky tests today, so without step 3 the
first step of Q9's order would never fire.

Decided 2026-09-30 (user): no three-run pre-pass. Cleanup quarantines only the tests the user names
as flaky. A red baseline in the recording run stops the batch, as Release 2b's one restricted
baseline already does, and cleanup reports the failing tests so the user can name the flaky ones or
fix them. No rerun. This replaces item 3 above.

### DT4. Per-test decision rule and who classifies (resolved)

Decision: a fresh-context classifier (a general-purpose subagent given a brief file, the pattern
`mutation-testing:audit` Phase 4 uses) assigns each candidate the first matching row. Inputs:
F = flaky (DT3); CF = cannot fail or checks little (a DT3 finding, or a FLAG verdict);
K = a contract exists, meaning callers, users or an external system depend on the behavior, cited by
file and line; B = brittle, meaning it asserts internals and would fail on a behavior-preserving
refactor; D = a behavior-level duplicate of a kept test, on the same inputs.

| # | Condition | Action (Q9 order) |
|---|---|---|
| 1 | F | quarantine with a 7-day bound (DT9) |
| 2 | CF and K | rewrite: same behavior, expected value from the contract (`testing:test-value` section 1) |
| 3 | B and K | rewrite to assert the observable outcome through the public API |
| 4 | CF or B, and a positive no-contract statement | delete; if real logic lives in a collaborator, cover it there in the same batch |
| 5 | D, confirmed by the classifier citing both tests | merge (parameterize) or delete the duplicate |
| 6 | none | keep |

The rewrite target is `testing:test-value` section 1, "Every expected value names its independent
source" (test-value SKILL.md:16), cited in the brief rather than restated (Q8). Mutation redundancy
alone never licenses a deletion or merge (DT7).

Row 4 needs a positive statement, not a missing citation: the subject is trivial (a constant, a
getter, pass-through glue) or unreachable from any public path, stated with the evidence. A
contract reached through reflection, dependency injection, an HTTP route or another repo does not
show up in a grep, so "no citation found" leads to rewrite or keep, never to delete. A finding from
an advisory rule, which is report-only because it can misfire (spec:909), reaches any row only after
the classifier quotes the defect in the test text.

Where evidence adds to Pocock: his `tests.md` lists implementation-detail tests as bad (M1) without
saying whether to delete or rewrite them. The rule rewrites them when a contract exists (row 3),
because Shi et al. 2018 measured real regression-detection loss of 9.5%-52.2% in reduced suites,
far above their mutant loss.

Recommended answer taken unattended (2026-09-30). Basis: spec:93-95 (Q9: rewrite by default; delete
only a test that protects no observable behavior; order quarantine, rewrite, delete, merge, keep);
`.work/tautological-tests/cleanup/RESEARCH-decision-rule.md` rule table and its verifier note that
the rule is synthesized judgment, not sourced; Shi et al., ISSTA 2018
(<https://mir.cs.illinois.edu/marinov/publications/ShiETAL18TSRinReal.pdf>, figures as corrected by
the cleanup slice's verifier); Khorikov, "Pragmatic unit testing" (2018 deck, cited in the same
sidecar) for the no-contract deletion case.

### DT5. Approval and commit rule (Q9, A10) (resolved)

Decision: cleanup never commits on its own. It stages one batch in the working tree:

- Rewrites and quarantines are applied and shown in the batch decision table.
- Each deletion and each merge is listed with its reason and applied only after the user approves
  that item.
- A judge-proposed diff is shown as a candidate. It is applied only when the classifier picks row 2
  or 3 for that test and the user approves the batch. A judge verdict is never committed as is.
- The user approves the batch, then cleanup commits. Pushing and opening the PR go through
  `/source-control:pull-request` with the user's approval.

Unattended runs stop at the staged batch and the report; they never commit.

Recommended answer taken unattended (2026-09-30). Basis: spec:93-95 (Q9: each deletion or merge
lists its reason and waits for approval); spec:974 (A10: the judge proposes test fixes and never
commits them); AGENTS.md "When to stop and when to keep going" (pushing and PR creation need the
user).

### DT6. Mutation gate: scope, replay and set comparison (resolved; needs Release 2b's scope)

Decision:

- Scope: mutate the production code the batch's tests exercise. Release 2b's DT3 static mapping
  (PR #5603) owns that question. The recording run passes 2b's `--exercised <test-path>` with the
  batch folder, and no `--paths`. That form maps the named tests as they stand, not the changed
  set, which is empty before any test is edited.
- No diff intersection. Today `--paths` is intersected with the changed lines (Phase 1 step 1), so a
  test-only batch would mutate nothing and pass vacuously. A recording run mutates every mutable
  line in the scope, one mutant each, with no diff. 2b's effort cap and `--max` apply unchanged;
  cleanup passes `--max` explicitly to cover the batch, and the report states it.
- Replay: the recording run writes its mutant list. The replay run applies exactly that list by
  per-mutant application (apply, run the covering tests, revert), the regime `tool: manual` already
  uses, whatever tool is configured. This avoids depending on a tool regenerating the same mutants:
  mutant ids vary by tool version and config, mutmut names mutants per function, and Stryker's
  incremental mode misses `.snap` and non-test file changes. Two independent runs would compare
  different mutants, and the subset check would mean nothing.
- Order: quarantines (DT9) are applied before the recording run. The flaky tests are then skipped
  in both runs, so a chance kill by a flaky test never counts as a loss, and a flaky failure never
  makes the baseline red (the audit stops on a red baseline).
- Gate: production files are byte-identical between the two runs (`git diff --quiet <base> --
  <paths>`). Detected means killed or timeout. Every mutant detected before is detected after (K0 is
  a subset of K1). The compare step refuses (exit 2) when K0 is empty, since an empty K0 proves
  nothing. A newly surviving mutant blocks the batch unless `mutation-testing:audit` Phase 4 triage
  calls it equivalent or arid with evidence. On a block, cleanup lists the candidate changes (the
  batch's changed tests that import the mutant's file) and the user reverts.
- Gate-blind tests: a changed or deleted test with no K0 mutant in a production file it imports is
  marked "gate-blind" in the decision table and needs the user's per-item approval, even for a
  rewrite.
- The gate is necessary, not sufficient: every deletion still carries its row-4 or row-5 reason
  and the user's approval (DT5).

This changes `mutation-testing:audit`: two flags, `--record-mutants <file>` and
`--replay-mutants <file>`, plus the no-diff recording scope. The spec's design contracts already
name small changes in `mutation-testing` (spec:170-171). The record format and its comparator
(`scripts/compare-records.sh`, the replay's compare step) live in `mutation-testing` and are private
to it; `testing` reads only the replay report's gate line and newly surviving list.

Recommended answer taken unattended (2026-09-30). Basis: `plugins/mutation-testing/skills/audit/SKILL.md`
:37-43 (`--paths`, `--max`), :156-163 (one mutant per line; agent-applied under `tool: manual`),
:50-60 (effort-derived caps); `.work/tautological-tests/cleanup/RESEARCH-safety.md` "The
invariant" (compare killed sets on one production commit, not scores) and "Scope of the mutation
run" (a test-only change makes a diff-scoped run mutate nothing).

Decided 2026-09-30 (user):

- The comparator moves into `mutation-testing` as the replay's own compare step, so the record
  format is private to that plugin. Dropped: the USER-RESERVED gate on the format, the v1 header,
  the version-skew check, and the `col` column (one mutant per line needs no column). The
  known-answer tests stay. Records live for one batch in `.work/`.
- Bisection is deferred. On a lost kill, the batch is blocked and the candidate changes (the tests
  that import the file) are listed; the user reverts. Switch condition: batches regularly show more
  than 2 candidates.
- The coverage before-and-after leg is deferred. Switch condition: a real batch shows a coverage
  drop the mutation gate missed.
- Release 2b's DT3 static mapping owns which production files the tests exercise. It replaces the
  `--paths` glob proposal and is passed to the recording run without `--paths`; cleanup depends on
  2b. `--exercised` excludes `--paths`, and the earlier `--record-mutants` required `--paths`, so
  the recording run takes 2b's `--exercised <test-path>` form instead.
- Probe R3-P1 runs once, with `tool: manual`.

### DT7. Per-test kill attribution (resolved: not built)

Decision: do not build per-test kill lists. The rule decides deletion and merge on behavior-level
evidence (K and D), and Shi 2018 shows that mutant redundancy alone does not license deletion. The
batch gate needs only the set comparison (DT6), which `mutation-testing:audit` supports once replay
exists. When a kill is lost, DT6 lists the candidate changes and the user reverts. Switch: a user
asks for unique-kill counts in the batch report, and the configured tool exposes per-test kills
(StrykerJS `disableBail` with `perTest`, PIT `fullMutationMatrix`).

Recommended answer taken unattended (2026-09-30). Basis: the Explore report found no per-test
attribution in `mutation-testing:audit` (grep for `killedBy`, `killer`, `per-test`: no hits);
RESEARCH-safety.md "Attribution needed for the per-test rule"; RESEARCH-decision-rule.md claim 3.

Decided 2026-09-30 (user): bounded bisection is deferred (DT6). Switch condition: batches regularly
show more than 2 candidates.

### DT8. Adapter and suite-type limits (resolved)

Decision:

- `block_model: file` adapters (`bash-harness`, about 800 fleet files) are rewrite-only. The
  scanner sees the whole file as one test, so a delete or merge would remove a whole file of checks
  on a whole-file verdict. Cleanup rewrites individual checks and never deletes or merges them.
- Integration and e2e tests (Playwright): rows 2-4 apply. Row 5 merges only against another test at
  the same level, never against unit tests.
- Snapshot-only findings go to row 2: convert to an explicit assertion where the expected value can
  be derived from requirements, otherwise shrink the snapshot. Obsolete snapshot entries are removed
  with the runner's own update command, and only where the runner documents it.

Recommended answer taken unattended (2026-09-30). Basis: spec:208-210 (`file` block model: "the
whole file is one test"); spec:264-265 (wave-1 adapter list); brief fleet inventory (hand-rolled
Bash about 800 files); RESEARCH-suite-types.md "Integration and e2e" (Google SWE book ch. 14) and
"Snapshot suites".

### DT9. Quarantine mechanics (resolved)

Decision: quarantine uses the framework's own skip form (from the adapter's `test_skip` or
`body_skip` vocabulary), with a reason reading
`test-change: quarantined <YYYY-MM-DD>: flaky, <evidence>`, where the date is 7 days out. The
`test-change:` prefix is what `test-weaken` counts (DT10). Quarantines are applied before the
mutation baseline (DT6). No new config key.

Recommended answer taken unattended (2026-09-30). Basis: Fowler 2011 (limit quarantine "no longer
than a week", RESEARCH-suite-types.md:79); Google Testing Blog 2016
(<https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html>): quarantine can mask
a real race, so it is bounded; spec:212-213 (`test_skip` and `body_skip` fields).

Decided 2026-09-30 (user): quarantine only the tests the user names as flaky; a red baseline stops
the batch and names the failing tests (DT3). The expired-quarantine sweep is deferred. Switch
condition: a quarantine outlives its date in practice.

### DT10. Interplay with `test-weaken` (resolved)

Decision: cleanup's deletions and quarantine skips are exactly what `test-weaken` names. While it
is advisory, it injects context and cleanup continues. When `rules: {test-weaken-block: error}` is
set, a deletion or added skip is denied unless the new text carries a `test-change: <reason>`
marker. Cleanup then adds one `test-change: cleanup <row> <reason>` comment at the edit. That
comment stays in the file, which is residue, accepted because the user chose block mode and the
comment is the reason that mode demands. For a quarantine, the skip reason starts with
`test-change:` (DT9). Cleanup never turns the hook off.

Recommended answer taken unattended (2026-09-30). Basis: `plugins/testing/hooks/test-weaken.sh`
:136-145 (deny only under `test-weaken-block: error`, bypassed by more `test-change:` markers)
(Explore report); spec:325 (D5).

### DT11. Batch, PR and report shape (resolved)

Decision: one folder per batch and one draft PR per batch (Q10). The PR body carries the decision
table (test, row, evidence, K citation, action, approved-by) and the gate result (K0 and K1 sizes,
the newly surviving set with its triage). The same table is written as a findings file in the
detector-findings shape, so `review:fanout` sees it. Cleanup refuses to start on the default branch
or a dirty tree.

Recommended answer taken unattended (2026-09-30). Basis: spec:96-97 (Q10, one PR per module or
folder); RESEARCH-rollout-tools.md "Recommended shape" and "Reporting per batch" (judgment);
`docs/conventions/detector-findings/README.md` :55-92 (destination resolution).

### DT12. Mutation tool reach per language (resolved)

Decision: no degraded mode. Where no tool is configured (Bash, Pester and Go have none in
`mutation-testing`'s table), `mutation-testing:audit` uses `tool: manual`, the agent-applied
single-operator protocol. With replay (DT6) the same mutants run on both sides. If
`mutation-testing` is not set up for the repo, cleanup stops and points to
`/mutation-testing:setup` rather than skipping the gate.

Recommended answer taken unattended (2026-09-30). Basis:
`plugins/mutation-testing/skills/principles/reference/tooling.md`:20-25 (tool table: no Go, Bash or
PowerShell tool) and :34 (manual protocol); `mutation-testing:audit` SKILL.md:162.

## Round 3: split mode

Deferred out of Release 3 by A16 (DT13). DT13-DT16 are kept as the design to use if it ships; PLAN
"Deferred: split mode" holds the summary.

### DT13. Where split mode lives and its flow (deferred by A16)

Decision: split mode is a mode of `testing:write` (`/testing:write --split`), not a new skill. Its
opt-in key is `userConfig.split_mode_enabled` (boolean, default false), effective only with `test_guards_enabled` on (DT14, one launcher). The flow:

1. The orchestrator writes a spec brief: the behaviors, with expected values from requirements, and
   the public interface (signatures only).
2. It dispatches a new plugin agent, `testing:test-writer`, with tools `Read, Grep, Glob, Write,
   Edit` (no Bash) and a `testing:test-value` preload. The agent starts without the parent
   conversation.
3. Validity check (DT15).
4. The orchestrator writes the freeze manifest (DT14) and prints the frozen list.
5. The implementer (main session or any subagent) makes the tests pass without editing them. If it
   believes a frozen test is wrong, it stops and reports to the user.
6. The orchestrator removes the manifest when the tests pass or the user ends split mode.

Steps 1-6 repeat per vertical slice (one behavior, or a few), never all tests for the feature up
front. Pocock names bulk tests-first "horizontal slicing" (S5), and `testing:write` already works in
vertical slices.

Recommended answer taken unattended (2026-09-30). Basis: spec:52-53 (Q3: spec-only test-writer
subagent, validity check before freezing, implementer cannot edit them); spec:43 (Q1: extend
`testing`, new hooks opt-in through `userConfig`); `code.claude.com/docs/en/sub-agents.md` (fetched
this session) line 230 (`tools`, `skills` frontmatter) and the "Forks inherit the parent
conversation" correction in `.work/tautological-tests/context-separation/RESEARCH.md` (use a named
agent, not a fork); `.work/tautological-tests/phase4-pocock-examples.md` row S5 and
context-separation RESEARCH-repo-scope.md option 1 ("Keeps vertical slicing");
`plugins/testing/skills/write/SKILL.md` has no split, subagent or frozen-test
content today (Explore report).

Decided 2026-09-30 (user): split mode is deferred out of Release 3 by a new Brief amendment, A16.
Switch condition: probe R2-P1 passes, and the Release 2 judge's calibration shows that main-session
tests carry provenance defects the Release 1 hooks and the judge both miss. If it ships, the simpler
form comes first: a done-time `git diff --quiet <freeze-sha> -- <files>` check, which detects an
edit rather than preventing it. The test-writer agent, the validity check (DT15), the
`split_mode_enabled` key, the freeze hook (DT14), probe R3-P3 and the Q4 clarification move to PLAN
"Deferred: split mode".

### DT14. Freezing: how the implementer is kept off the tests (deferred with DT13)

Plugin subagents cannot carry `hooks` or `permissionMode` frontmatter, so the lock cannot live in an
agent file. Decision: a new plugin hook, `test-freeze.sh`, on PreToolUse `Write|Edit`. It uses the
same `if` rows `gen-hook-filters.sh` generates for test-scan (so non-test paths start no process),
gated on `split_mode_enabled` (launcher shape below). It denies every agent,
the test-writer included, a write to a path listed in the session's freeze list under the testing
data directory. The list exists only after the validity check (DT15), so the writer works freely
before the freeze. No agent is exempt, because an exemption for `testing:test-writer` would let the
implementing thread spawn the writer to edit a frozen test. A frozen test changes only after the
user ends the freeze for that slice. The reason tells the agent to report the disagreement to the
user. `implementation:implementer` needs no change, because plugin hooks run inside subagents.
The skill and the hook resolve the list through one plugin script (`freeze-list.sh`), which reuses
the hook's data-directory resolution, so both read the same file.

Q4 consistency: Q4 limits which detection signals may block. This deny is not a detection verdict.
It is a lock the user asked for by opting in and starting split mode, released when split mode ends.
The dated Q4 clarification goes with split mode if it ships (PLAN "Deferred: split mode").

Known gaps, recorded and not closed: Bash and script writes bypass the hook (the same gap
spec:910 records, covered by guardrails `block-hook-bypass`); a freeze left by a crashed session is
pruned after 7 days like the other `$DATA` state.

Recommended answer taken unattended (2026-09-30). Basis: sub-agents.md line 240 ("plugin subagents
don't support the `hooks`, `mcpServers`, or `permissionMode` frontmatter fields"); hooks.md
(fetched this session) lines 267 and 745-746 (plugin hooks run inside subagents; the input carries
`agent_id` and `agent_type`); spec:54-62 (Q4); spec:335-337 (launcher gate). The manifest is keyed
by `session_id`, which assumes subagent tool calls carry the parent's `session_id`: Release 2
probe R2-P1 (judge PLAN.md:57) tests exactly that, and split mode reuses its result. If R2-P1
fails, the manifest keys on a hash of the normalized repo toplevel instead (a raw path fails the
session-id character check); then a second session in the same checkout is frozen too, so the flow
removes the list on every exit path (done, refusal, error).

Further limits, from the devil's-advocate pass (2026-09-30):

- One launcher. A second PreToolUse row set would add a node launcher to every test-file write
  while both options are off, against the Brief's "at most one launcher process" criterion
  (spec:134-136). `test-freeze` runs from test-weaken's existing rows instead, behind the same
  `--require-true TEST_GUARDS_ENABLED` gate: a small PreToolUse dispatcher runs the freeze check
  when `CLAUDE_PLUGIN_OPTION_SPLIT_MODE_ENABLED` is `true`, then test-weaken. Split mode therefore
  needs both keys on. An any-of gate in `exec-bash.mjs` was rejected: that file is one canonical
  copy synced into 21 plugins (`scripts/sync-exec-bash.sh`), so the change would reach all of them.
- Refusals. `--split` refuses unless both `test_guards_enabled` and `split_mode_enabled` are on (a
  freeze nothing enforces is a false promise), and refuses to freeze a file the generated `if` rows
  do not match (a consumer-added pattern never reaches the hook, Q6).
- Lifetime. A session-keyed list does not survive `/clear` or a fork if either issues a new
  `session_id` (unconfirmed). The skill states that `/clear` ends split mode, and the deny message
  names the list file and the release command, `/testing:write --split --end`.

### DT15. Validity check before freezing (deferred with DT13)

Decision: a written test is frozen only when all three hold:

1. `cant-fail-scan.sh --file` reports no finding on it (every rule, not only the gating ones).
2. It runs and fails on the current code for the right reason: an assertion failure, or a missing
   symbol or not-implemented error for the interface under test. A syntax error, a failed import of
   the framework, or a fixture error is the wrong reason, and the test goes back to the writer.
3. The user sees the list and each failure line before the freeze.

There is no "passes on a reference" step, because TDD has no reference implementation.

Recommended answer taken unattended (2026-09-30). Basis:
`.work/tautological-tests/context-separation/RESEARCH.md` open decision 2 (ExecCritic and arXiv
2606.16062: unvalidated LLM-written tests are often wrong); spec:52-53 (Q3).

### DT16. Keeping the test-writer from reading the implementation (deferred with DT13)

Direction: the writer's isolation rests on a fresh context, a brief carrying only the spec and
signatures, no Bash, and DT15. Nothing stops it reading an existing implementation file with Read.
A deny would need a PreToolUse `Read` hook with no path filter, which starts a process on every
Read in every session and breaks the hook budget. Split mode is aimed at new behavior (red-first),
where the implementation does not exist yet. Research tag: measure whether split-mode tests carry
provenance defects at a higher rate than main-session tests, using the Release 2 judge's calibration
harness. If they do, add a Read deny scoped to the test-writer, for example through a
`SubagentStart`-written manifest with an `if` filter, and measure its budget.

Recommended answer taken unattended (2026-09-30). Basis: `docs/conventions/hook-budget` (cited at
spec:376); context-separation RESEARCH.md claim 1 as downgraded by its verifier (MEDIUM: the effect
of separate authorship is not settled).

## Round 4: cross-cutting

### DT17. Test-seam posture (resolved)

Decision: test at the seams that already exist, driven through their command lines:

- New `plugins/mutation-testing/scripts/compare-records.sh <before> <after>`, the replay's compare
  step: prints the newly surviving mutants and exits non-zero when any remain. This is the one
  deterministic new logic the gate needs; a `.test.sh` covers it with known-answer cases.
- The classifier and the replay are agent behavior, covered by skill evals (`evals/evals.json`,
  validated by `/skill-quality:check validate-evals`), not unit tests.

Recommended answer taken unattended (2026-09-30). Basis: spec:387-392 (Release 1 test boundaries
are the scripts' command lines); `testing:plan` classification table (seam altitude), applied by
judgment.

Decided 2026-09-30 (user): the comparator lives in `mutation-testing` (DT6), and the split-mode
seams (`test-freeze.sh`, `test-pretool.sh`, `freeze-list.sh`, the regenerated rows) move to PLAN
"Deferred: split mode" with DT13.

### DT18. Configuration, extension and observability (resolved)

Decision:

- Config: one new userConfig key, `split_mode_enabled`. Cleanup adds no key: it is invoked
  explicitly, and its inputs (folder, `--max`) are arguments. The quarantine bound is fixed at
  7 days (DT9).
- Extension: new languages reach cleanup through adapters (the scanner, spec:193-262) and through
  `mutation-testing`'s tool table or the manual protocol. Cleanup has no per-language code.
- Observability: the batch findings file and the PR body (DT11); `test-freeze` logs each deny to
  the plugin's hook log, as the other testing hooks log.

Recommended answer taken unattended (2026-09-30). Basis: `plugins/testing/.claude-plugin/plugin.json`
userConfig (`test_guards_enabled`, `stdin_read_timeout` today, Explore report); spec:43 (Q1).

Decided 2026-09-30 (user): no new `.claude/*` config file. Issue #5606 makes a docs convention file
with a CLAUDE.md pointer the default config location, and any cleanup config reads the testing
config wherever #5606 puts it. The `split_mode_enabled` key and the `test-freeze` deny log leave
Release 3 with DT13.

## Dependency order

DT1 orders the work. DT6 needs Release 2b's exercised scope (PR #5603) and two
`mutation-testing:audit` flags before the cleanup gate works. A15 (DT2) and A16 (DT13) are decided
and go into the spec with the next PR that edits it.
