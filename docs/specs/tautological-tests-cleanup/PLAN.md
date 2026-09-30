# PLAN: tautological-tests-cleanup (Release 3: cleanup, split mode, wave 2)

## Brief

The contract is the Brief in `docs/specs/tautological-tests.md` (Q1-Q13, amendments A1-A14). Release 3
scope, from that spec's "Release 3 outline":

| Outline item | Where in this plan |
|---|---|
| `testing:cleanup` reads audit findings, applies the per-test order (Q9), runs a mutation check before and after, one PR per module or folder (Q10) | Phases 2-3 |
| Opt-in split mode (Q3): spec-only test-writer subagent, validity check before freezing, an implementer that cannot edit the tests | Phase 4 |
| Wave 2 adapters (Rust, Java/Kotlin, Go testify); ast-grep only if SW1 fires | Deferred by proposed amendment A15 (design DT2), recorded in Phase 1; no build phase |

Design: `design/design-threads.md` beside this file (DT1-DT18). Goal: an existing suite full of
tautological and low-value tests can be cleaned up safely, rewriting by default and deleting only
what protects no behavior, each deletion approved; and new tests can be written by a separate agent
the implementer cannot edit. The bar is one Matt Pocock would approve, adapted where evidence
corrects him (DT4, DT13).

This plan changes the Brief in two places, both pending the user (Phase 1):

- A15: wave 2 and the SW1 backend move out of Release 3 until a switch condition fires (DT2).
- A dated Q4 clarification: the split-mode freeze deny is a user-requested lock, not a detection
  signal (DT14).

## Plan

Standards grounding: `AGENTS.md` (draft PRs, Conventional Commits titles, stop before pushing),
`.claude/rules/pr-body-contract.md`, `docs/conventions/topic-docs/README.md` with
`scripts/check-contract-slice-prune.sh` (no path left under `docs/topics/`),
`docs/conventions/detector-findings/README.md` (findings shape, destination, crosswalk),
`docs/conventions/hook-budget` and `docs/conventions/hook-precision` (cited at spec:376),
`docs/conventions/shell-test-helpers` (no cross-plugin imports), `.claude/rules/skill-bodies-state-current-rules.md`
(new skill body and agent), `scripts/check-hook-userconfig-argv.sh` (userConfig delivery).

Test strategy: TDD (Red, Green, Refactor) for every script. Test boundaries, all through their
command lines:

- New `plugins/testing/skills/cleanup/scripts/mutant-gate.sh <before.tsv> <after.tsv>` through
  `mutant-gate.test.sh`: known-answer cases (DT17).
- New `plugins/testing/hooks/test-freeze.sh` and `test-pretool.sh` through `test-freeze.test.sh`
  and `test-pretool.test.sh`: hook JSON in, decision out, the same pattern as `test-weaken.test.sh`.
- New `plugins/testing/scripts/freeze-list.sh`, covered inside `test-freeze.test.sh` (the writer
  and the hook must resolve the same file).
- `plugins/testing/scripts/gen-hook-filters.sh` through `gen-hook-filters.test.sh` (existing).
- `plugins/testing/skills/audit/scripts/cant-fail-scan.sh --file` (existing), used by the validity
  check, needs no new test.
- Agent behavior (the classifier, replay, the test-writer) is covered by skill evals, validated by
  `plugins/skill-quality/scripts/check-evals-quality.sh`, and by the manual probes named in each
  phase.

### Phase 1: User decisions and spec housekeeping [TODO]

Runs in the PR that next owns `docs/specs/tautological-tests.md` (this design PR does not edit it).

1. The user decides A15 (DT2): defer Rust, Java/Kotlin, Go testify and the SW1 backend, with the
   DT2 switch conditions. On yes, add under spec Q5 and Q13: "Amended <date> (user, A15): wave 2
   and the SW1 backend leave Release 3 until a switch condition in
   `docs/specs/tautological-tests-cleanup/design/design-threads.md` DT2 fires." On no, add a Phase 6
   for the three adapters (fixtures per GRID cell, adapter files, `gen-hook-filters.sh`
   regeneration) through `/planning:plan review`.
2. The user decides the Q4 clarification (DT14). On yes, add under Q4: "Clarified <date> (user,
   Release 3 DT14): the split-mode freeze deny is a lock the user starts and ends; it is not a
   detection signal and is outside Q4's list."
3. First commit of PR B, before any code: spec:890 sanity check becomes `test -f docs/specs/tautological-tests-cleanup/PLAN.md` (this
   plan graduates in its own PR, so the `docs/topics/` path no longer exists).

**Sanity Check:**

- `grep -c 'A15' docs/specs/tautological-tests.md` returns at least 1, or this PLAN carries a
  Phase 6 for the wave 2 adapters.
- `grep -c 'docs/topics/tautological-tests-cleanup' docs/specs/tautological-tests.md` returns 0.
- `test -f docs/specs/tautological-tests-cleanup/PLAN.md` passes.

### Phase 2: Mutation record, replay and the gate script (DT6, DT7, DT12) [TODO]

Pre-flight consumer check, first work item: `git grep -n 'mutation-testing:audit'` over `plugins/`
and `docs/`, listing every caller and every reader of its findings file. The two new flags are
additive, so the existing flag set and findings shape must stay unchanged for them.

- New `plugins/mutation-testing/skills/audit/context/mutant-record.md`, the one statement of the
  record format: header `# mutant-record v1 <production-commit-sha>`, then one TSV row per mutant:
  `path`, `line_start`, `line_end`, `col`, `operator`, `original`, `replacement`, `state` (killed,
  survived, no-coverage, timeout, invalid). Tab, newline and backslash in text fields are escaped as
  `\t`, `\n`, `\\`, so a multi-line statement removal fits one row.
- `plugins/mutation-testing/skills/audit/SKILL.md`:
  - `--record-mutants <file>` requires `--paths` and mutates every mutable line in those paths, one
    mutant each, with no diff intersection (today Phase 1 step 1 intersects `--paths` with the
    diff, which would mutate nothing for a test-only batch). The effort-derived cap does not apply;
    an explicit `--max` does and is stated in the report. It writes the record.
  - `--replay-mutants <file>` applies exactly the listed mutants by per-mutant application (apply,
    run the covering tests, revert: the `tool: manual` regime), whatever tool is configured, with no
    incremental cache. It refuses when HEAD's production files differ from the recorded sha on any
    listed path, or when a listed `original` no longer matches its lines. It re-selects covering
    tests, because the tests changed, and writes the after record.
  - Restoration and Phase 4 triage are unchanged; replay survivors go through the same triage.
- `plugins/testing/skills/cleanup/scripts/mutant-gate.sh`: reads the two records, keys each mutant
  by `path, line_start, line_end, col, operator, replacement`, prints
  `newly-surviving <path>:<line_start> <operator>` for each key detected before and not detected
  after, and exits 1 when any remain and 0 otherwise. It exits 2 on a malformed record, a missing or
  unknown header version, mismatched shas, or an empty K0 (nothing detected before proves nothing).
  Detected means `killed` or `timeout`. It never reads mutation-testing code, only the record files
  (no cross-plugin import); it points at `mutant-record.md` for the format.
- `mutant-gate.test.sh`, Red first: identical non-empty records exit 0; one lost kill exits 1 and
  names it; a gain exits 0; a key present only in the after record is ignored; an empty K0 exits 2;
  a sha mismatch, a malformed row and an unknown header version exit 2; `timeout` then `killed` and
  `killed` then `timeout` are not losses; `killed` then `invalid` and `killed` then `no-coverage`
  are; a multi-line original round-trips its escapes; two mutants on one line with different
  columns stay two keys.
- The pre-flight caller list is recorded in this PLAN, before the SKILL.md edit, as one line at
  column 0 that starts with the literal prefix `Consumers of mutation-testing:audit:`.
- `plugins/mutation-testing/skills/audit/evals/evals.json`: one case records and replays over a
  fixture with `tool: manual` and asserts the replay applies the same mutants.
- `plugins/mutation-testing` CHANGELOG entry and a minor version bump.

**Sanity Check:**

- `bash plugins/testing/skills/cleanup/scripts/mutant-gate.test.sh` exits 0.
- `grep -c -- '--record-mutants\|--replay-mutants' plugins/mutation-testing/skills/audit/SKILL.md`
  returns at least 2.
- `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/mutation-testing/skills/audit/evals/evals.json`
  exits 0.
- `grep -c '^Consumers of mutation-testing:audit:' docs/specs/tautological-tests-cleanup/PLAN.md` returns 1.
- Manual probe R3-P1 in a scratch repo under `.work/tautological-tests-cleanup/probe/`: record over
  one JS file with no production diff and confirm K0 is non-empty; delete one killing assertion;
  replay: the lost mutant is named by `mutant-gate.sh`, and the restore check passes. Run it once
  with `tool: manual` and once with StrykerJS configured (replay must still apply the recorded
  mutants itself). A row `| R3-P1 | ... | holds |` is added
  to `docs/specs/tautological-tests/probes.md` in a "Release 3 probes" section;
  `grep -c '^| R3-P1 |.*holds' docs/specs/tautological-tests/probes.md` returns 1.
- `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.

### Phase 3: `testing:cleanup` skill (DT3-DT5, DT8-DT11) [TODO]

New `plugins/testing/skills/cleanup/SKILL.md`, `/testing:cleanup <folder> [--paths <globs>]`,
model-invoked and user-invocable. Steps, each in the body:

Working files (the before and after records, the classifier brief and its answer, the decision
table) live in the consumer repo's memory tier, `.work/testing-cleanup/<folder-slug>/` (resolved per
the topic-docs convention), so a compacted or resumed session finds them on disk; every step reads
them from that path, never from conversation memory.

0. Refuse on the default branch, on a dirty tree, when `mutation-testing` has no config (points to
   `/mutation-testing:setup`, DT12), or when the installed `mutation-testing:audit` does not
   document `--record-mutants` (version skew, DT6).
1. Inputs (DT3): the scanner's `--findings` over the folder; the branch's judge findings file when
   present; three unmodified runs of the folder's tests for flakiness; expired quarantines in the
   folder (DT9).
2. Quarantine first (DT6, DT9): skip the flaky tests in the working tree with the
   `test-change: quarantined <date>` reason, so both mutation runs exclude them and the baseline is
   green.
3. Baseline: `mutation-testing:audit --paths <globs> --record-mutants <before>` on the current
   production commit. With no `--paths`, propose globs from the tests' imports and ask the user.
   Once Release 2b's scope lands, use it instead (DT6). Stop when K0 is empty.
4. Classify (DT4): dispatch a fresh-context general-purpose subagent, `model: opus` named in the
   body so it does not inherit a session model by accident, with a brief file (the candidates, the
   rule table, the pointer to `testing:test-value` section 1). It returns one row per candidate:
   test, row fired, evidence, K citation or the positive no-contract statement, proposed action and
   diff.
5. Apply (DT5, DT8, DT10): rewrites in the working tree; deletions and merges listed, each applied
   only on the user's yes; `block_model: file` adapters rewrite only; row 5 never crosses test
   levels; a `test-change:` marker where `test-weaken-block: error` is set. A changed test with no K0
   mutant in a production file it imports is marked gate-blind and needs a per-item yes.
6. Gate (DT6): `--replay-mutants <before>` writes `<after>`; `mutant-gate.sh`; for a newly surviving
   mutant that triage does not call equivalent or arid, revert the batch changes whose tests import
   its file one at a time, replaying only that mutant, until the kill returns; that change leaves the
   batch. Line coverage before and after is reported where the repo can produce a report.
7. Report (DT11): the decision table and gate result as a detector-findings file and a PR-body
   draft. The user approves the batch; cleanup commits. Push and PR go through
   `/source-control:pull-request`. Unattended runs stop before the commit.

Other files:

- `plugins/testing/skills/cleanup/evals/evals.json`, validated by `check-evals-quality.sh`: a
  CF-and-K test is rewritten, not deleted; a trivial-getter test is proposed for deletion with a
  positive no-contract statement and not applied without approval; a test whose contract is reached
  only through dependency injection is not proposed for deletion; a bash-harness file gets no
  deletion; a flaky test is quarantined with a `test-change:` dated reason and the gate still exits
  0; a judge FLAG diff is not applied unclassified; with `test-weaken-block: error`, the quarantine
  edit is not denied.
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
- Manual probe R3-P2, the end-to-end tracer, in the scratch repo: a folder with one tautological
  test that has a contract, one on a trivial getter, one flaky test and one good test. Cleanup
  stages a rewrite, proposes one deletion and waits, quarantines the flaky test with a date 7 days
  out, keeps the good test, and the gate exits 0. A deliberately bad rewrite that drops a kill is
  reverted by the gate. `grep -c '^| R3-P2 |.*holds' docs/specs/tautological-tests/probes.md`
  returns 1.
- `bash scripts/validate-plugins.sh` and `bash scripts/check-changelog-parity.sh --check-bump origin/main`
  exit 0.

### Phase 4: Split mode (DT13-DT16) [TODO]

- `plugins/testing/.claude-plugin/plugin.json`: `split_mode_enabled` (boolean, default false),
  defaulted false in-script too (userConfig `default` is not delivered, per the
  `scripts/check-hook-userconfig-argv.sh` header).
- New `plugins/testing/agents/test-writer.md`: `tools: Read, Grep, Glob, Write, Edit`,
  `skills: testing:test-value`, a body that writes tests only from the brief's behaviors and
  signatures and treats any implementation it happens to see as off-limits for expected values.
  Its `## Next` names `/testing:write`.
- New `plugins/testing/scripts/freeze-list.sh add|clear|path <session_id> [file...]`: the one
  reader and writer of `$DATA/freeze/<session_id>.list`, with `DATA` from `testing::data_dir`
  (`plugins/testing/hooks/scanner-run.sh:10-18`), so the skill and the hook resolve the same file.
  The skill passes `${CLAUDE_SESSION_ID}`. Paths are stored through the existing
  `hook::normalize_path_to` (`plugins/testing/hooks/hook-utils.sh:505`), the same normalization
  test-weaken's input goes through, so writer and reader agree on Windows forms.
- New `plugins/testing/hooks/test-freeze.sh`: exits 0 with no output when no list exists; denies a
  listed path for every agent, the test-writer included (DT14), with a reason naming the list file
  and `/testing:write --split --end`; logs each deny with `agent_type`; prunes lists older than
  7 days. Session id must match `^[A-Za-z0-9_-]+$`. An EXIT trap forces exit 0 on its own failure
  (the edit proceeds).
- One launcher (DT14): `plugins/testing/scripts/gen-hook-filters.sh` points test-weaken's existing
  PreToolUse rows (gate `--require-true TEST_GUARDS_ENABLED`) at a new
  `plugins/testing/hooks/test-pretool.sh` dispatcher, which runs `test-freeze.sh` when
  `CLAUDE_PLUGIN_OPTION_SPLIT_MODE_ENABLED` is `true` and then `test-weaken.sh`, passing one stdin
  copy to both. No new row set, and `exec-bash.mjs` is untouched. The `hooks.json` `description`
  names both keys. Regenerate `hooks.json`; never hand-edit it.
- `plugins/testing/skills/write/SKILL.md`: a `--split` section with the DT13 flow per vertical
  slice; refusal unless `test_guards_enabled` and `split_mode_enabled` are both on, and refusal to
  freeze a file the generated `if` rows do not match; the DT15 validity check
  (`cant-fail-scan.sh --file` clean; fails for the right reason; the user sees the list); writing
  and removing the freeze list on done, refusal and error; `--end`; the statement that `/clear` ends
  split mode; and what the implementer does on disagreement.
- Depends on Release 2 probe R2-P1 (subagent calls carry the parent `session_id`). If R2-P1 has
  not run or fails, key the list on a hash of the normalized repo toplevel instead (DT14).
- `test-pretool.test.sh`: split off runs test-weaken only; split on with a listed path denies
  without running test-weaken; split on with an unlisted path runs test-weaken's advisory output
  unchanged.
- `test-freeze.test.sh`, Red first: no list allows; a listed path
  denied for the main thread, for `implementation:implementer` and for `testing:test-writer`; an
  unlisted test file allowed; the same file written as `C:\repo\a.test.ts`, `C:/repo/a.test.ts` and <!-- path-example -->
  `/c/repo/a.test.ts` all match one listed entry; `../` and empty session ids write and read
  nothing; malformed JSON exits 0; a stale list is pruned; a strace spawn-budget case (the
  `docs/conventions/hook-budget` option 2): through `test-pretool.sh`, with `test_guards_enabled`
  on and no list, a test-file write spawns the same process count with `split_mode_enabled` on as
  with it off (test-weaken's own spawns are the shared baseline).
- README, CHANGELOG and a version bump for `testing`.

**Sanity Check:**

- `bash plugins/testing/hooks/test-freeze.test.sh`, `bash plugins/testing/hooks/test-pretool.test.sh` and `bash plugins/testing/scripts/gen-hook-filters.test.sh` exit 0.
- `jq -r '.userConfig.split_mode_enabled.default' plugins/testing/.claude-plugin/plugin.json` prints `false`.
- `bash plugins/testing/scripts/gen-hook-filters.sh --check`, `bash scripts/check-hooks-description.sh`
  and `bash scripts/check-hook-userconfig-argv.sh` exit 0.
- `bash plugins/skill-quality/scripts/check-skill.sh plugins/testing/skills/write` exits 0.
- Manual probe R3-P3 in the scratch repo with `split_mode_enabled` on: `/testing:write --split` for
  one behavior; the writer's test fails for the right reason and is frozen; an Edit to it from the
  main session, from an `implementation:implementer` spawn and from a `testing:test-writer` spawn
  is denied; the implementation turns it green; the list is gone at the end.
  `grep -c '^| R3-P3 |.*holds' docs/specs/tautological-tests/probes.md` returns 1.
- `grep -c strace plugins/testing/hooks/test-freeze.test.sh` returns at least 1, and
  `bash plugins/testing/scripts/gen-hook-filters.sh --check` exits 0 (non-test paths match no
  `if` row, so they spawn nothing: the Brief's "matches no test pattern spawns zero hook processes"
  criterion).

### Phase 5: Close out [TODO]

- Spec Release 3 outline: cleanup and split mode `[DONE]`; wave 2 marked deferred under A15, or
  `[DONE]` if the user chose to build it.
- All phase tags here `[DONE]`.

**Sanity Check:**

- `grep -c '\[TODO\]' docs/specs/tautological-tests-cleanup/PLAN.md` returns 0.
- `git grep -n 'docs/topics/tautological-tests-cleanup' -- ':!docs/specs/tautological-tests-cleanup'`
  returns nothing.

## Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Extend `review:fanout fix` to apply cleanup | It applies findings without the per-test rule, the mutation gate or per-deletion approval | fanout gains a gate hook that a producer can require |
| Per-test kill attribution (StrykerJS `perTest`, PIT matrix) | Mutant redundancy alone does not license deletion (Shi 2018); only the set gate is needed (DT7) | the user asks for unique-kill counts and the configured tool exposes them |
| Two independent mutation runs, compare scores | Different mutants on each side under `tool: manual` or a cap; a score hides a lost kill (DT6) | never while `tool: manual` or a cap samples |
| A new `testing:split` skill | `testing:write` already owns vertical-slice TDD; a mode reuses it (DT13) | the split flow outgrows one section of `write` |
| Freeze through agent frontmatter `hooks` or `permissionMode` | Plugin agents ignore both (sub-agents docs) | Claude Code supports them for plugin agents |
| Block the test-writer's Read of implementation files | Needs an unfiltered Read hook, which breaks the hook budget (DT16) | the judge's calibration shows split-mode tests carry more provenance defects |
| Build wave 2 now | No fleet repo uses Rust, Java/Kotlin or testify (DT2) | a DT2 switch fires |

## Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A module-wide mutation run is slow or costly | High | Med | `--max` caps the recording run; replay runs the same list only; one folder per batch |
| The gate passes while a deletion loses real regression detection | Med | High | The gate is necessary, not sufficient: every deletion needs a no-contract reason and the user's yes (DT4, DT5) |
| The classifier misreads "contract exists" | Med | Med | K must cite `file:line`; rewrite is the default; eval cases; the user reviews the batch |
| Freeze bypassed by Bash writes | Known | Med | guardrails `block-hook-bypass`; recorded gap (DT14) |
| Freeze routed through a test-writer spawn | Med | Med | no agent is exempt once the list exists (DT14); R3-P3 tries the route |
| A long cleanup run is compacted mid-batch | High | Med | records and the decision table on disk under `.work/testing-cleanup/<folder-slug>/`; steps read them by path |
| R2-P1 fails (subagents carry another session id) | Low | Med | fall back to repo-keyed lists (DT14) |
| `mutation-testing:audit` flags change a contract other callers read | Low | Med | Phase 2 pre-flight consumer check; flags are additive |

## Blast radius

Blast-radius: MEDIUM. One new skill, one new agent, one new opt-in hook check and one userConfig
key in `testing`, with test-weaken's existing PreToolUse rows re-pointed at a dispatcher (its
advisory output must stay byte-identical, `test-pretool.test.sh`); two additive flags and a no-diff
recording scope in `mutation-testing`; no change to another plugin's code. Everything
is opt-in or explicitly invoked and reversible by git revert. Stress-test triggers: a new hook, a
new cross-plugin data contract (the mutant record), and an automated path that deletes tests.

## Stress-test summary

- Plan reviewer (fresh context): 2 CRITICAL, 6 IMPORTANT, 7 SUGGESTION, all checked against the
  files and folded in. The two CRITICALs were Sanity Check commands that could not run as written:
  `check-skill.sh` takes a skills root, not a skill directory (check-skill.sh:13-15), and
  `check-evals-quality.sh` takes an `evals.json` path (:16-17). Both were fixed. The IMPORTANT findings
  fixed were:
  - the Phase 5 grep that matched its own text;
  - a real strace budget case replacing a missing test;
  - the test-writer exemption, which let the implementer route an edit through a writer spawn, so
    no agent is now exempt (DT14);
  - one shared freeze-list script, so the skill and the hook read the same data directory;
  - Windows path normalization through the existing `hook::normalize_path_to`;
  - working files on disk so a compacted session can resume.
- Devil's advocate (fresh context): 1 CRITICAL, 7 HIGH, 8 MEDIUM, 4 LOW. The CRITICAL was verified
  (`mutation-testing` SKILL.md Phase 1 step 1 intersects `--paths` with the diff, so a test-only
  batch mutated nothing and passed). It was fixed in two ways: recording runs now have a no-diff
  scope, and the gate refuses an empty K0. The HIGHs were folded into DT6 and Phases 2-3:
  - sampling blindness: the gate-blind marking, and no effort cap on recording runs;
  - no way to tell which change lost a kill: bounded bisection;
  - quarantine colliding with the gate, and a flaky baseline: quarantine is applied before
    recording;
  - replay through a tool: replay uses per-mutant application;
  - the dropped coverage leg: coverage is now reported where a report exists;
  - the freeze bypass: no exemption.

  MEDIUMs folded in:
  - the fallback key is hashed;
  - `/clear` and `--end` are documented;
  - refusals when an option is off or a path is unmatched;
  - one launcher through a dispatcher (an any-of gate in the 21-plugin `exec-bash.mjs` was rejected);
  - the `test-change:` quarantine prefix;
  - row 4 needs a positive no-contract statement;
  - record columns and escaping;
  - a version-skew check.

  LOWs folded in: timeout counts both ways; the Phase 5 grep and wave-2 phase numbering; an extra
  A15 switch (a consumer outside the fleet). LOW 20 needed no change after the exemption was removed.

## Execution shape

Phase 1 is independent of the rest and rides the next PR that owns the spec. Phase 2 gates Phase 3
(the gate needs record and replay). Phase 4 shares only `plugin.json`, CHANGELOG and README with
Phase 3 and could run beside it, but both bump the testing version; run it after Phase 3 to avoid a
version conflict. Main session throughout.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | user decisions |
| 2 | main session | new data contract and gate |
| 3 | main session | skill body and tracer probe |
| 4 | main session | hook and agent contract, live probe |
| 5 | main session | bookkeeping |

PR slicing, each opened as a draft, each version one minor above main at merge: PR A = this design
and plan (graduated, no plugin change); PR B = Phases 1-3 (`mutation-testing` and `testing` minors);
PR C = Phases 4-5 (`testing` minor).

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) | Source |
|---|---|---|---|
| [EXEC-SHAPE] Phase 4 runs after Phase 3, not beside it | PR C follows PR B | both bump `plugins/testing/.claude-plugin/plugin.json` version (Phase 3 and 4 file lists) | plan |
| [FALLBACK] Repo-keyed freeze list if R2-P1 fails | Phase 4 keying; a second session in the same checkout is then frozen too, so the flow clears the list on done, refusal and error | the Release 2 judge plan's probe R2-P1 (subagent `session_id`) has not run | plan |

## Open questions

- A15 (DT2): defer wave 2 and SW1. Recommended yes. Unblocks calling Release 3 done.
- Q4 clarification for the freeze deny (DT14). Recommended yes. Unblocks Phase 4's deny.
- The `mutant-record v1` TSV (Phase 2) is a new cross-plugin data contract, hard to change once
  records exist. Recommended: the six columns in Phase 2. USER-RESERVED: unblocks Phase 2.
- Split mode needs `test_guards_enabled` on as well as `split_mode_enabled`, because the freeze
  check shares test-weaken's launcher (DT14). The alternative, an any-of gate in `exec-bash.mjs`,
  reaches all 21 plugins that sync that file. Recommended: accept the dependency. Unblocks Phase 4.
- Every DT1-DT18 answer was taken unattended; each is the user's to redirect.

## Handoff to implementation

Approval: pending the user (unattended run, recommended answers taken).

### User-approval gates

- Phase 1: A15 and the Q4 clarification.
- Phase 3: every deletion and merge, and every batch commit, in every cleanup run.
- Every push, PR creation and PR ready flip.

### Mechanical work

Commit per phase with `git commit -F - --cleanup=verbatim`; run the touched suites plus
`scripts/affected-tests.sh`.
