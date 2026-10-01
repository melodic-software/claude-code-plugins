---
description: "Re-derive a performance result in a fresh context that does not inherit the implementer's numbers, then report the target as met or not met without rounding a miss into a win. Use when: 'verify this speedup', 'is this result real', 'independent verification', 'write up the performance result'. Final phase after /performance:snapshot post. Skip when no baseline exists, or when reviewing a diff for general quality rather than a measured claim."
user-invocable: true
argument-hint: "[<claim or target>]"
disable-model-invocation: false
metadata:
  workflow-stage: verify
  summary: Re-derive the result in fresh context and report it honestly
---

**Arguments.** `[<claim or target>]`. e.g. /performance:verify the 4-to-1 spawn reduction

## Purpose

Answers **"is this result real, and what does it actually say?"**

This phase is where **blocking correctness defects that the implementer, the implementer's own test
suite, and a full green CI run all missed** get caught. That is why it is a separate phase from
measurement and not a step inside it.

Read [`${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md`](${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md) first.

## 1. Fresh context, and adversarial by construction

Dispatch a verifier that **does not inherit the implementer's numbers**. Give it the trees and the
claim; withhold the reasoning that produced the figures. A verifier shown the expected answer
verifies the answer, not the work.

The brief should say, in substance: distrust the reported numbers, re-derive them yourself, and
report what you actually observe including the ways you could not reproduce it.

The brief also sets a turn budget, a limit the verifier keeps for itself: 30 turns, stop gathering and
re-measuring by turn 22, and spend the remaining turns writing the report. Run the highest-value
checks first: re-derive the headline number and the differential before any secondary check. A
report that ends short names what it did not reach under `Not covered:`. A verification that ran out
of turns is not complete, so anything unreached stays NOT MET or unverified.

Two independent verifiers routinely find different defects, so one verifier is the floor, not the
target.

## 2. Prove behavior did not change, with a differential

**A passing test suite is not a behavior proof.** It proves nothing asserted broke. It does not prove
behavior is unchanged, because it only checks what someone thought to assert.

Run a differential: the pre-change and post-change subject over a harvested corpus of real inputs,
requiring **byte-identical output**. Use the bundled one rather than writing one:
`python3 "${CLAUDE_PLUGIN_ROOT}/scripts/differential.py" --baseline <path> --candidate <path>
--config <json>`. Its config takes a `matrix` of modes, and it refuses a run where neither arm ever
produced output. Run it from the Bash tool, whose shell resolves `python3` (`type -P python3` names
the one it found); a bare name inside another process's `subprocess` call searches a different
`PATH` (harness-integrity rule 6). The module docstring documents the config.

**Cover every MODE the subject runs in.** A differential that covers one of two modes misses a real
deny -> ask downgrade in the other and still reports byte-identical output. Enumerate the modes first
and record which the differential actually exercised; an unexercised mode is an unverified mode, and
it is reported as such rather than assumed fine.

## 3. Record whether the measured build is the deployed build

The verdict is a statement about the measurement. Whether the measured build is the one the user
runs is a separate disposition, the `Deployed:` line. The flow measures a worktree before merge, so
a difference at this point is expected and cannot be resolved before the PR: record it, never report
the change as done, and do not change the verdict for it.

This applies to a subject that runs from an installed copy, such as a Claude Code plugin. A subject
with no install record gets `Deployed: n/a (no install record for this subject)` and the report
proceeds, so a target-agnostic run is not blocked.

1. Record **what was measured**: plugin or component version (from the tree or worktree path the
   harness used), and whether a worktree override, `--plugin-dir`, or project-scope install path
   was in play.
2. Record **what is deployed** where the user actually runs: read `installed_plugins.json` under
   the plugins root (`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins`, or `CLAUDE_CODE_PLUGIN_CACHE_DIR`
   when set) and quote the `version` and `installPath` of the record for the plugin under test.
   Choose the record whose `scope` the subject runs under; for a project-scope record also require
   its `projectPath` to equal the subject project's root, since one plugin can hold project records
   for several repositories, and fall back to the user-scope record when none matches. A plugin
   loaded only through `--plugin-dir` has no record.
3. **Set the disposition.** Versions agree: `Deployed: same as measured`. Versions differ:
   `Deployed: differs: <installed version/path>, re-measure after install`, plus an `Open
   follow-up:` line (install the measured build, then `/performance:snapshot post` and
   `/performance:verify` again). With an open follow-up the report says the change is measured,
   never that it is done, shipped, or live.

Claim: Claude Code records each plugin install in `<plugins root>/installed_plugins.json` with its
`scope`, `installPath`, and `version`; user scope is under `~/.claude`, and a project-scope install
is a separate record in the same file carrying a `projectPath`. Basis: the plugin loading reference,
<https://code.claude.com/docs/en/plugins/loading> ("Check which stage a plugin reached" and "Find
plugins on disk"), documents the file, those three fields, and the `CLAUDE_CODE_PLUGIN_CACHE_DIR`
root; the `projectPath` field and one record per scope are observed in a local
`installed_plugins.json`, not documented there. As-of: 2026-09-29. Recheck: when that page changes
what the file records, or a Claude Code release changes its layout.

## 4. Check the harness before believing the result

Every gate in the harness-integrity checklist. In particular, for any discrimination
check involved, confirm it asserts that its **two arms differ**, not merely that each produced its
expected string. A harness that exits identically in both arms and still reports a confident verdict
never exercised the subject. `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/discriminate.py" --config <json>`
runs such a check with all three assertions, restores from a sidecar copy, and exits 2 rather than 1
when the harness never ran; prefer it to a hand-built pair of arms.

## 5. Report

State the target as **met** or **not met**, with the measurement that explains why.

```text
Target:      <realistic> / <ideal>        Floor: <value>
Counter:     <before> -> <after>          [headline] [unproven, when Correlation is]
Correlation: <evidence, repeated from the goal> | unproven
Scaling:     <growing input, per-size result, bound, demonstrated at every size: yes | no> | n/a
Event:       <event-level metric, result vs event target> | n/a
Unit:        <unit metric, result vs unit target> | n/a
Measured:    <version/path harness used>
Deployed:    same as measured
             | differs: <installed version/path>, re-measure after install
             | n/a (no install record for this subject)
Duration:    <p50/p95 before> -> <after>  [or: REFUSED, <reason from is_measurable>]
Rig:         <hardware>, <runtime mode>, <throttling>, <run count>, <timestamp>
Verdict:     MET | NOT MET | UNMEASURABLE
Behavior:    UNCHANGED (differential: N inputs, modes covered: <list>)
             | CHANGED: <what changed>    [ranked above the performance claim]
Cost:        <diff size, new moving parts>   [optional; beside the gain]
Not covered: <percentiles, inputs, paths, modes not exercised>
Overrides:   <any recorded gate override, or none>
Open follow-up: <only when Deployed differs: install, then /performance:snapshot post and /performance:verify>
Reproduced by an independent verifier: yes/no, and what diverged
```

Rules that bind the report:

- **IF `Correlation:` is `unproven`, THEN the `Counter:` line shows `unproven` beside the
  headline.** An unproven counter win is a counter win, not a user-perceived one.
- **`Scaling:`, `Event:`, and `Unit:` repeat the goal's lines of the same name, `n/a` where the
  goal says `n/a`.** A `Scaling:` bound not demonstrated at every size the goal recorded is not
  `MET`, however well the largest or smallest size did. A goal with an `Event:` target is not `MET`
  on the `Unit:` target alone: an unmeasured event target gives `NOT MET` and is named under
  `Not covered:`. The event-level result is reported even when the unit result is good.
- **The goal's `Boundary:`, `Path:`, and `Done when:` lines have no report line.** The verifier
  re-derives against them and reports the outcome in `Verdict:`, `Not covered:`, and the snapshot's
  `Path (<arm>):` lines: an arm flagged `unobserved` or mismatched there is listed under
  `Not covered:`.
- **Any aggregate over several targets reports the speedup as a geometric mean** of the per-target
  ratios, with each target's row shown beside it. An arithmetic mean of ratios changes with which
  arm is the reference; a geometric mean does not. See
  [write the result up](../../reference/techniques.md#j-write-the-result-up).
- **`Not covered:` is never omitted.** Write `none` only when nothing was left unexercised.
- **`Cost:` sits beside the gain it buys.** Whether a large diff is worth a small win is the
  human's call; the report makes the trade visible.
- **Never round a miss into a win.** A target missed by 8% is not met.
- **`Deployed:` is required and never changes the verdict.** `MET`, `NOT MET`, and `UNMEASURABLE`
  describe the measurement. When `Deployed:` differs, the report carries the `Open follow-up:` line
  and no done, shipped, or live language until a post-install re-measurement agrees. A worktree-only
  win with an older install still live is reported as measured, not live.
- **A correctness regression outranks any speedup** and is stated separately, above the performance
  claim, never folded into it.
- **The counter is the headline; the duration is context.** On a host that failed
  `is_measurable()`, there is no duration line at all, only the refusal and its reason.
- **An unexercised mode is reported under `Not covered:`, not omitted.**
- **Say which claims rest on the plugin's own conventions** rather than on sourced practice: the
  p50/p95-over-20 default, the refusal threshold, and counts-over-wall-clock for anything other than
  instruction counts.

## Boundary

- **Does not measure.** `/performance:snapshot` captures; this re-derives and reports.
- **Does not review the diff for general quality.** That is the review lane. This checks one measured
  claim.
- **Does not merge.** Under any autonomy setting this plugin may open a PR and never merge one.

## Next

- Target met on a drift-immune counter, to lock the win in: `/performance:protect`, which then
  hands off to `/source-control:pull-request`.
- Target met on a duration only: `/source-control:pull-request`.
- Target met with a large realistic-to-ideal gap (re-scan), or not met with another candidate due:
  `/performance:target`.
- Behavior changed: `/debugging:debug`.

## Gotchas

- **A green CI run is not verification.** CI stays green while blocking defects are live, because it
  only checks what someone thought to assert.
- **A verifier that inherits the numbers is not independent.** Withhold the reasoning, not just the
  conclusion.
- **`git checkout --` is not a restore mechanism** when the code under test is uncommitted. It
  silently reverts the fix and destroys the work. Restore from saved bytes, and verify the restore.
- **"The tests pass" answers a different question than "behavior is unchanged".** Only a differential
  over real inputs answers the second, and only for the modes it ran.
- **UNMEASURABLE is a legitimate, complete verdict.** It is not a failure of the work; reporting a
  number the host cannot support would be.
