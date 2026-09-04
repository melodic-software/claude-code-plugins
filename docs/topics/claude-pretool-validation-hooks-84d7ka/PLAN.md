# PreToolUse guard remediation

## Brief

### TLDR

Act on the PreToolUse guard audit recorded in
[`FINDINGS.md`](FINDINGS.md): fix the one guard measurably misfiring, make the kill switches
save what they promise, close two visibility gaps, close the MCP coverage hole, and codify the
two conventions the interview established. One draft PR carrying six changes.

### Goal

The audit classified 17 PreToolUse guards and found that its ablation verdicts were the least
actionable part of it. The actionable findings were a guard firing four times with zero true
positives, a kill switch recovering 15 percent of a disabled hook's cost instead of 75, two
missing one-line visibility fields, and a content-guard blind spot on the GitHub MCP write
tools. This task ships those four, plus the ADR and convention that stop the next author
re-litigating the two policy questions the interview settled.

### Constraints

- **Alpha repo, single known consumer.** No deprecation shims, no compatibility aliases, no
  migration paths. Breaking changes are acceptable and expected.
- **Configurability is non-negotiable.** Every guard keeps its `*_enabled` userConfig boolean,
  read through the `CLAUDE_PLUGIN_OPTION_*` hook mirror. The operator runs this marketplace
  across several projects and at work; per-hook control is the reason the hoist matters.
- **Cross-lane files are announced before they are touched.** `plugins/*/hooks/hooks.json` is
  contended across at least three sessions, and `plugins/context-guard/hooks/hooks.json` is
  already assigned to the prompt-hooks lane. A contested file defers to a follow-up rather than
  stalling this PR.
- **`lib/hook-utils.sh` and its 17 vendored copies stay untouched.** Contended, and a possible
  split of that file is a separate question.
- Validate with `scripts/affected-tests.sh --run`, never the full suite. A changed file mapping
  to zero suites is an error, not "nothing to run".
- The PR opens as a draft and flips to ready when the work is done. The body satisfies
  `.claude/rules/pr-body-contract.md` before creation, not after.

### Acceptance criteria

1. `block_hook_bypass_scratch_roots` has a non-empty default covering the harness-designated
   scratchpad and `.work/`, and `block-hook-bypass.test.sh` carries a MUST-stay-quiet case that
   FAILS against the unmodified hook and passes after the change.
2. All 17 PreToolUse guard scripts read their `*_enabled` switch before sourcing any library,
   and `scripts/check-killswitch-hoist.sh` fails on a script that reverses that order.
3. The two `plugins/disk-hygiene/hooks/hooks.json` PreToolUse rows carry a `statusMessage`, and
   every uncontested `plugins/*/hooks/hooks.json` carries a one-line top-level `description`.
4. `secret-pattern-detection` and `hardcoded-path-check` inspect the content written by
   `mcp__github__push_files`, `mcp__github__create_or_update_file` and
   `mcp__github__delete_file`, with contract tests covering each payload shape.
5. An ADR records the A/B/C hook-packaging taxonomy, and `PLUGIN-PHILOSOPHY.md` carries a
   pointer row to it.
6. `docs/conventions/hook-input-rewriting/README.md` states the deny-or-ask posture, names
   `updatedInput` paired with `"ask"` as the sanctioned escape hatch, and gives the principle of
   least astonishment as the basis.
7. `scripts/affected-tests.sh --run` passes and selects a non-empty suite set for changes 1
   through 4.

### Captured assumptions

- **Placement follows repo precedent, not explicit instruction.** The operator said "plugin
  philosophy, or whatever the relevant document file is. Maybe that's an ADR." ADR 0019 (share
  code across plugins by vendoring) is the packaging analogue, and convention docs are owner
  docs for ongoing disciplines that point up to the philosophy. So the taxonomy is an ADR and
  the rewrite posture is a convention.
- **The `description` text for each `hooks.json` is the implementer's to draft**, one line per
  plugin, describing what that plugin's hook set does.
- **The hoist is behavior-preserving for enabled guards.** Only the disabled path changes cost.
  Any guard whose kill switch is read after a library that the switch check itself depends on is
  an exception to be surfaced, not silently reordered.
- **The A/B/C classification is settled**, per the interview: Class A is 12 plugins where hooks
  are the plugin, Class B is autonomy, context-guard and disk-hygiene where the hook is the
  feature mechanism, Class C is the 5 adjunct-to-skills candidates.

### Out of scope

- **Executing any Class C plugin split.** Filed as five agent-ready issues (source-control,
  claude-ops, instruction-placement, session-flow, context-budget). The ADR records the rule;
  the restructure is separate work and deliberately unexecuted here.
- **The ADR 0003 corpus sweep on `block-hook-bypass`.** Filed as one agent-ready issue. The
  scratch-root default narrows scope with a known root cause, which ADR 0003 treats as
  rescoping; the sweep answers the larger default-on question and needs its own evidence table.
- **The PostToolUse half of the kill-switch hoist.** Owned by the sibling session on branch
  `claude/posttool-hooks-review-ji6rl5` under a split both lanes agreed and the operator has now
  authorized.
- **Any change to `docs/conventions/hook-budget/`.** The prompt-hooks lane raised an
  unadjudicated challenge to its measurement method; that routes to issue #3685, not to this PR.
- **The remaining ablation verdicts.** Ten KEEP, three TRIM, two EVIDENCE-GATE and one DELETE
  rest on class reasoning with no firing data. `FINDINGS.md` frames them as triage, and they
  need per-guard evidence before any of them moves.

### Deferred questions

None. All five registered questions were answered; the register graded clean with
`open=0 deferred=0 blocked=0`.

## Plan

Not yet written. `/planning:plan` fills this section.
