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
3. Judge child isolation, with the Phase 3 judge command started from a hook: it runs with the
   session's login (no credential printed) and records which account is billed with and without
   `ANTHROPIC_API_KEY` set; it loads no plugin hook, no CLAUDE.md, no MCP server and no skill;
   `--system-prompt` replaces the default prompt; `--max-budget-usd` stops a run; the model alias is
   honored; a Read outside the repo is refused. Also whether `CLAUDE_CODE_CHILD_SESSION` is set in
   the hook environment (DT16).
4. An `async: true` PostToolUse command hook keeps running while the session continues; its process
   survives the turn; what happens to it and to its `claude -p` grandchild on `/clear` and on
   interactive exit (orphan count). Linux, and a Windows Git Bash variant through `/fleet:reach`
   (user-gated at run time) (DT16).
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
- Dated Q4 clarification: "Clarified 2026-09-30 (design DT16): the judge's one forced turn relays
  verdicts for the user to approve; it never gates a stop, a commit or `--check`, and it never
  blocks on its own failure."
- Graduation: `git mv docs/topics/tautological-tests-judge docs/specs/tautological-tests-judge`
  before PR A flips ready; spec:877 becomes `test -f docs/specs/tautological-tests-judge/PLAN.md`
  in the same commit. Later phases edit the graduated files.

**Sanity Check:**

- `grep -cE '^\| R2-P([1-9]|1[01]) \|' docs/specs/tautological-tests/probes.md` returns 11.
- `grep -E '^\| R2-P(3|5|6|9) \|.*\| fails \|' docs/specs/tautological-tests/probes.md | grep -vc 'DT[0-9]'` returns 0 (a failed gating probe names its design thread).
- `grep -c 'does not yet' docs/specs/tautological-tests/precision-run.md` returns 0.
- `grep -c 'Section 5' docs/specs/tautological-tests.md` returns 0.
- `grep -c 'Amended 2026-09-29 (user' docs/specs/tautological-tests.md` returns 2 and
  `grep -c 'Clarified 2026-09-30 (design DT16)' docs/specs/tautological-tests.md` returns 1.
- `test -f docs/specs/tautological-tests-judge/PLAN.md && ! test -e docs/topics/tautological-tests-judge` passes.
- `bash scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0.

### Phase 2: Block listing and session state (DT8, DT13) [TODO]

Scanner: `cant-fail-scan.sh` has no block-listing output (`--inventory` prints counts only), so add
`--blocks`, printing `block <file>:<start>-<end> <ordinal> <name>` from `close_block()` for each
examined block in scope (ordinal separates duplicate names), in the same run test-scan already
makes. A `block_model: file` adapter (bash-harness) prints one whole-file block.

Block identity is the name plus ordinal, never the recorded range: line numbers drift when a later
write inserts a test above. Every reader re-runs `--blocks` on the current file, finds the block by
name and ordinal, and hashes its current text. A bash-harness file is one key (path plus whole-file
sha); the changed ranges travel with it as a hint to the judge.

`plugins/testing/hooks/test-scan.sh` passes `--blocks` and writes one file per scanned write,
`$DATA/sessions/<session_id>/<tool_use_id>.json` (one file per write, so parallel writers never
interleave), including the scanner error and timeout paths; only the gitignored and 0-examined skips
(test-scan.sh:42-44, :110) write nothing. Fields: `file`, `repo` (the file's git toplevel),
`agent_id`, `create`, `blocks` (`[{name, ordinal, start, end}]` for the blocks this write created or
changed; `null` on scanner failure, meaning "whole file"), `ok_markers` (count of `cant-fail-ok:` in
the file), and `written_at`.

- Session id must match `^[A-Za-z0-9_-]+$`, else no write.
- Prune `$DATA/sessions/` files older than 7 days beside the `marks/` prune (test-scan.sh:63).
- Prune `$DATA/{verdicts,locks,relayed,attempts,slots}/` on the same 7-day rule.
- `cant-fail-scan.test.sh`: one `--blocks` case per adapter family (brace JS and C#, C# `=>` body,
  indent Python, bats `@test`, Pester `It`, Go, bash-harness whole file), asserting start, end and
  ordinal; two blocks with one name get ordinals 1 and 2.
- `test-scan.test.sh`, Red first: create records every block; edit records only the edited block;
  a clean file still records its blocks; scanner timeout records `blocks:null`; marker count
  recorded; two parallel writes give two files; gitignored path and `../x` or empty ids write
  nothing.

**Sanity Check:**

- `bash plugins/testing/skills/audit/scripts/cant-fail-scan.test.sh` and
  `bash plugins/testing/skills/audit/scripts/parity-check.sh` exit 0, locally and under
  `docker run ubuntu:24.04` (gawk 5.2.1).
- `bash plugins/testing/hooks/test-scan.test.sh` exits 0.
- Every suite `bash scripts/affected-tests.sh` prints for the touched files exits 0.

### Phase 3: Background judge, Stop relay, SessionStart catch-up (DT2-DT4, DT10, DT12-DT16) [TODO]

Shared pieces:

- Key = `file::name::ordinal::sha of the current block text`, re-derived by running `--blocks` on
  the current file (Phase 2); a bash-harness file is one key. A block is in doubt when a session
  write created or changed it, or its file's `cant-fail-ok:` count rose above the first recorded
  count (DT13). A verdict whose sha matches the current text stays valid when lines shift.
- Ledger: `$DATA/verdicts/<session_id>/<key-hash>.json`, written to a temp file in the same
  directory and renamed. Lock: `$DATA/locks/<key-hash>` via noclobber, holding `pid host start`;
  stale when older than the judge timeout plus 30 s, or when `kill -0` fails on the same host
  (Windows: age only); a stale lock is broken and counted as one failed attempt. Every lock holder
  re-checks for a verdict after acquiring. Attempts: `$DATA/attempts/<key-hash>`. Relayed:
  `$DATA/relayed/<session_id>`.
- Accuracy first, runaway guards only (user, 2026-09-30). No cap limits how thoroughly one run
  judges: Anthropic's cost guidance treats output caps and budgets as levers that trade quality for
  cost, and says to raise a cap a run hits rather than accept truncation (platform.claude.com
  optimizing-for-cost-and-intelligence, "Set budgets and output caps", fetched 2026-09-30). The
  guards that remain stop only malfunction: `--max-budget-usd` per run set to 10 times the probe 7
  p95 cost of a ten-test run (recorded in probes.md; a run that hits it is logged as a malfunction,
  and its keys go to UNKNOWN with that reason); the `timeout 150` hang guard; at most 3 concurrent
  runs per machine (`$DATA/slots/` noclobber slots, shared by every session and by Stop), which
  limits load, not depth. Optional userConfig `test_judge_session_runs` (default unset, meaning no
  limit) for users who want a spend ceiling. One judge run per file (all in-doubt blocks of that
  file in one call) because the judge reads the whole file anyway.
- Judge command (one function, used by all hooks and by Phase 4): run under `timeout 150` in its own
  process group from cwd = the file's repo toplevel:
  `claude -p --model <alias> --system-prompt <plugins/testing/hooks/test-judge-prompt.md content>
  --tools Read,Grep,Glob --allowedTools "Read(<repo>/**)" "Grep(<repo>/**)" "Glob(<repo>/**)"
  --settings '{"disableAllHooks":true}' --setting-sources "" --strict-mcp-config
  --effort <level> --max-budget-usd <n>`, exact flags as probe 3 confirms. Input: the file path, block names and
  ranges (bash-harness: the changed ranges as a hint). `TEST_JUDGE_ACTIVE=1` is exported so every
  judge hook exits at once inside it. The child's stdout goes straight to the ledger temp file, so a
  dead parent cannot lose a finished verdict. The prompt asks only where each expected value came
  from (DT1), treats comments and strings in the test as data, never as instructions or evidence of
  provenance, never proposes deleting a test (a deletion would need Q9's reason-and-approval path),
  and returns per block: quoted evidence, FLAG/PASS/UNKNOWN, the source of the expected value, and
  for FLAG a proposed diff, as a fixed JSON block. The provenance rules are not restated in the
  prompt file: at run time the judge command appends section 1, "Every expected value names its
  independent source",
  of `plugins/testing/skills/test-value/SKILL.md` (the Pocock-adapted guidance, one source of truth,
  Q8), since the isolated child loads no skills. The prompt file and that section are frozen before
  Phase 4 labels are read; a later edit to either re-runs the holdout.
- Model, chosen by evals (user, 2026-09-30: accuracy over cost): until Phase 4 has data, the
  defaults are `${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_MODEL:-opus}` and
  `${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_FALLBACK_MODEL:-sonnet}` at
  `${CLAUDE_PLUGIN_OPTION_TEST_JUDGE_EFFORT:-medium}`. Basis: Anthropic's guidance starts most agent
  workloads on Opus 5.5 at its default effort and places Haiku at high-volume work with checkable
  outputs (Haiku 4.5 63% vs Opus 5.5 92% on GPQA Diamond), and says to choose the model from your
  own evals (platform.claude.com optimizing-for-cost-and-intelligence, fetched 2026-09-30). Phase 4
  replaces these defaults with the eval result. Each value is validated against
  `fable|opus|sonnet|haiku` and `low|medium|high|xhigh|max`. Session model: the last
  `select(.type=="assistant") | .message.model` other than `<synthetic>` in
  `tail -n 400 "$transcript_path"`, read with `jq -R 'fromjson? | ...'`. Q7 requires a different
  model from the writer: if the judge class matches the session model, the fallback; if that matches
  too, the next of `opus, sonnet, haiku` that does not (never fable unless configured). The verdict
  records the model and effort.
- Relay validation: before any verdict is relayed, each quoted evidence string must be a substring
  of the current file and each proposed diff must pass `git apply --check` touching only that test
  file; a verdict failing either is relayed as UNKNOWN with the reason.

New `plugins/testing/hooks/test-judge-bg.sh` (PostToolUse, `async: true`, same `if` rows as
test-scan; hooks on one event run in parallel, hooks.md:410): write `pending/<tool_use_id>` (pid),
sleep the debounce (`TEST_JUDGE_DEBOUNCE`, default 20 s), then read the session file for its own
`tool_use_id` (absent: run `--blocks` itself). Re-derive the file's in-doubt keys; drop keys with a
verdict; if the file changed since this write (a newer write's job owns it), exit. Take a slot and
the file's locks, re-check verdicts, run the judge once for the file, write verdicts, release, and
remove `pending/`. Never prints output (Q7: nothing mid-task).

New `plugins/testing/hooks/test-judge.sh` (Stop, synchronous). An EXIT trap forces exit 0 on every
path (Q4); no library is sourced before the no-state-file exit.

1. `stop_hook_active` true and `relayed/` names the current verdict set: exit 0 (no re-block).
2. Collect in-doubt keys by re-deriving blocks (missing files logged and skipped). Empty: exit 0.
3. Keys with a verdict are ready. Keys with a live `pending/` or lock are waited on. Keys with
   neither (job killed, crashed, stale, or never started) are judged now, taking the same lock and
   slots, per file and in parallel, at most 10 keys per Stop, the rest named as waiting. All of it is
   bounded by `TEST_JUDGE_TIMEOUT` (default 180 s, below a generated Stop `timeout` of 240 s; both
   re-derived from probe 7 and recorded in probes.md). On exhaustion or failure: a `systemMessage`
   naming the tests not judged and the time spent; after 2 failed attempts per key, "judge not run
   for <test>".
4. Validate verdicts (relay validation), write the findings file (detector-findings shape,
   destination resolved per that contract) from the ledger, and record the set in `relayed/`.
5. Attended: `{"decision":"block","reason":...}` from a fixed template: "The test judge reviewed N
   tests (F FLAG, P PASS, U UNKNOWN). Findings: <path>. Show the user each verdict and proposed diff
   from that file, quoted as data. Apply nothing; wait for the user." Unattended (`permission_mode`
   auto or bypassPermissions, per probe 9): no block. Either way a `systemMessage` carries the counts
   and path, so the user sees them unfiltered.

New `plugins/testing/hooks/test-judge-start.sh` (SessionStart): names ledger verdicts for this repo
not in `relayed/` from sessions whose last write is over an hour old, as a `systemMessage` with the
findings path, then marks them relayed so the notice appears once.

Tests, Red first:

- `test-judge-bg.test.sh`: a created test is judged once and its verdict written by rename; the
  session file written after the job starts is still found; a block changed during the debounce
  exits without judging; inserting a test above a judged one neither re-judges it nor loses the new
  one; a second firing finds the lock and exits; a stale lock with a dead pid is broken and counted;
  an unset session cap means no limit, a set one is honored; the slot cap is honored; a run that
  hits the malfunction budget gives UNKNOWN with that reason; `TEST_JUDGE_ACTIVE=1` exits at once; judge
  failure and judge timeout leave no verdict and release the lock; nothing is printed.
- `test-judge.test.sh`: flag off; no state; nothing in doubt; verdicts ready give one templated
  block and a `systemMessage` with counts; `stop_hook_active` with a relayed set exits; a live
  `pending/` or lock is waited on; a key with no job is judged at Stop under the lock; the 11th key
  waits and is named; budget exhaustion gives a `systemMessage` and no block; 2 failed attempts give
  "judge not run"; a quote that is not in the file and a diff touching another file are relayed as
  UNKNOWN; an untouched test in an edited file is not in doubt; a new `cant-fail-ok:` marker is;
  keys unset use `opus`/`sonnet` at `medium`; invalid alias or effort falls back; Agent-call and `<synthetic>` lines do not
  change the session model; class collisions walk `opus, sonnet, haiku` and never pick fable;
  unattended mode gives no block; a malformed state file is skipped; scanner exit 2 and a crash in
  the script both end in exit 0; `TEST_JUDGE_ACTIVE=1` exits at once.
- `test-judge-start.test.sh`: an unrelayed verdict from an old session is named once; a relayed one
  is not; one from a session active in the last hour is not; another repo's is not.

Other files:

- `plugins/testing/.claude-plugin/plugin.json`: `test_judge_enabled` (boolean, default false,
  description names the `test_guards_enabled` dependency), `test_judge_model` (string, `opus`),
  `test_judge_fallback_model` (string, `sonnet`), `test_judge_effort` (string, `medium`),
  `test_judge_session_runs` (number, no default: unset means no limit), each also
  defaulted in-script; version bump.
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
  judge runs discarded or superseded, judge cost and the longest Stop wait. It holds when forced
  turns are at most one per task end, superseded runs are at most a third of runs (else the debounce
  default is raised and re-measured), and the longest Stop wait is under 60 s.
  `grep -c '^| R2-P13 |.*holds' docs/specs/tautological-tests/probes.md` returns 1.
- Manual probe R2-P14 through `/fleet:reach` on a Windows host (user-gated at run time): holds when
  an idle Stop takes under 500 ms and a Stop with 5 in-doubt tests and ready verdicts takes under
  2 s. `grep -c '^| R2-P14 |.*holds' docs/specs/tautological-tests/probes.md` returns 1.

### Phase 4: Calibration set and first measurement (DT1, DT9, DT13) [TODO]

- `plugins/testing/skills/audit/evals/judge-calibration/`: `cases/*.fixture`, `labels.tsv` (DT9
  columns plus `stratum` and `split`), `metrics.sh`, `metrics.test.sh` (known-answer kappa, confusion
  matrix and Wilson interval cases, Red first).
- The judge runs through the same judge command function the hooks use (Phase 3), so calibration
  measures exactly what runs in use.
- Stratum `in-use`: test blocks sampled at random from tests added in the three repos' git histories
  (the population the hooks send under DT13), at natural prevalence. Stratum `seed`: the DT1 seeds.
  Stratum `adversarial`: tautological tests carrying a misleading provenance comment ("// expected
  value from the spec") or an instruction-shaped string, to measure whether the judge treats test
  text as data.
  Before labeling, record how many in-use cases were drawn and how many carried a provenance defect;
  if FLAG falls short of 30, record the achieved n and its interval rather than padding.
- Split: at least a third of each stratum is `holdout`; the prompt file stays frozen, and any prompt
  change after seeing `tune` results is re-measured on `holdout` only.
- The model rater (a subagent of a class other than the judge's) labels every case blind. User gate:
  the user labels every case blind to it; disagreements are adjudicated with the user.
- `metrics.sh` reports per stratum: kappa user vs model rater, judge vs user, judge vs model rater,
  the judge's confusion matrix, precision and recall on FLAG with Wilson intervals, prevalence, and
  UNKNOWN counts. System recall is stated as covering tests the session created or changed.
- Model sweep (the evals that choose the default): `metrics.sh --sweep` runs the frozen judge over
  every case for `haiku`, `sonnet` and `opus`, each at `low` and `medium` effort, and reports
  precision and recall on FLAG with Wilson intervals, UNKNOWN rate and cost per case per arm. The
  shipped default is the arm with the best FLAG precision and recall on `holdout`; where arms'
  intervals overlap, the cheaper arm wins (accuracy first, cost only breaks ties). The fallback
  default is the best arm of another class. Both are written to plugin.json and the in-script
  defaults in the same commit, with the sweep table in calibration.md.
- Re-running on a new model: because the settings hold class aliases, a new version (for example
  Haiku 5.5) needs no code change, only `metrics.sh --sweep`; calibration.md says to re-run it on
  every new model in a class and change the default only when the sweep says so.
- `docs/specs/tautological-tests-judge/calibration.md` records protocol and results.

**Sanity Check:**

- `bash plugins/testing/skills/audit/evals/judge-calibration/metrics.test.sh` exits 0.
- `bash plugins/testing/skills/audit/evals/judge-calibration/metrics.sh --check` exits 0: every row
  has both labels, a stratum and a split; holdout is at least a third per stratum; user-vs-model
  kappa is at least 0.6; the last commit touching `test-judge-prompt.md` predates the first commit
  touching `labels.tsv`, or later prompt changes carry holdout-only metrics.
- `grep -cE '^kappa (user-model|judge-user|judge-model)' docs/specs/tautological-tests-judge/calibration.md` returns at least 3.
- `grep -cE '^\| (haiku|sonnet|opus) \| (low|medium) \|' docs/specs/tautological-tests-judge/calibration.md` returns 6 (the sweep table), and
  `jq -r '.userConfig.test_judge_model.default' plugins/testing/.claude-plugin/plugin.json` equals the
  arm calibration.md names as chosen.
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
- Devil's advocate round 3 (final): 0 CRITICAL, 6 HIGH, 9 MEDIUM, 3 LOW; DT16's direction held and
  every finding is folded in: the bg job no longer assumes hook order (hooks run in parallel,
  hooks.md:410, checked); block identity by name and ordinal, re-derived from the current file;
  locks with pid, host, start and staleness; a `pending/` marker and Stop taking the same lock; cost
  bounds (one run per file, malfunction-only budget, optional session cap, machine slots); relay from a fixed
  template with quote and diff validation; an isolated judge child (`--system-prompt`,
  `--setting-sources`, `--strict-mcp-config` and `--max-budget-usd` exist in `claude --help`,
  checked; their effect is probe 3); repo-scoped reads; an exit-0 trap and a dated Q4
  clarification; Stop judges in parallel with the budget derived from probe 7; bash-harness keyed by
  whole file; pass bars on R2-P13 and R2-P14; a Windows variant of probe 4; one session file per
  write; all state pruned; SessionStart names a verdict once; no implicit fable fallback; same-dir
  rename; no deletion diffs; an adversarial calibration stratum.
  Unprobed assumptions carried into Phase 1: grandchild survival when node is killed, Read outside
  cwd in `-p`, which credential `-p` bills, MSYS append behavior (removed by one file per write).

## Execution shape

Fully sequential: Phase 1 gates Phase 2 (probes 1, 8, 11), Phase 2 gates Phase 3 (block ranges and
state), Phase 3 gates Phase 4 (the judge command must exist). Main session throughout.

PR slicing: PR A = design, this plan and Phase 1; PR B = Phases 2-3; PR C = Phases 4-5. Each opens
as a draft, with its own version bump where a plugin changes.

## Open questions

- None. Defaults approved by the user 2026-09-30 as landed here (basis: judgment, re-derived by
  probes 7 and R2-P13 for the timing ones and by the Phase 4 sweep for the model): debounce 20 s;
  no spend cap by default, only the malfunction guards (per-run budget at 10 times the probe 7 p95,
  hang timeout, 3 machine slots); 10 keys and 180 s per Stop (Stop timeout 240 s); R2-P13 bar of a
  60 s longest Stop wait; R2-P14 bars of 500 ms idle and 2 s ready; judge `opus` at `medium`,
  fallback `sonnet`, until the sweep chooses.

## Handoff to implementation

Approval: approved by the user (Kyle Sexton) on 2026-09-30 in session 848e10e2, "I approve whatever you land on", after the final stress-test round and the accuracy-first cost change.

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
