# PLAN: tautological-tests-judge (Release 2 task-end judge)

## Brief

The contract is the Brief in `docs/specs/tautological-tests.md` (Q1-Q13, amendments A1-A14). This
plan changes it in two places, both user decisions recorded in Phase 1: the Q12 rater wording, and
Q7's "tests still in doubt" read as "tests the session created or changed that no deterministic rule
has cleared" (design DT13). Release 2 scope from that spec's "Release 2 outline":

| Outline item | Where in this plan |
|---|---|
| Stop/SubagentStop judge on a different model, provenance only, FLAG/PASS/UNKNOWN with quoted evidence, advisory, proposes fixes and never commits them | Phases 2-3 |
| First item: probe whether prompt or agent hooks fit | Phase 1 (design DT6/DT16 chose command hooks and a headless judge; the probes confirm their facts) |
| Labeled calibration set, two raters, seeded from the judge rows plus G7 and G10 | Phase 4 |
| `mutation-testing:audit` scope for production code the changed tests exercise | Out of this plan: its own later plan (user, 2026-09-29) |
| Resolve the ImpossibleBench ">79%" section | Phase 1 (Section 4.2, per the Release 2 research) |
| Evaluate PostToolUse `bashEditDiff` | Deferred in design (research tag recorded) |

Design: `design/design-threads.md` beside this file (DT1-DT16). Goal: catch a tautological test
(expected value restates the implementation) that the session wrote, before the task ends, and
propose a fix for approval, to a bar Matt Pocock would approve.

Architecture (DT16): the judge is a headless `claude -p` run with a fixed prompt, a model class
alias and read-only tools. A background job starts it soon after a test is written and writes the
verdict to an on-disk ledger; the Stop hook waits only for jobs still running, judges any test with
no verdict synchronously, and relays the verdicts in the same session. The writing agent never
supplies the judge's prompt, model or output.

## Plan

Standards grounding: `AGENTS.md` (draft PRs, Conventional Commits titles, unattended lanes run in
auto mode), `.claude/rules/pr-body-contract.md`, `docs/conventions/topic-docs/README.md` and
`scripts/check-contract-slice-prune.sh` (a PR may not leave a path under `docs/topics/`),
`docs/conventions/detector-findings/README.md` (findings shape),
`.claude/rules/skill-bodies-state-current-rules.md` (judge prompt file), `scripts/check-hook-userconfig-argv.sh`
header (userConfig `default` is not delivered, #46477), `code.claude.com/docs/en/hooks.md` "Run hooks
in the background" (async hooks: no timeout enforced, killed at `-p` teardown, no dedup).

Test strategy: TDD for every script (Red, Green, Refactor). Test boundaries:

- `plugins/testing/hooks/test-scan.sh` through `test-scan.test.sh`, payload on stdin (existing).
- New hook scripts `test-judge-bg.sh` (PostToolUse async), `test-judge.sh` (Stop) and
  `test-judge-start.sh` (SessionStart) through `.test.sh` files: payload on stdin, fixture state and
  transcripts, the scanner stubbed through `TEST_SCAN_SCANNER` (existing seam) and the judge command
  stubbed through a new `TEST_JUDGE_CMD` seam.
- `plugins/testing/scripts/gen-hook-filters.sh` through `gen-hook-filters.test.sh` (existing).
- `judge-calibration/metrics.sh` through `metrics.test.sh`, known-answer cases (new).
- Judge verdict quality is measured by Phase 4, not by unit tests.

### Phase 1: Live probes, spec housekeeping, graduation [TODO]

Probes in a scratch repo under `.work/tautological-tests-judge/probe/` (gitignored), with `claude -p`
sessions and throwaway hooks. Each is a row `| R2-P<n> | ... |` (version, command, observed output,
verdict `holds` or `fails`, and for a failed gating probe the design thread it was routed to) in a
new "Release 2 probes" section of `docs/specs/tautological-tests/probes.md`.

1. Subagent tool calls carry the parent `session_id` (DT8).
2. `.message.model` on assistant lines of a transcript that contains an Agent spawn; the id format
   for sonnet and opus sessions; `<synthetic>` lines (DT3).
3. Judge child: `claude -p --model <alias> --tools Read,Grep,Glob --settings '{"disableAllHooks":true}'`
   started from a hook runs with the session's login (no credential printed), loads no plugin hook,
   and honors the alias. Also whether `CLAUDE_CODE_CHILD_SESSION` is set in the hook environment
   (DT16).
4. An `async: true` PostToolUse command hook keeps running while the session continues; its process
   survives the turn; what happens to it on `/clear` and on interactive exit (DT16).
5. `systemMessage` from a Stop command hook reaches the user.
6. `decision: block`, then `stop_hook_active: true` on the following Stop.
7. Tokens and wall time per judge run, for one test and for ten.
8. `session_id` after `/clear`, after `--resume`, and after a fork.
9. A Stop block in `claude -p` and in an auto-mode session: where the forced turn and
   `systemMessage` go, and the `permission_mode` value (DT15).
10. Two blocking Stop command hooks in one Stop: the delivered reason(s) and the block count.
11. Where test-scan's `DATA` resolves when started from the consumer settings entry
    (`test-scan.sh --enabled`) versus the plugin hook.

Gating: probe 3, 5, 6 or 9 failing stops the plan and routes to `/planning:design`. Probe 4 failing
drops the precompute half of DT16 (the Stop hook judges everything synchronously, DT16's own
fallback). A failed probe 2 drops the session-model comparison. A failed probe 8 adds
cwd-plus-transcript-directory keying to Phase 2 through `/planning:plan review`.

Housekeeping:

- `docs/specs/tautological-tests/precision-run.md:187`: medley's test was rewritten (medley#2074),
  not annotated.
- `docs/specs/tautological-tests.md:871`: "Section 5" becomes "Section 4.2 (Conflicting-SWEbench:
  the share of cheating transcripts that modified tests)".
- Dated Q12 amendment under spec:101-104: "Amended 2026-09-29 (user): the judge's labeled set is
  rated by the user and a model rater of a different model class from the judge's."
- Dated Q7 amendment: "Amended 2026-09-29 (user, design DT13): tests still in doubt are the test
  blocks the session created or changed that no deterministic rule has cleared."
- Graduation: `git mv docs/topics/tautological-tests-judge docs/specs/tautological-tests-judge`
  before PR A flips ready; spec:877 becomes `test -f docs/specs/tautological-tests-judge/PLAN.md`
  in the same commit. Later phases edit the graduated files.

**Sanity Check:**

- `grep -cE '^\| R2-P([1-9]|1[01]) \|' docs/specs/tautological-tests/probes.md` returns 11.
- `grep -E '^\| R2-P(3|5|6|9) \|.*\| fails \|' docs/specs/tautological-tests/probes.md | grep -vc 'DT[0-9]'` returns 0 (a failed gating probe names its design thread).
- `grep -c 'does not yet' docs/specs/tautological-tests/precision-run.md` returns 0.
- `grep -c 'Section 5' docs/specs/tautological-tests.md` returns 0.
- `grep -c 'Amended 2026-09-29 (user' docs/specs/tautological-tests.md` returns 2.
- `test -f docs/specs/tautological-tests-judge/PLAN.md && ! test -e docs/topics/tautological-tests-judge` passes.
- `bash scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0.

### Phase 2: Block listing and session state (DT8, DT13) [TODO]

Scanner: `cant-fail-scan.sh` has no block-listing output (`--inventory` prints counts only), so add
`--blocks`, printing `block <file>:<start>-<end> <name>` from `close_block()` for each examined
block in scope, in the same run test-scan already makes. For `block_model: file` adapters
(bash-harness) it prints the patch range instead of the whole file.

`plugins/testing/hooks/test-scan.sh` passes `--blocks` and appends one line to
`$DATA/sessions/<session_id>.jsonl` per scanned write, including the scanner error and timeout paths;
only the gitignored and 0-examined skips (test-scan.sh:42-44, :110) write nothing. Fields: `file`,
`repo` (the file's git toplevel), `agent_id`, `create`, `blocks` (`[{name, start, end}]` for the
blocks this write created or changed; `null` on scanner failure, meaning "whole file"), and
`ok_markers` (count of `cant-fail-ok:` in the file, first sight and every write).

- Session id must match `^[A-Za-z0-9_-]+$`, else no write.
- Prune `$DATA/sessions/` files older than 7 days beside the `marks/` prune (test-scan.sh:63).
- `cant-fail-scan.test.sh`: one `--blocks` case per adapter family (brace JS and C#, C# `=>` body,
  indent Python, bats `@test`, Pester `It`, Go, bash-harness patch range), asserting start and end.
- `test-scan.test.sh`, Red first: create records every block; edit records only the edited block;
  a clean file still records its blocks; scanner timeout records `blocks:null`; marker count
  recorded; gitignored path and `../x` or empty ids write nothing.

**Sanity Check:**

- `bash plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` and
  `bash plugins/testing/skills/audit/scripts/parity-check.sh` exit 0, locally and under
  `docker run ubuntu:24.04` (gawk 5.2.1).
- `bash plugins/testing/hooks/test-scan.test.sh` exits 0.
- Every suite `bash scripts/affected-tests.sh` prints for the touched files exits 0.

### Phase 3: Background judge, Stop relay, SessionStart catch-up (DT2-DT4, DT10, DT12-DT16) [TODO]

Shared pieces:

- Key = `file::block name::sha of the block text` (range from `--blocks`). A key is in doubt when
  its block was created or changed this session, or its file's `cant-fail-ok:` count rose above the
  first-seen count (DT13).
- Ledger: `$DATA/verdicts/<session_id>/<key-hash>.json`, written with a temp file and `mv` so a
  reader never sees half a verdict. Lock: `$DATA/locks/<key-hash>` via noclobber. Relayed marker:
  `$DATA/relayed/<session_id>`.
- Judge command (one function, used by both hooks and by Phase 4):
  `claude -p --model <alias> --tools Read,Grep,Glob --settings '{"disableAllHooks":true}'` with the
  prompt from `plugins/testing/hooks/test-judge-prompt.md`, the file path and block range as input,
  and `TEST_JUDGE_ACTIVE=1` exported so every judge hook exits at once inside it. The prompt asks
  only where each expected value came from (DT1), ignores any hint in the test text, and returns
  quoted evidence, then FLAG, PASS or UNKNOWN, the source of the expected value, and for FLAG a
  proposed diff, as a fixed JSON block. The prompt file is frozen before Phase 4 labels are read.
- Model: `${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_MODEL:-sonnet}`, fallback
  `${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_FALLBACK_MODEL:-opus}`, each validated against
  `fable|opus|sonnet|haiku`. Session model: the last `select(.type=="assistant") | .message.model`
  other than `<synthetic>` in `tail -n 400 "$transcript_path"`, read with `jq -R 'fromjson? | ...'`.
  If the judge class matches the session model, the fallback; if that matches too, the first
  allowlisted class that does not. The verdict records the model that ran.

New `plugins/testing/hooks/test-judge-bg.sh` (PostToolUse, `async: true`, same `if` rows as
test-scan, after it): read the session line test-scan just wrote; for each in-doubt key, sleep the
debounce (`TEST_JUDGE_DEBOUNCE`, default 20 s), re-hash the block, exit if it changed (a newer write
owns it), skip if a verdict or lock exists, else take the lock, run the judge, write the verdict,
release the lock. Never prints output (Q7: nothing mid-task).

New `plugins/testing/hooks/test-judge.sh` (Stop, synchronous). No library is sourced before the
no-state-file exit.

1. `stop_hook_active` true and `relayed/` names the current verdict set: exit 0 (no re-block).
2. Collect in-doubt keys (missing files logged and skipped). Empty: exit 0.
3. Keys with a verdict are ready. Keys with a live lock are waited on; keys with neither (job killed
   at `-p` teardown, crashed, or never started) are judged now, at most 10 per Stop, the rest named
   as waiting. All waiting and judging is bounded by `TEST_JUDGE_TIMEOUT` (default 180 s, below a
   generated Stop `timeout` of 240 s). On exhaustion or judge failure: a `systemMessage` naming the
   tests not judged; after 2 failed attempts per key, "judge not run for <test>".
4. Write the findings file (detector-findings shape, destination resolved per that contract) from
   the ledger, and record the verdict set in `relayed/`.
5. Attended: `{"decision":"block","reason":...}` whose reason carries the verdicts and proposed
   diffs verbatim: present them, apply nothing, wait for the user. Unattended (`permission_mode`
   auto or bypassPermissions, per probe 9): a `systemMessage` with counts and the findings path, no
   block. Either way the `systemMessage` carries the counts, so the user sees them unfiltered.

New `plugins/testing/hooks/test-judge-start.sh` (SessionStart): names any ledger verdict for this
repo not in `relayed/` (a session that ended mid-task), as a `systemMessage` with the findings path.

Tests, Red first:

- `test-judge-bg.test.sh`: a created test is judged once and its verdict written atomically; a
  block changed during the debounce exits without judging; a second firing for the same key finds
  the lock and exits; `TEST_JUDGE_ACTIVE=1` exits at once; judge failure leaves no verdict and
  releases the lock; nothing is printed.
- `test-judge.test.sh`: flag off; no state; nothing in doubt; verdicts ready give one block carrying
  them verbatim; `stop_hook_active` with a relayed set exits; a live lock is waited on; a key with no
  job is judged at Stop; the 11th key waits and is named; budget exhaustion gives a
  `systemMessage` and no block; 2 failed attempts give "judge not run"; an untouched test in an
  edited file is not in doubt; a new `cant-fail-ok:` marker is; keys unset use `sonnet`/`opus`;
  invalid alias falls back; Agent-call and `<synthetic>` lines do not change the session model;
  class collisions pick the fallback, then a third class; unattended mode gives no block; a
  malformed state line is skipped; `TEST_JUDGE_ACTIVE=1` exits at once.
- `test-judge-start.test.sh`: an unrelayed verdict is named; a relayed one is not; another repo's is
  not.

Other files:

- `plugins/testing/.claude-plugin/plugin.json`: `test_judge_enabled` (boolean, default false,
  description names the `test_guards_enabled` dependency), `test_judge_model` (string, `sonnet`),
  `test_judge_fallback_model` (string, `opus`); version bump.
- `plugins/testing/scripts/gen-hook-filters.sh` and test: a PostToolUse `async: true` row set for
  `test-judge-bg.sh`, a `Stop` entry (`timeout: 240`) and a `SessionStart` entry, all through
  `exec-bash.mjs --require-true TEST_GUARDS_ENABLED --require-true TEST_JUDGE_ENABLED`
  (exec-bash.mjs:70-89 takes several gates); the hooks.json `description` names both keys.
  Regenerate `hooks.json`; never hand-edit it.
- `plugins/testing/skills/setup/SKILL.md` and README: the three keys, the tunable-versus-fixed split
  (DT12), the reach limits (DT13: stubs in `beforeEach` and `.snap` files are outside the block),
  and, per probe 11, whether globs added only through the consumer settings entry are judged.
- `plugins/testing/CHANGELOG.md` entry.

**Sanity Check:**

- `bash plugins/testing/hooks/test-judge-bg.test.sh`, `bash plugins/testing/hooks/test-judge.test.sh`
  and `bash plugins/testing/hooks/test-judge-start.test.sh` exit 0.
- `bash plugins/testing/scripts/gen-hook-filters.test.sh` exits 0;
  `jq '.hooks.Stop | length' plugins/testing/hooks/hooks.json` and
  `jq '.hooks.SessionStart | length' plugins/testing/hooks/hooks.json` each return 1, and
  `jq '[.hooks.PostToolUse[].hooks[] | select(.async == true)] | length' plugins/testing/hooks/hooks.json`
  returns at least 1.
- `jq -r '.userConfig.test_judge_enabled.default' plugins/testing/.claude-plugin/plugin.json` prints `false`.
- `bash scripts/validate-plugins.sh`, `bash scripts/check-hooks-description.sh`,
  `bash scripts/check-hook-userconfig-argv.sh` and
  `bash scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.
- Manual probe R2-P12 in the scratch repo, once from `--plugin-dir` and once from an installed copy:
  writing `expect(add(a, b)).toBe(a + b)` gives a ledger verdict before the Stop, one forced turn
  carrying it, and the counts in a `systemMessage`; a hand-computed literal gives PASS; an ignored
  forced turn is not repeated. `grep -c '^| R2-P12 |.*holds' docs/specs/tautological-tests/probes.md` returns 1.
- Manual probe R2-P13: a scripted 5-turn TDD session writing about 15 tests; records forced turns,
  judge runs discarded by the debounce, judge tokens and the Stop wait. `grep -c '^| R2-P13 |'
  docs/specs/tautological-tests/probes.md` returns 1.
- Manual probe R2-P14 through `/fleet:reach` on a Windows host (user-gated at run time): idle Stop
  latency, target under 500 ms, and the Stop wait with 5 in-doubt tests. `grep -c '^| R2-P14 |'
  docs/specs/tautological-tests/probes.md` returns 1.

### Phase 4: Calibration set and first measurement (DT1, DT9, DT13) [TODO]

- `plugins/testing/skills/audit/evals/judge-calibration/`: `cases/*.fixture`, `labels.tsv` (DT9
  columns plus `stratum` and `split`), `metrics.sh`, `metrics.test.sh` (known-answer kappa, confusion
  matrix and Wilson interval cases, Red first).
- The judge runs through the same judge command function the hooks use (Phase 3), so calibration
  measures exactly what runs in use.
- Stratum `in-use`: test blocks sampled at random from tests added in the three repos' git histories
  (the population the hooks send under DT13), at natural prevalence. Stratum `seed`: the DT1 seeds.
  Before labeling, record how many in-use cases were drawn and how many carried a provenance defect;
  if FLAG falls short of 30, record the achieved n and its interval rather than padding.
- Split: at least a third of each stratum is `holdout`; the prompt file stays frozen, and any prompt
  change after seeing `tune` results is re-measured on `holdout` only.
- The model rater (a subagent of a class other than the judge's) labels every case blind. User gate:
  the user labels every case blind to it; disagreements are adjudicated with the user.
- `metrics.sh` reports per stratum: kappa user vs model rater, judge vs user, judge vs model rater,
  the judge's confusion matrix, precision and recall on FLAG with Wilson intervals, prevalence, and
  UNKNOWN counts. System recall is stated as covering tests the session created or changed.
- `docs/specs/tautological-tests-judge/calibration.md` records protocol and results.

**Sanity Check:**

- `bash plugins/testing/skills/audit/evals/judge-calibration/metrics.test.sh` exits 0.
- `bash plugins/testing/skills/audit/evals/judge-calibration/metrics.sh --check` exits 0: every row
  has both labels, a stratum and a split; holdout is at least a third per stratum; user-vs-model
  kappa is at least 0.6; the last commit touching `test-judge-prompt.md` predates the first commit
  touching `labels.tsv`, or later prompt changes carry holdout-only metrics.
- `grep -cE '^kappa (user-model|judge-user|judge-model)' docs/specs/tautological-tests-judge/calibration.md` returns at least 3.
- `bash scripts/check-orphaned-fixtures.sh --check` exits 0.

### Phase 5: Close out [TODO]

- Spec Release 2 outline: judge items `[DONE]`; the mutation scope stays `[TODO]`.
- All phase tags here `[DONE]`.

**Sanity Check:**

- `grep -c '\[TODO\]' docs/specs/tautological-tests-judge/PLAN.md` returns 0.
- `git grep -n 'docs/topics/tautological-tests-judge'` returns nothing.

## Blast radius

Blast-radius: MEDIUM. Three new opt-in hooks (async PostToolUse, Stop, SessionStart), a headless
judge command, three userConfig keys and a scanner flag, in one plugin; off by default, reversible
by git revert. Hook infrastructure, a model-spending background process and undocumented behavior
(transcript fields, async hook lifetime) are stress-test triggers.

## Stress-test summary

- Plan reviewer (fresh context): 1 CRITICAL, 9 IMPORTANT, 7 SUGGESTION; all verified and fixed.
- Devil's advocate round 1: 2 CRITICAL, 7 HIGH, 7 MEDIUM, 3 LOW. CRITICALs and the unattended HIGH
  went to design (DT13-DT15); the rest folded in.
- Devil's advocate round 2: 1 CRITICAL, 4 HIGH, 6 MEDIUM, 2 LOW. The CRITICAL (re-block loop) and
  the HIGHs on the writer controlling the judge and the SubagentStop race went to design: DT16
  replaces the writer-dispatched judge with a hook-run headless judge and an on-disk ledger (research
  `.work/tautological-tests-judge-concurrency/`, verifier fail rows 4, 7, 12; the design-bearing
  hooks.md facts rechecked by curl). Folded in: block ranges from `--blocks` (all adapter families),
  bash-harness patch-range only, honest S3/G7 reach, budget exhaustion shown to the user, gated probe
  rows must name a design thread, kappa and prompt-freeze checks in `metrics.sh --check`, TDD-session
  cost probe.
- Devil's advocate round 3 (final): pending.

## Execution shape

Fully sequential: Phase 1 gates Phase 2 (probes 1, 8, 11), Phase 2 gates Phase 3 (block ranges and
state), Phase 3 gates Phase 4 (the judge command must exist). Main session throughout.

PR slicing: PR A = design, this plan and Phase 1; PR B = Phases 2-3; PR C = Phases 4-5. Each opens
as a draft, with its own version bump where a plugin changes.

## Open questions

- None at draft time.

## Handoff to implementation

Approval: pending

### User-approval gates

- Phase 1: a failing gating probe routes to `/planning:design`; the Windows probe runs only with the
  user's go-ahead at that time.
- Phase 4: the user's blind labels and the adjudication.
- Every push, PR creation and PR ready flip.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential, main session, in a worktree under the user's worktrees root.

### Mechanical work

Commit per phase with `git commit -F - --cleanup=verbatim`; run the touched suites plus
`scripts/affected-tests.sh`, never `scripts/run-plugin-tests.sh` locally (handoff h3). Scanner
changes run under `docker run ubuntu:24.04` for gawk 5.2.1 (handoff h8).
