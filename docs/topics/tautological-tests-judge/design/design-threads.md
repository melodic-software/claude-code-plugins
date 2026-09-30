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

### DT6. Hook shape and how the judge runs (directional: probes 3-6)

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

### DT7. "In doubt" and the calibration population (resolved)

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
