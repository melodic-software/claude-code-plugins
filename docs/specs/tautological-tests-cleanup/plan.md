# PLAN: tautological-tests-cleanup (Release 3: cleanup)

Status (2026-10-01): PR #5604 was closed unmerged with `do-not-merge`. The plan of record is
issue #5742, which links this branch at commit `97a41ff`. #5719 deletes `docs/specs`, so the spec edits in
Phases 1 and 4 and "PR A" in Execution shape no longer have a target; they are left as written, not
redesigned. A PR that carries this plan again is titled
`docs(testing): plan Release 3 test cleanup skill`.

## Brief

The contract is the Brief in `docs/specs/tautological-tests.md` (Q1-Q13, amendments A1-A14). Release 3
scope, from that spec's "Release 3 outline":

| Outline item | Where in this plan |
|---|---|
| `testing:cleanup` reads audit findings, applies the per-test order (Q9), runs a mutation check before and after, one PR per module or folder (Q10) | Phases 2-3 |
| Opt-in split mode (Q3): spec-only test-writer subagent, validity check before freezing, an implementer that cannot edit the tests | Deferred by amendment A16 (design DT13); "Deferred: split mode" below; no build phase |
| Wave 2 adapters (Rust, Java/Kotlin, Go testify); ast-grep only if SW1 fires | Deferred by amendment A15 (design DT2); no build phase |

Design: `design/design-threads.md` beside this file (DT1-DT18). Goal: an existing suite full of
tautological and low-value tests can be cleaned up safely, rewriting by default and deleting only
what protects no behavior, each deletion approved. The bar is one Matt Pocock would approve, adapted
where evidence corrects him (DT4).

This plan changes the Brief in two places, both decided by the user on 2026-09-30 and written into
the spec by Phase 1:

- A15: wave 2 and the SW1 backend move out of Release 3 until a switch condition fires (DT2).
- A16: split mode (Q3) moves out of Release 3 until its switch condition fires (DT13).

## Plan

Standards grounding: `AGENTS.md` (draft PRs, Conventional Commits titles, stop before pushing),
`.claude/rules/pr-body-contract.md`, `docs/conventions/topic-docs/README.md` with
`scripts/check-contract-slice-prune.sh` (no path left under `docs/topics/`),
`docs/conventions/detector-findings/README.md` (findings shape, destination, crosswalk),
`docs/conventions/shell-test-helpers` (no cross-plugin imports), `.claude/rules/skill-bodies-state-current-rules.md`
(new skill body). Configuration: this plan adds no `.claude/*` config file. #5606 closed through
PR #5697: the testing team config is the `yaml config` block of the consumer's
`docs/conventions/testing.md`, with `.claude/testing.yaml` as the fallback (the docs block wins when
both exist), resolved by `plugins/testing/scripts/resolve-config.sh` per
`docs/conventions/config-cascade/README.md`. Any cleanup setting reads that cascade (DT18).

Dependency (pending, Release 2b): 2b owns the question "which production files do these tests
exercise" through its DT3 static mapping. It has not shipped: PR #5603 was closed unmerged on
2026-10-01 and the plan now lives in issue #5741 (open, plan pending approval); `--exercised` is
absent from `plugins/mutation-testing/skills/audit/SKILL.md:3` on main; the spec lists the 2b scope
as `[TODO]` (`docs/specs/tautological-tests.md:886-887`). As the user decided on 2026-09-30,
`--exercised` takes an optional test file or folder; given one, the mapping starts from the tests
under that path, not the changed set. The effort cap applies and `--max` overrides it. 2b
recognizes test files through `cant-fail-scan.sh --file` and refuses the scope when the testing
plugin is not installed; cleanup lives in `testing`, so that holds. The user narrowed 2b on
2026-10-01: `--exercised` is explicit-only (no auto-engage), and survivor causes are `input-gap`
and `no-assertion` only; copied or restated expectations belong to the shipped judge rule
`testing/judge/rule-restated-expectation` (`plugins/testing/hooks/judge-lib.sh:39`). Release 3
always passes `--exercised <folder>` explicitly and reads no survivor cause, so the narrowing
changes nothing here. Phase 2 cannot start before 2b ships.

Test strategy: TDD (Red, Green, Refactor) for every script. Test boundaries, all through their
command lines:

- New `plugins/mutation-testing/scripts/compare-records.sh <before> <after>` through
  `compare-records.test.sh`: known-answer cases (DT17). It is the replay's own compare step, beside
  the existing `suppression-lint.sh`.
- `plugins/testing/skills/audit/scripts/cant-fail-scan.sh --findings` (existing), read by cleanup,
  needs no new test.
- Agent behavior (record, replay, the classifier) is covered by skill evals, validated by
  `plugins/skill-quality/scripts/check-evals-quality.sh`, and by the manual probes named in each
  phase.

### Phase 1: Spec housekeeping [TODO]

Runs in the next PR that edits `docs/specs/tautological-tests.md` (this design PR does not edit it).
PR #5605 already rewrote the Release 2 gate; this plan's Release 3 pointer goes in the Release 3
outline's Sanity Check (heading spec:897, check spec:908), which still names
`docs/topics/tautological-tests-cleanup/PLAN.md`. Superseded if #5719 deletes the spec first.

1. A15 (DT2), decided 2026-09-30 by the user. Add under spec Q5 and Q13: "Amended 2026-09-30 (user,
   A15): wave 2 and the SW1 backend leave Release 3 until a switch condition in
   `docs/specs/tautological-tests-cleanup/design/design-threads.md` DT2 fires."
2. A16 (DT13), decided 2026-09-30 by the user. Add under spec Q3 and Q13: "Amended 2026-09-30 (user,
   A16): split mode leaves Release 3 until probe R2-P1 passes and the Release 2 judge's calibration
   shows that main-session tests carry provenance defects the Release 1 hooks and the judge both
   miss. The design is kept in `docs/specs/tautological-tests-cleanup/plan.md` 'Deferred: split
   mode'."
3. The Release 3 sanity check at spec:908 points at `docs/specs/tautological-tests-cleanup/plan.md`.

**Sanity Check:**

- `grep -c 'A15' docs/specs/tautological-tests.md` returns at least 1.
- `grep -c 'A16' docs/specs/tautological-tests.md` returns at least 1.
- `grep -c 'docs/specs/tautological-tests-cleanup/plan.md' docs/specs/tautological-tests.md` returns
  at least 1, and `grep -c 'docs/topics/tautological-tests-cleanup' docs/specs/tautological-tests.md`
  returns 0.

### Phase 2: Mutation record, replay and compare (DT6, DT7, DT12) [TODO]

Needs Release 2b's `--exercised <folder>` interface and DT3 mapping (#5741, pending). Pre-flight
consumer check, first work item: `git grep -n 'mutation-testing:audit'` over `plugins/` and `docs/`, listing every caller
and every reader of its findings file. The two new flags are additive, so the existing flag set and
findings shape must stay unchanged for them.

- New `plugins/mutation-testing/skills/audit/context/mutant-record.md`, the record format, private
  to `mutation-testing`: a first line holding the production commit sha, then one TSV row per
  mutant: `path`, `line_start`, `line_end`, `operator`, `original`, `replacement`, `state` (killed,
  survived, no-coverage, timeout, invalid). Tab, newline and backslash in text fields are escaped as
  `\t`, `\n`, `\\`, so a multi-line statement removal fits one row. No other plugin reads a record.
  A record lives for one batch in the caller's `.work/` directory.
- `plugins/mutation-testing/skills/audit/SKILL.md`:
  - `--record-mutants <file>` runs only under an explicit `--exercised <folder>`, not `--paths`: 2b's
    DT3 mapping starts from the named tests as they stand, because a recording runs before any
    test is edited. It mutates every mutable line in the mapped functions, one mutant each, with no
    diff intersection. 2b's effort cap and `--max` apply unchanged; the caller passes `--max`
    explicitly to cover the batch, and the report states it. A red baseline stops the run, as 2b
    already does, and the report names the failing tests. It writes the record.
  - `--replay-mutants <file>` applies exactly the listed mutants by per-mutant application (apply,
    run the covering tests, revert: the `tool: manual` regime), whatever tool is configured, with no
    incremental cache. A red baseline stops the replay and names the failing tests, the same
    shape as recording. It refuses when HEAD's production files differ from the recorded sha on any
    listed path, or when a listed `original` no longer matches its lines. It re-selects covering
    tests, because the tests changed, and writes the after record. Its compare step runs
    `compare-records.sh`; replay survivors go through Phase 4 triage, and a newly surviving mutant
    triage calls equivalent or arid with evidence does not block. The report carries one
    `Gate: pass` or `Gate: block` line and one `newly-surviving <path>:<line_start> <operator>` line
    per blocking mutant.
  - Restoration is unchanged.
- `plugins/mutation-testing/scripts/compare-records.sh`: reads the two records, keys each mutant by
  `path, line_start, line_end, operator, replacement`, prints
  `newly-surviving <path>:<line_start> <operator>` for each key detected before and not detected
  after, and exits 1 when any remain and 0 otherwise. It exits 2 on a malformed record, mismatched
  shas, or an empty K0 (nothing detected before proves nothing). Detected means `killed` or
  `timeout`.
- `compare-records.test.sh`, Red first: identical non-empty records exit 0; one lost kill exits 1
  and names it; a gain exits 0; a key present only in the after record is ignored; an empty K0
  exits 2; a sha mismatch and a malformed row exit 2; `timeout` then `killed` and `killed` then
  `timeout` are not losses; `killed` then `invalid` and `killed` then `no-coverage` are; a
  multi-line original round-trips its escapes.
- The pre-flight caller list is recorded in this plan, before the SKILL.md edit, as one line at
  column 0 that starts with the literal prefix `Consumers of mutation-testing:audit:`.
- `plugins/mutation-testing/skills/audit/evals/evals.json`: one case records and replays over a
  fixture with `tool: manual`, asserts the replay applies the same mutants, and asserts a deleted
  killing assertion produces `Gate: block`.
- `plugins/mutation-testing` CHANGELOG entry and a minor version bump.

**Sanity Check:**

- `bash plugins/mutation-testing/scripts/compare-records.test.sh` exits 0.
- `grep -c -- '--record-mutants' plugins/mutation-testing/skills/audit/SKILL.md` and
  `grep -c -- '--replay-mutants' plugins/mutation-testing/skills/audit/SKILL.md` each return at
  least 1, and `grep -c 'compare-records.sh' plugins/mutation-testing/skills/audit/SKILL.md`
  returns at least 1.
- `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/mutation-testing/skills/audit/evals/evals.json`
  exits 0.
- `grep -c '^Consumers of mutation-testing:audit:' docs/specs/tautological-tests-cleanup/plan.md` returns 1.
- Manual probe R3-P1, run once with `tool: manual`, in a scratch repo under
  `.work/tautological-tests-cleanup/probe/`: record over one test folder with no production diff
  and confirm K0 is non-empty; delete one killing assertion; replay: the report shows `Gate: block`
  and names the lost mutant, and the restore check passes. A row `| R3-P1 | ... | holds |` is added
  to `docs/specs/tautological-tests/probes.md` in a "Release 3 probes" section;
  `grep -c '^| R3-P1 |.*holds' docs/specs/tautological-tests/probes.md` returns 1.
- `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.

### Phase 3: `testing:cleanup` skill (DT3-DT5, DT8-DT11) [TODO]

New `plugins/testing/skills/cleanup/SKILL.md`, `/testing:cleanup <folder>`, model-invoked and
user-invocable. Steps, each in the body:

Working files (the before and after records, the classifier brief and its answer, the decision
table) live in the consumer repo's memory tier, `.work/testing-cleanup/<folder-slug>/` (resolved per
the topic-docs convention), for one batch, so a compacted or resumed session finds them on disk;
every step reads them from that path, never from conversation memory. Cleanup passes the record
paths to `mutation-testing:audit` and reads only its report, never a record.

0. Refuse on the default branch, on a dirty tree, or when `mutation-testing` has no config (points
   to `/mutation-testing:setup`, DT12).
1. Inputs (DT3): the scanner's `--findings` over the folder; the branch's judge findings file when
   present; the flaky tests the user names. The judge is off by default
   (`plugins/testing/.claude-plugin/plugin.json`: `test_judge_enabled` false; `sonnet` at `medium`,
   fallback `opus`), so the file is usually absent. Cleanup finds it with the same lookup as
   `judge::findings_dir` (`plugins/testing/hooks/judge-lib.sh:652-661`) and runs unchanged without
   it.
2. Quarantine first (DT6, DT9): skip the named flaky tests in the working tree with the
   `test-change: quarantined <date>` reason, so both mutation runs exclude them.
3. Baseline: `mutation-testing:audit --exercised <folder> --max <n> --record-mutants <before>` on
   the current production commit, with no `--paths` (the 2b scope, DT6), and `--max` set to cover
   the batch. A red baseline stops the batch: cleanup reports the failing tests so the user can
   name the flaky ones for step 2 or fix them. Stop when the report shows K0 empty.
4. Classify (DT4): dispatch a fresh-context general-purpose subagent, `model: opus` named in the
   body so it does not inherit a session model by accident (Release 2 found `sonnet` `medium`
   tied-best on the judge's provenance task, `docs/specs/tautological-tests-judge/plan.md:220-229`
   and calibration.md "Chosen default"; opus is kept first because a wrong deletion costs more than
   a wrong verdict: Recommended, awaiting user), with a brief file (the candidates, the
   rule table, the pointer to `testing:test-value` section 1). It returns one row per candidate:
   test, row fired, evidence, K citation or the positive no-contract statement, proposed action and
   diff.
5. Apply (DT5, DT8, DT10): rewrites in the working tree; deletions and merges listed, each applied
   only on the user's yes; `block_model: file` adapters rewrite only; row 5 never crosses test
   levels; a `test-change:` marker where `test-weaken-block: error` is set. A changed test with no K0
   mutant in a production file it imports is marked gate-blind and needs a per-item yes.
6. Gate (DT6): `--replay-mutants <before>` writes `<after>` and reports `Gate: pass` or
   `Gate: block`. A red replay baseline (a changed test failing on unmutated code) stops the batch
   and names the failing tests, as in step 3. On a block, the batch stops. For each newly surviving mutant, cleanup lists the
   candidate changes, the batch's changed tests that import its file. The user reverts the ones
   they choose, and cleanup replays again. Cleanup reverts nothing itself.
7. Report (DT11): the decision table and gate result as a detector-findings file and a PR-body
   draft. The user approves the batch; cleanup commits and removes the batch's records. Push and PR
   go through `/source-control:pull-request`. Unattended runs stop before the commit.

Other files:

- `plugins/testing/skills/cleanup/evals/evals.json`, validated by `check-evals-quality.sh`: a
  CF-and-K test is rewritten, not deleted; a trivial-getter test is proposed for deletion with a
  positive no-contract statement and not applied without approval; a test whose contract is reached
  only through dependency injection is not proposed for deletion; a bash-harness file gets no
  deletion; a test the user names as flaky is quarantined with a `test-change:` dated reason and
  the gate still passes; a red baseline stops the batch and names the failing tests without
  quarantining any; a lost kill blocks the batch, lists its candidate changes and reverts
  nothing; a judge FLAG diff is not applied unclassified; with `test-weaken-block: error`, the
  quarantine edit is not denied.
- One pointer line each in `plugins/testing/skills/audit/SKILL.md` "What this skill does NOT do"
  (cleanup edits; audit stays "repair, not pruning") and `plugins/testing/skills/test-value/SKILL.md`
  `## Next`.
- `plugins/testing` README, CHANGELOG and a minor version bump.

**Sanity Check:**

- `test -f plugins/testing/skills/cleanup/SKILL.md` passes and
  `bash plugins/skill-quality/scripts/check-skill.sh plugins/testing/skills` exits 0.
- `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/testing/skills/cleanup/evals/evals.json` exits 0.
- `grep -c 'testing:cleanup' plugins/testing/skills/audit/SKILL.md` and
  `grep -c 'testing:cleanup' plugins/testing/skills/test-value/SKILL.md` each return at least 1.
- `grep -c -- '--exercised' plugins/testing/skills/cleanup/SKILL.md` returns at least 1.
- Manual probe R3-P2, the end-to-end tracer, in the scratch repo: a folder with one tautological
  test that has a contract, one on a trivial getter, one test the user names as flaky and one good
  test. Cleanup stages a rewrite, proposes one deletion and waits, quarantines the flaky test with a
  date 7 days out, keeps the good test, and the gate passes. A deliberately bad rewrite that drops a
  kill blocks the batch and is listed as a candidate change.
  `grep -c '^| R3-P2 |.*holds' docs/specs/tautological-tests/probes.md` returns 1.
- `bash scripts/validate-plugins.sh` and `bash scripts/check-changelog-parity.sh --check-bump origin/main`
  exit 0.

### Phase 4: Close out [TODO]

- Spec Release 3 outline: cleanup `[DONE]`; wave 2 marked deferred under A15 and split mode marked
  deferred under A16.
- All phase tags here `[DONE]`.

**Sanity Check:**

- `grep -c '\[TODO\]' docs/specs/tautological-tests-cleanup/plan.md` returns 0.
- `git grep -n 'docs/topics/tautological-tests-cleanup' -- ':!docs/specs/tautological-tests-cleanup'`
  returns nothing.

## Deferred: split mode

Deferred by A16 (DT13, decided 2026-09-30 by the user). The design is DT13-DT16 in
`design/design-threads.md`; if it ships, the done-time `git diff --quiet <freeze-sha> -- <frozen
files>` check comes before any hook. The hook-form detail (freeze list script, dispatcher, test
cases, probe R3-P3) is at commit `97a41ff` of this file.

Switch condition: probe R2-P1 holds (it does, `docs/specs/tautological-tests/probes.md`), and
main-session tests carry provenance defects the Release 1 hooks and the judge both miss. That half
is unmeasured. Calibration found 0 provenance-shaped scanner findings in 60 drawn blocks and in the
586-block pool, and says that count is not a prevalence estimate
(`docs/specs/tautological-tests-judge/calibration.md:69-73`). Runnable form: over
`plugins/testing/skills/audit/evals/judge-calibration/labels.tsv`, count in-use rows (`source` ends
in `@<40-hex sha>` and is neither `authored` nor a `.fixture`) with `reference_label` FLAG and
`judge_verdict` not FLAG. Today: 60 in-use rows, 0 labeled FLAG, 0 missed. The set does not record
whether the main session or a subagent wrote a test, so it cannot isolate "main-session". Proposed
threshold (judgment, awaiting user): at least 1 such joint miss in a fresh in-use sample of 60 or
more blocks whose writer is recorded.

## Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Extend `review:fanout fix` to apply cleanup | It applies findings without the per-test rule, the mutation gate or per-deletion approval | fanout gains a gate hook that a producer can require |
| Per-test kill attribution (StrykerJS `perTest`, PIT matrix) | Mutant redundancy alone does not license deletion (Shi 2018); only the set gate is needed (DT7) | the user asks for unique-kill counts and the configured tool exposes them |
| Two independent mutation runs, compare scores | Different mutants on each side under `tool: manual` or a cap; a score hides a lost kill (DT6) | never while `tool: manual` or a cap samples |
| Bisect a lost kill by reverting changes one at a time (DT6, DT7) | Deferred by the user (2026-09-30); the user reverts from the candidate list | batches regularly show more than 2 candidates |
| Sweep expired quarantines on each run (DT9) | Deferred by the user (2026-09-30) | a quarantine outlives its date in practice |
| Report line coverage before and after (DT6) | Deferred by the user (2026-09-30) | a real batch shows a coverage drop the mutation gate missed |
| Build split mode in Release 3 (DT13) | Deferred by the user (2026-09-30) through A16 | the measurement in "Deferred: split mode" shows joint misses (unmeasured today) |
| Build wave 2 now | No fleet repo uses Rust, Java/Kotlin or testify (DT2) | a DT2 switch fires |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Release 2b's `--exercised <folder>` does not ship | High (#5603 closed unmerged; #5741 has no PR and an unapproved plan) | High | Consequence: Release 3 PR B (Phases 2-4) waits until 2b ships; no fallback scope is built |
| A module-wide mutation run is slow or costly | High | Med | `--max` caps the recording run; replay runs the same list only; one folder per batch |
| The gate passes while a deletion loses real regression detection | Med | High | The gate is necessary, not sufficient: every deletion needs a no-contract reason and the user's yes (DT4, DT5) |
| The classifier misreads "contract exists" | Med | Med | K must cite `file:line`; rewrite is the default; eval cases; the user reviews the batch |
| An unnamed flaky test passes the one baseline and kills or loses a mutant by chance | Med | Low | a red baseline stops the batch and names the failing tests; a lost chance kill shows up as a candidate the user reviews, and the user can name the test as flaky |
| A long cleanup run is compacted mid-batch | High | Med | records and the decision table on disk under `.work/testing-cleanup/<folder-slug>/`; steps read them by path |
| `mutation-testing:audit` flags change a contract other callers read | Low | Med | Phase 2 pre-flight consumer check; flags are additive |

## Blast radius

Blast-radius: MEDIUM. One new skill in `testing`; two additive flags and a compare script in
`mutation-testing`, with the record format private to that plugin; no hook and no userConfig key.
Everything is explicitly invoked and reversible by git revert. Stress-test triggers: an automated
path that deletes tests, and a dependency on Release 2b's unmerged scope.

## Stress-test summary

- Plan reviewer (fresh context): 2 CRITICAL, 6 IMPORTANT, 7 SUGGESTION, all checked against the
  files and folded in. The two CRITICALs were Sanity Check commands that could not run as written:
  `check-skill.sh` takes a skills root, not a skill directory (check-skill.sh:13-15), and
  `check-evals-quality.sh` takes an `evals.json` path (:16-17). Both were fixed. The IMPORTANT finding
  still in the plan: working files on disk so a compacted session can resume.
- Devil's advocate (fresh context): 1 CRITICAL, 7 HIGH, 8 MEDIUM, 4 LOW. The CRITICAL was verified
  (`mutation-testing` SKILL.md Phase 1 step 1 intersects `--paths` with the diff, so a test-only
  batch mutated nothing and passed). It was fixed in two ways: recording runs now have a no-diff
  scope, and the gate refuses an empty K0. Folds still in the plan: the gate-blind marking;
  quarantine before recording; replay by per-mutant application; the `test-change:` quarantine
  prefix; row 4's positive no-contract statement; record columns and escaping; timeout counted as
  detected both ways; an extra A15 switch (a consumer outside the fleet).
- Overengineering review (2026-09-30): the user cut the plan to the cleanup core, removing the
  other folds: bisection, the coverage leg, the flaky pre-pass, the expired-quarantine sweep, the
  version-skew check and record header, and all split-mode items (A16). Each is recorded as
  "Decided 2026-09-30 (user)" in its design thread.

## Execution shape

Phase 1 is independent of the rest and rides the next PR that edits the spec. Phase 2 waits on
Release 2b and gates Phase 3 (the gate needs record and replay). Main session throughout.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | spec text |
| 2 | main session | new flags and compare script |
| 3 | main session | skill body and tracer probe |
| 4 | main session | bookkeeping |

PR slicing, each opened as a draft, each version one minor above main at merge: PR A = this design
and plan (no plugin change; closed as #5604, see Status); PR B = Phases 2-4 (`mutation-testing` and
`testing` minors), after 2b ships (#5741). Phase 1 rides whichever PR next edits the spec.

## Decisions made (gate-passed)

None: every item traces to the Brief, a design thread, or the user's 2026-09-30 decisions. The two
earlier rows belonged to split mode, now deferred.

## Open questions

- Every DT1-DT18 answer not covered by a "Decided (user)" line was taken unattended; each is the
  user's to redirect.
- The classifier's model (Phase 3 step 4): opus, Recommended, awaiting user.
- The split-mode switch threshold ("Deferred: split mode"): judgment, awaiting user.

## Handoff to implementation

Approval: pending the user (unattended run, recommended answers taken).

### User-approval gates

- Phase 3: every deletion and merge, every revert after a blocked gate, and every batch commit, in
  every cleanup run.
- Every push, PR creation and PR ready flip.

### Mechanical work

Commit per phase with `git commit -F - --cleanup=verbatim`; run the touched suites plus
`scripts/affected-tests.sh`.
