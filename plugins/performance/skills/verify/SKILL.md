---
description: "Re-derive a performance result in a FRESH CONTEXT that does not inherit the implementer's numbers, then report the target as met or not met without rounding a miss into a win. Dispatches a verifier told to distrust the reported figures and reproduce them from the trees, checks that the change did not alter behavior via a differential covering every MODE the subject runs in, and states any behavior change separately from and above the performance claim. Use when: independently re-deriving a measured performance claim before it is stated, or writing up the result: 'verify this speedup', 'is this result real', 'independent verification', 'write up the performance result'. Final phase; runs after /performance:snapshot post. Skip when no baseline exists (there is nothing to verify), or when reviewing a diff for general quality rather than checking a measured claim."
user-invocable: true
argument-hint: "[<claim or target>] (e.g. /performance:verify the 4-to-1 spawn reduction)"
disable-model-invocation: false
metadata:
  workflow-stage: verify
  summary: Re-derive the result in fresh context and report it honestly
---

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

Two independent verifiers routinely find different defects, so one verifier is the floor, not the
target.

## 2. Prove behavior did not change, with a differential

**A passing test suite is not a behavior proof.** It proves nothing asserted broke. It does not prove
behavior is unchanged, because it only checks what someone thought to assert.

Run a differential: the pre-change and post-change subject over a harvested corpus of real inputs,
requiring **byte-identical output**.

**Cover every MODE the subject runs in.** A differential that covers one of two modes misses a real
deny -> ask downgrade in the other and still reports byte-identical output. Enumerate the modes first
and record which the differential actually exercised; an unexercised mode is an unverified mode, and
it is reported as such rather than assumed fine.

## 3. Check the harness before believing the result

Every gate in the harness-integrity checklist. In particular, for any discrimination
check involved, confirm it asserts that its **two arms differ**, not merely that each produced its
expected string. A harness that exits identically in both arms and still reports a confident verdict
never exercised the subject.

## 4. Report

State the target as **met** or **not met**, with the measurement that explains why.

```text
Target:      <realistic> / <ideal>        Floor: <value>
Counter:     <before> -> <after>          [headline] [unproven, when Correlation is]
Correlation: <evidence, repeated from the goal> | unproven
Duration:    <p50/p95 before> -> <after>  [or: REFUSED, <reason from is_measurable>]
Rig:         <hardware>, <runtime mode>, <throttling>, <run count>, <timestamp>
Verdict:     MET | NOT MET | UNMEASURABLE
Behavior:    UNCHANGED (differential: N inputs, modes covered: <list>)
             | CHANGED: <what changed>    [ranked above the performance claim]
Cost:        <diff size, new moving parts>   [optional; beside the gain]
Not covered: <percentiles, inputs, paths, and modes not exercised>
Overrides:   <any recorded gate override, or none>
Reproduced by an independent verifier: yes/no, and what diverged
```

Rules that bind the report:

- **IF `Correlation:` is `unproven`, THEN the `Counter:` line shows `unproven` beside the
  headline.** An unproven counter win is a counter win, not a user-perceived one.
- **Any aggregate over several targets reports the speedup as a geometric mean** of the per-target
  ratios, with each target's row shown beside it. An arithmetic mean of ratios changes with which
  arm is the reference; a geometric mean does not. See
  [write the result up](../../reference/techniques.md#j-write-the-result-up).
- **`Not covered:` is never omitted.** Write `none` only when nothing was left unexercised.
- **`Cost:` sits beside the gain it buys.** Whether a large diff is worth a small win is the
  human's call; the report makes the trade visible.
- **Never round a miss into a win.** A target missed by 8% is not met.
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
