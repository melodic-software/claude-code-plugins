---
description: "Clean up low-value tests in one folder: reads /testing:audit findings, test-judge FLAG verdicts and the tests the user names as flaky, has a fresh-context classifier pick quarantine, rewrite, delete, merge or keep per test, rewrites by default, and deletes or merges only with a stated no-contract reason and the user's yes on each item. A mutation gate records the mutants the tests kill before any edit and replays them after, blocking the batch when a kill is lost. Nothing is committed until the user approves the batch. Use when: the user wants an existing suite of tautological, vacuous or low-value tests cleaned up ('clean up these tests', 'prune the useless tests in this folder', 'fix the tests audit flagged'), or audit findings need acting on rather than reporting. Needs the mutation-testing plugin set up."
argument-hint: "<folder> [--max <n>] [--flaky <test> ...]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Rewrite, quarantine or delete low-value tests in one folder behind a mutation gate
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call:

- Current branch, `git branch --show-current`
- Default branch, `git symbolic-ref --short refs/remotes/origin/HEAD` (unset: ask, unless the
  user named it)
- Working tree status (empty = clean), `git status --porcelain | head -20`

## Arguments

`$ARGUMENTS`: `<folder>` (required, one folder per batch), `--max <n>` (the recording run's mutant
cap, default 100), `--flaky <test>` (repeatable; tests the user names as flaky, also accepted from
the conversation). No folder: ask for one.

## Working files

Every step reads and writes `<work>` = `.work/testing-cleanup/<folder-slug>/` in the repository
root, `<folder-slug>` being the folder path lowercased with every character outside `[a-z0-9._-]`
replaced by `-`. It holds `before.tsv` and `after.tsv` (the mutant records), `classifier-brief.md`,
`classifier-answer.md`, `decisions.md` (the decision table, each item's approval state, the step
reached, and for every file the batch edits its `git hash-object` after the last edit) and
`pr-body.md`. Right after each edit to a test file (the quarantine in step 2, each rewrite,
deletion or merge in step 5, each revert the user makes in step 6), run `git hash-object "<path>"`
and record the hash and the step reached in `decisions.md`; step 0's resume check reads them.

Read the working files from that path at every step, never from conversation memory, so a
compacted or resumed session continues where the files say it stopped. Before the first write,
confirm `.work/` is ignored (`git check-ignore -q .work/x`); when it is not, create `.work/.gitignore`
holding `*`, and say so.

## Steps

### 0. Refuse

Stop, naming the remedy, when any of these holds; check them all before step 1:

- The current branch is the default branch, or the working tree is dirty. Cleanup stages a batch
  that must be reviewable as one diff. A resumed batch is the exception: when `<work>/decisions.md`
  exists and every changed path's `git hash-object "<path>"` equals the hash it recorded for that
  path after its last edit, continue at the step it records. A path with a different hash carries
  an edit the batch did not make: refuse.
- The `mutation-testing` plugin is not installed. Cleanup has no gate without it, and no degraded
  mode: report that the gate needs that plugin and stop.
- `mutation-testing` has no config for the repository, or its `test-command` is missing or lacks a
  standalone, unquoted `{tests}` word: both mutation runs use it. Point to
  `/mutation-testing:setup apply`.
- The folder does not exist, or `/testing:audit --file <path>` claims no file under it.
- The folder holds test files of more than one language (the adapters' `language`), such as a
  `*.test.sh` harness beside Python tests. The one `test-command` cannot run them all, so the
  baseline would be red. Name a subfolder per language and ask for one.

### 1. Inputs

Gather all three before any edit, and write the candidate list to `decisions.md`:

1. The scanner's findings over the folder:
   `env CANT_FAIL_SCAN_ROOT="<absolute folder>" bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/cant-fail-scan.sh" --findings`.
   Quote every path you put in a command, each as its own argument.
   Every row is a candidate, report-only rules included. `Location` is repo-relative.
2. Test-judge findings, when present. The judge is off by default, so usually there are none. Read
   every `.work/reviews/*/*.md` whose frontmatter has `type: review-findings` and a `branch:` equal
   to the current branch exactly (the frontmatter, not the directory, proves the branch), and keep
   the `testing/judge/rule-restated-expectation` rows whose `Location` is under the folder. A FLAG
   makes its test a candidate; a PASS clears no scanner finding.
3. The tests the user names as flaky. Cleanup detects no flakiness itself.

No candidate: report `nothing to clean in <folder>` and stop.

### 2. Quarantine

Skip each named flaky test with the framework's own skip form, the `test_skip` or `body_skip`
vocabulary of the adapter that claims its file (`${CLAUDE_PLUGIN_ROOT}/skills/audit/adapters/`),
with the reason `test-change: quarantined <YYYY-MM-DD>: flaky, <evidence>`, the date 7 days out.
The `test-change:` prefix is the marker the `test-weaken` hook accepts, so the edit is not denied
under `test-weaken-block: error`. Quarantine comes first so both mutation runs skip these tests.

### 3. Record the baseline

Invoke `/mutation-testing:audit --exercised <folder> --max <n> --record-mutants <work>/before.tsv`
through the Skill tool, with no `--paths`. Then read its report:

- A red baseline stops the batch. List the failing tests so the user can name the flaky ones for
  step 2 or fix them. Quarantine nothing on your own.
- `K0 empty`, or `no mapping: scope empty`: stop. Nothing the tests kill can be gated.
- Mutants dropped by the cap: state how many, and continue only on the user's yes or with a larger
  `--max`.

### 4. Classify

Write `<work>/classifier-brief.md` from [`context/classifier-brief.md`](context/classifier-brief.md),
with `<plugin-root>` rendered as `${CLAUDE_PLUGIN_ROOT}`, and dispatch a fresh-context `general-purpose` subagent with `model: opus`, so it does not inherit
the session's model. Opus is chosen over the judge's `sonnet` because a wrong deletion costs more
than a wrong verdict. Write its table to `<work>/classifier-answer.md` and apply that file's
reading rules.

This skill relies on the per-call `model` it passes taking effect; how that ranks against the
agent's frontmatter and operator overrides is set by
<https://code.claude.com/docs/en/sub-agents#choose-a-model>. As of 2026-10-02. Recheck when that
section changes the order.

### 5. Apply

Fill `decisions.md` with one row per candidate: test, row, evidence, K citation or no-contract
statement, action, gate-blind, approved-by.

- Rows 2 and 3: apply the rewrite in the working tree. A judge-proposed diff is applied only through
  a row 2 or 3 the classifier picked.
- Rows 4 and 5: list each deletion and merge with its reason and apply it only after the user says
  yes to that item. A row 4 whose logic lives in a collaborator gets that test in the same batch.
- A file whose adapter has `block_model: file` (`bash-harness`) is rewrite-only: never delete or
  merge it, or checks inside it.
- When `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-config.sh"` prints `rules.test-weaken-block`
  `error`, each deletion carries a `test-change: cleanup row <n>: <reason>` comment at the edit.
- Gate-blind: a changed or deleted test none of whose imported production files holds a
  `before.tsv` row is marked gate-blind and needs the user's yes, even for a rewrite.

Unattended, apply only the row 2 and 3 rewrites that are not gate-blind, and leave every yes-gated
item listed and unapplied.

### 6. Gate

Invoke `/mutation-testing:audit --exercised <folder> --replay-mutants <work>/before.tsv
--record-mutants <work>/after.tsv` through the Skill tool and read its `Gate:` line.

- A red replay baseline (a changed test fails on unmutated code) stops the batch and names the
  failing tests.
- `Gate: block`: the batch stops. For each `newly-surviving <path>:<line> <operator>` line, list the
  candidate changes: the batch's changed tests that import `<path>`. The user reverts the ones they
  choose; then replay again. Cleanup reverts nothing itself.
- `Gate: pass`: go on.
- Any other outcome (no `Gate:` line, a refusal, a compare that could not run) stops the batch the
  same way. Only `Gate: pass` reaches step 7.

### 7. Report and commit

Write the decision table and the gate result (K0 and K1, each newly surviving mutant with its
triage) to `<work>/pr-body.md`, and the findings file to the branch's findings directory,
`.work/reviews/<branch-slug>/<YYYYMMDDTHHMMSSZ>-testing-cleanup.md`, the slug and home as
`/review:fanout` "Shared inputs" defines them. One row per candidate that a rule selected, in the
shape `plugins/review/reference/findings-file-shape.md` gives: `Tier` and `Confidence` copied from
the source row, `Surface(s)` `testing:cleanup`, `Finding` the source row's `Finding` (rule id and
threshold first) followed by `cleanup row <n>: <action>`, `Action` reading `applied by /testing:cleanup in this branch;
review, do not re-apply` (or `kept: <reason>`). Quarantined tests have no rule and appear in
`pr-body.md` only.

Show the batch and wait for the user's approval. Then commit the batch's files only (named paths,
never `git add -A`) and delete `before.tsv` and `after.tsv`. Push and the draft pull request go
through `/source-control:pull-request` when that plugin is installed, otherwise leave them to the
user. Unattended runs stop before the commit.

## What this skill does NOT do

- Commit without the user's approval of the batch, or delete, merge or revert any test without a
  yes on that item.
- Detect flaky tests, sweep expired quarantines, or bisect a lost kill.
- Clean more than one folder per batch, or turn the `test-weaken` hook off.

## Next

/source-control:pull-request create

Opens the batch's draft pull request with `pr-body.md` as its body.

## Gotchas

- **The gate is necessary, not sufficient.** A replay that passes says no recorded kill was lost.
  It says nothing about behavior no mutant reached, so every deletion still needs its row 4 or 5
  reason and the user's yes.
- **"No caller found" is not a no-contract statement.** A contract reached through dependency
  injection, reflection or an HTTP route does not show up in a search; that test is rewritten or
  kept.
- **The gate compares sets, not tests.** A weakened test passes the gate when another changed test
  in the batch now kills the same mutants. Each rewrite is still
  reviewed on its own row; per-test kill attribution is not built.
- **A record outlives nothing.** Production code that changes between the two runs makes the replay
  refuse. Finish a batch before rebasing it.
