# Design threads: tautological-tests-judge (Release 2)

Contract: the Brief in `docs/specs/tautological-tests.md` (Q1-Q13, amendments A1-A14). Research:
`.work/tautological-tests-judge/RESEARCH.md` and sidecars (gitignored, main checkout).

Status values: resolved, directional, deferred, open.

## Round 1 (user answered 2026-09-29: recommended options, sonnet as a class alias)

### DT1. Judge scope versus the calibration seeds (resolved)

Decision: the judge asks only Q7's question, where each expected value came from
(`docs/specs/tautological-tests.md:86`).

| Seed | Defect | In judge scope? | Expected verdict |
|---|---|---|---|
| S3 | hand-derived snapshot | yes | FLAG |
| G7 | stub pass-through (expected value is the stub's return) | yes | FLAG |
| T3 | platform API faked, error modes lost | no, coupling | UNKNOWN |
| M2 | internal collaborator mocked | no, coupling | UNKNOWN |
| M3 | private method tested | no, coupling | UNKNOWN |
| M6 | name says HOW not WHAT | no, naming | UNKNOWN |
| M7-side-channel | DB read instead of the interface | no, coupling | UNKNOWN |
| G10 | mocking a type you don't own | no, coupling | UNKNOWN |
| M5 | breaks on refactor | no, not in test text | UNKNOWN |
| S5 | horizontal slicing | no, not in test text | UNKNOWN |

Out-of-scope seeds stay in the calibration set; a FLAG on one scores as over-reach. Widening the
question goes through `/planning:interview`. Basis: spec:86, handoff h1.

### DT2. What "advisory" permits at Stop (resolved)

Decision: exactly one forced turn. The Stop hook returns `decision: block` with a reason telling
Claude to show the verdicts and proposed fixes and wait for approval, applying nothing. On the next
Stop (`stop_hook_active: true`) the hook allows the stop. Basis: hooks.md Stop decision control and
`stop_hook_active` (RESEARCH-hooks.md claims 4-5); Q9, A10.

### DT3. Judge model (resolved; probe 2 confirms the transcript field)

Decision: userConfig `test_judge_model`, default `sonnet`, holding a model class alias (fable, opus,
sonnet, haiku), never a versioned id, so new model versions need no change (user, 2026-09-29).
At Stop the hook reads the last assistant `"model"` from `transcript_path`; when that id contains
the configured class (a `claude-sonnet-*` session with judge `sonnet`), it uses
`test_judge_fallback_model` (default `opus`) and says so in its reason. Basis: transcript grep this
session (assistant lines carry `"model":"claude-opus-5-5"`); undocumented format, hence the probe.

Raters (Q12 amendment, handoff h8): the human, a model rater, and the judge. The model rater's class
differs from the judge's.

### DT4. Opt-in key (resolved)

Decision: boolean userConfig `test_judge_enabled`, default false, effective only when
`test_guards_enabled` is true (the judge reads state test-scan writes); its description says so.
Basis: `plugins/testing/.claude-plugin/plugin.json` userConfig; test-scan.sh:26.

### DT5. Artifact location (resolved)

Decision: work in `docs/topics/tautological-tests-judge/` on branch
`docs/tautological-tests-judge-design` (worktree `/home/kyle/worktrees/ccp-tt-judge`); graduate to
`docs/specs/tautological-tests-judge/` before merge; rewrite the spec's Release 2 sanity check
(spec:877) to the graduated path in the same PR. Basis: handoff h7, spec:877.

## Round 2 (user accepted 2026-09-29)

### DT6. Hook shape and how the judge runs (superseded by DT16; the idle-cost reasoning stands)

Stop fires at every turn end, and prompt and agent hooks have no `if` filter there, so either would
make a model call on every turn end; a prompt hook also cannot read files (RESEARCH-hooks.md).

Decision: one command hook on Stop, launched through `exec-bash.mjs --require-true` like the other
testing hooks.

1. `stop_hook_active` true: emit a `systemMessage` naming the findings file and verdict counts, so
   the user sees the judge's result unfiltered by the writing agent; exit.
2. Build the in-doubt set (DT7). Empty, or its hash already judged this session: exit 0.
3. Otherwise `decision: block`, reason: dispatch the `testing:test-judge` agent (tools Read, Grep,
   Glob; no Edit or Write) with `model: <DT3 alias>` over the listed tests, write its output to the
   findings file (DT10), show verdicts and proposed diffs, apply none.

Idle cost: one command launch per Stop, no model call.

Rejected: the hook calling `claude -p` itself. It needs CLI auth in the hook, runs inside the Stop
timeout, and loads the plugin's own Stop hook in the child (recursion guard needed; probe 3).

### DT7. "In doubt" and the calibration population (superseded by DT13 for the trigger)

Decision: a test block this session wrote or edited that, re-scanned at Stop with `--file --lines`,
still carries a finding from `rule-recomputed-expectation`, `rule-constant-restatement` or
`rule-recomputed-derived` (the rules test-scan.sh:129 already asks the writer about), or that gained
a `cant-fail-ok:` marker this session. The set is hashed per session for the step-2 dedup.

The calibration set is sampled from the same population (these rules' hits on the corpus and on the
three precision-run repos, including the `cant-fail-ok:` determinism contracts), with the DT1 seeds
added on top. Rationale: a precision number measured on seeds alone says nothing about the tests the
judge sees in use; the scanner's provenance hits are those tests, and a new suppression is where an
agent could paper over one. Basis: test-scan.sh:129; judgment.

### DT8. Session state from test-scan to Stop (directional: probe 1)

Decision: test-scan appends one line `{file, agent_id, rules, lines}` to
`$DATA/sessions/<session_id>.jsonl` per scanned write (also when it reports no finding, so a later
`cant-fail-ok:` edit is seen). The Stop hook reads it. Files older than 7 days are pruned, like
`marks/`. Stop only in v1, if probe 1 shows subagent calls carry the parent `session_id`;
SubagentStop is deferred.

Amended 2026-09-30 (probe R2-P8): `/clear` and a fork start a new `session_id` whose SessionStart
payload names no parent, while `cwd` and the transcript directory stay the same (probe logs
`p5-hooks.jsonl`); `--resume` keeps the id. State is therefore keyed by project, then session:
`$DATA/sessions/<pkey>/<session_id>/`, `$DATA/verdicts/<pkey>/<session_id>/` and
`$DATA/relayed/<pkey>/<session_id>/`, where `<pkey>` hashes the project directory
(`CLAUDE_PROJECT_DIR`, else the payload `cwd`, which follows a Bash `cd`) and the transcript
directory. On SessionStart `source` `clear` or `fork` the SessionStart hook writes a successor
marker; that session's Stop hook then treats the in-doubt blocks, verdicts and relay markers of
every other session under the same key whose last write falls within the hour before the marker as
the session's own (DT13's "the session" includes its `/clear` and fork predecessors). Sessions idle
longer stay with the SessionStart catch-up, whose one-hour rule sets the window (judgment).
`CLAUDE_PROJECT_DIR` is logged in the SessionStart, PreToolUse and Stop hook environments
(`*-hooks.jsonl`); PostToolUse is unprobed. Known limit: two live sessions in one directory, one of
which clears, can adopt the other's writes from the hour before the clear.

Confirmed 2026-09-30 (user): a `/clear` or fork successor counts as the same session for Q7,
because the common workflows continue one task across it: `/session-flow:handoff`, then `/clear`,
then the pasted resume prompt, or `/compact`. `/compact` keeps the `session_id` and transcript
(SessionStart `source` `compact`, probe R2-P8), so it needs no adoption.

### DT9. Calibration set: schema, size, bar (resolved)

Schema, one row per test: id, source (seed id, corpus fixture, repo path), language, file and test
name, in scope (yes/no), human label, model-rater label, adjudicated label, judge verdict, quoted
evidence, note.

Size: at least 30 adjudicated FLAG and 30 adjudicated PASS in scope, plus the eight out-of-scope
seeds. Basis: Tier 2 practitioner guidance of 30-50 items to start (RESEARCH-judge-validation);
30 per class is judgment.

Report: Cohen's kappa for human vs model rater, and the judge's confusion matrix, precision and
recall on FLAG, prevalence and UNKNOWN handling (RESEARCH-judge-validation, 2606.00093). Labels are
trusted at human-vs-model kappa of at least 0.6 (Tier 2 "substantial"). The judge stays advisory
(Q7); any promotion goes through `/planning:interview`.

### DT10. Proposed-fix output (resolved)

Per in-doubt test: file, test name, quoted evidence (before the verdict), verdict FLAG/PASS/UNKNOWN,
where the expected value came from, and for FLAG a proposed diff, never applied. Written in the
detector-findings shape (`docs/conventions/detector-findings/README.md`) under the destination that
contract resolves, so `review:fanout fix` and Release 3 cleanup read it.

## Round 3 (user accepted 2026-09-29)

### DT11. Pocock's implementation-coupled group (resolved)

The plugins exist to stop tautological tests, aligned with Pocock (user, 2026-09-29). Pocock
defines a tautological test as one whose expected value restates the implementation (his M8), which
is the judge's one question. Coverage of his list:

| Pocock ids | Caught by |
|---|---|
| T1, T2, M1, M4, M7-weak, M8, S2, S4 | Release 1 scanner rules |
| S3, G7 | Release 2 judge |
| T3, M2, M3, M6, M7-side-channel, M5, S5 | `testing:test-value` guidance only (SKILL.md:113) |

Decision: the coupling group stays guidance-only; the judge stays tautology-only. Rejected: widening
the judge (a Brief change through `/planning:interview`) and a coupling check in Release 3 cleanup.
Basis: Q7 (spec:86); one question is what the calibration set can measure (judgment).

### DT12. Tunable versus fixed (resolved)

Tunable: hooks on or off; test-file globs; adapters; per-rule `off`/`warn`/`error`;
`test_judge_enabled`; `test_judge_model` and `test_judge_fallback_model` (class aliases); per-test
`cant-fail-ok: <reason>`. Basis: `.claude/testing.yaml` keys (`plugins/testing/skills/setup/SKILL.md:24-37`).

Fixed: rule semantics; only deterministic rules may block (Q4); the judge never blocks (Q7) and never
applies a fix (Q9, A10); the judge's question (Q7); no coverage or mutation-score bar ships
(`code-metrics` `coverage.reference: null`, `plugins/code-metrics/reference/config.md:78`).

## Round 4 (from the plan stress-test; user accepted recommendations 2026-09-29)

### DT13. In-use reach of the judge (resolved: option a; supersedes DT7 trigger)

DT7's in-doubt set is three scanner rules plus new `cant-fail-ok:` markers. S3 (hand-derived
snapshot) scans as `rule-snapshot-only`, and G7 (stub pass-through) has no rule (spec:603), so in
real use neither reaches the judge, although DT11 says the judge catches them.

Options: (a) every test block the session created or changed is in doubt, capped per block, each
judged once; (b) add `rule-snapshot-only` and `rule-mock-only-oracle` hits to the trigger (covers S3
partly, not G7); (c) keep DT7 and restate DT11 as "judge-capable, not hook-surfaced".
Recommendation: (a). Q7's "tests still in doubt" read as "no deterministic signal cleared them";
the scanner cannot see S3 or G7, and per-test dedup bounds the cost. Basis: spec:603, spec:81-86;
judgment on the Q7 reading.

Reach, stated plainly: S3 and G7 are caught when the snapshot or stub sits inside the test block;
a stub in `beforeEach` or a snapshot in a `.snap` file is outside the block text the judge gets
(stress-test round 2, finding 6). Adapters with `block_model: file` (bash-harness) send only the
changed hunk, never the whole file.

Consequences: a test the session never created or changed is never in doubt; at most 10 tests per
forced turn, the rest wait for the next Stop; the DT9 population becomes test blocks sampled from
the three repos' histories at natural prevalence, reported as one stratum, with the DT1 seeds a
second stratum; the judge prompt is frozen before it sees a labeled case and at least a third of
cases are held out from prompt changes.

### DT14. Who writes the verdict (superseded by DT16)

The forced turn routes dispatch, model, prompt, output file and the counts through the writing agent,
which can skip or frame the judge; keys marked judged at block time make one ignored turn permanent.
Recommendation: a SubagentStop command hook matched on the judge's `agent_type` writes the findings
file from the judge's own output and records its model; only it marks keys judged; the Stop
`systemMessage` says "judge not run" when no judge-written file exists. Basis: SubagentStop input
carries `agent_type` and `agent_transcript_path` (RESEARCH-hooks.md:29); probe the handback location.

### DT15. Unattended sessions (resolved; amends DT2)

`claude -p`, `--bg` and auto-mode lanes have nobody to approve, and the block counts toward the
shared 8-block cap. Recommendation: when unattended (non-interactive or `permission_mode` auto or
bypass), block once with "dispatch the judge, apply nothing, do not wait"; the findings file is the
review surface for the PR. Basis: RESEARCH-hooks.md:29, :98-112; AGENTS.md lane launch mode.

Amended 2026-09-30 (user, after probe R2-P9 failed): `permission_mode` cannot mark an unattended
session: plain `-p` reports `default` like an attended manual session (hooks.md: Manual arrives as
`default`), and `-p --permission-mode auto` reports `auto` like an attended auto session. A
session is attended only when the hook environment has `CLAUDE_CODE_SESSION_ATTENDED=1` exactly;
any other value or its absence is unattended and gets no forced turn, only the `systemMessage` and
the findings file. The variable is undocumented, so the
rule fails safe: if it is renamed or dropped, every session falls back to the no-forced-turn path.
Probe R2-P9 pins its values and is rechecked on each Claude Code release. Basis: probe logs
`p5r-hooks.jsonl` and `p9r-hooks.jsonl` (1 in interactive default and auto sessions; 0 under `-p`,
`-p --permission-mode auto` and `--bg`).

## Round 5 (from stress-test round 2; user chose the recommended design 2026-09-30)

### DT16. Who runs the judge (resolved: second amendment, precompute early and relay at Stop; supersedes DT6 steps, DT14, and the dispatch half of DT2)

Old: the Stop hook forces a turn in which the writing agent dispatches the judge subagent; a
SubagentStop hook records the result. Stress-test round 2 found a new CRITICAL in that machinery
(an ignored turn re-blocks every Stop up to the 8-block cap) plus HIGHs: a background judge races
the next Stop; the writer still writes the judge's prompt and model; calibration measures a
different prompt than the one used. Each fix adds state (`pending/`, attempt counts, TTLs).

New: the Stop hook starts the judge itself as a detached headless `claude -p` run: fixed prompt
(the same one calibration uses), `--model <alias>`, read-only tools (`--tools Read,Grep,Glob`),
writing the findings file directly. An env marker set by the parent makes `test-judge.sh` exit at
once in the child (no recursion). The Stop hook never waits and never blocks while the judge runs.
At a later Stop, when a result file it has not yet relayed exists, it shows the counts in a
`systemMessage` and, attended only, forces one relay turn: "present verdicts and proposed diffs from
<file>, apply nothing, wait for the user". It marks the file relayed at block time, so an ignored
turn is never repeated.

Why: retires round-2 findings 1-3, 8, 9 and 12, the SubagentStop hook and probes 4, 7 and 10;
the writer never touches the judge's input or output; unattended sessions take the same path.
DT6's reasons against it: the timeout does not bind a detached child; recursion is handled by the
env marker; auth is unknown (probe). Known limit: a session that ends before the judge finishes
leaves only the findings file.

Amendment proposed 2026-09-29 (user: results "can't be lost, and they can't be disconnected"):
run the judge synchronously, not detached. The Stop hook waits for the `claude -p` judge (command
hooks allow up to 600 s; generated `timeout` about 240 s, judge bound below it), writes the findings
file first, then returns in the same Stop: attended, `decision: block` whose reason carries the
verdicts and proposed diffs verbatim ("present these, apply nothing, wait"); unattended, a
`systemMessage` plus the file. A judge failure or timeout says so in the `systemMessage`, leaves the
keys unjudged, and the next Stop retries (at most 2 attempts per key, then "judge not run for X").
A SessionStart hook names any findings file never relayed (session killed mid-judge). Cost: the
user waits at a Stop only when new tests are in doubt; idle Stops make no model call.

Second amendment proposed 2026-09-30 (user asked for concurrency without lost results; research
`.work/tautological-tests-judge-concurrency/RESEARCH.md`): precompute early, relay at Stop.

1. PostToolUse, `async: true` (no rewake): after test-scan records a created or changed test, a
   background judge job waits a short debounce (default 20 s), re-reads the file, and exits if the
   test's block sha changed (a newer write owns it). Otherwise it takes a per-key lock
   (noclobber marker), runs the fixed-prompt `claude -p` judge, and writes the verdict to a durable
   ledger `$DATA/verdicts/<session_id>/<key>.json` before exiting 0. It never speaks to the session,
   so mid-task work is not interrupted (Q7: once at task end).
2. Stop (synchronous, cheap): in-doubt keys with a ledger verdict are ready; keys whose job is still
   running are waited on, bounded; keys with no job (killed by `-p` teardown, crashed, or written by a
   path the async hook missed) are judged synchronously now. Then relay as before: attended,
   `decision: block` carrying the verdicts verbatim, once per verdict set; unattended,
   `systemMessage` plus the findings file.
3. SessionStart: names any ledger verdict never relayed (session ended mid-task).

Why: the judge mostly runs while Claude keeps working, so the Stop wait shrinks to stragglers;
every verdict is on disk before anything reads it, and the synchronous Stop path is the fallback for
every async loss mode the research found (`-p` kills in-flight async hooks at teardown; an
`asyncRewake` hook killed at its timeout gives no wake, measured on 2.1.278/2.1.281; a failed
`asyncRewake` launch loops, #96148). `asyncRewake` is not used: it is reported synchronous in `-p`
and Desktop (#89960, reproduced 2.1.284), and a mid-task wake contradicts Q7's task-end timing.
Cost risk: judging a test that is rewritten after the debounce; measured by a probe.

Basis: `claude --help` this session (`--model`, `--tools`, `--allowed-tools`, `--permission-mode`,
`--bare` skips hooks but also keychain reads, so it is not used); round-2 report findings 1-3.
Gating probes: env-marker recursion guard; model alias honored; `--tools` restriction in `-p`;
detached child survives hook exit on Linux and Windows Git Bash; child has credentials from hook
context; tokens per run.

Amended 2026-09-30 (user, after probe R2-P3 failed): the judge command adds
`--disable-slash-commands`, because without it the child still lists 18 bundled skills (probe logs
`p3-main.jsonl`, `p3-noskills.jsonl`; cli-reference: "Disable all skills and commands for this
session"). The child inherits the parent's environment unchanged: the parent's OAuth subscription
login is the expected case, and when `ANTHROPIC_API_KEY` is set the judge bills that key, since in
`-p` "the key is always used when present" (env-vars docs, fetched 2026-09-30). A bad key is caught
by the hang timeout, not special-cased.

## Probes for the plan's first phase

1. Subagent tool calls carry the parent `session_id`.
2. Transcript assistant lines carry `model` on the installed version.
3. A child `claude -p` started from a hook loads the plugin's Stop hook (confirms the DT6 rejection).
4. The Agent tool's `model` argument overrides a plugin agent's frontmatter.
5. `systemMessage` from a Stop command hook reaches the user.
6. `decision: block`, then `stop_hook_active: true` on the following Stop.

## Deferred

- Bash and MCP writes (bashEditDiff, beta). Research tag: measure bashEditDiff coverage under the
  default permission mode on 2.1.284+. The spec risk table already records the gap.
- SubagentStop judging. Research tag: probe 1 result.
