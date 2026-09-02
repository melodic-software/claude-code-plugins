---
description: "Re-derive a performance result in a FRESH CONTEXT that does not inherit the implementer's numbers, then report the target as met or not met without rounding a miss into a win. Dispatches a verifier told to distrust the reported figures and reproduce them from the trees, checks that the change did not alter behavior via a differential covering every MODE the subject runs in, and states any behavior change separately from and above the performance claim. Use when: 'verify this speedup', 'did the optimization actually work', 'check my benchmark numbers', 'independent verification', 'is this result real', 'write up the performance result', 'double-check before I claim this'. Final phase; runs after /performance:snapshot post. Skip when no baseline exists (there is nothing to verify), or when reviewing a diff for general quality rather than checking a measured claim."
user-invocable: true
argument-hint: "[<claim or target>] (e.g. /performance:verify the 4-to-1 spawn reduction)"
disable-model-invocation: false
metadata:
  workflow-stage: verify
  summary: Re-derive the result in fresh context and report it honestly
---

## Purpose

Answers **"is this result real, and what does it actually say?"**

In the source run behind this plugin, this phase caught **two blocking correctness defects that the
implementer, the implementer's own 143-test suite, and a full green CI run had all missed.** That is
why it is a separate phase from measurement and not a step inside it.

Read [`${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md`](${CLAUDE_PLUGIN_ROOT}/reference/harness-integrity.md) first.

## 1. Fresh context, and adversarial by construction

Dispatch a verifier that **does not inherit the implementer's numbers**. Give it the trees and the
claim; withhold the reasoning that produced the figures. A verifier shown the expected answer
verifies the answer, not the work.

The brief should say, in substance: distrust the reported numbers, re-derive them yourself, and
report what you actually observe including the ways you could not reproduce it.

Two independent verifiers found different defects in the source run. One is the floor, not the
target.

## 2. Prove behavior did not change, with a differential

**A passing test suite is not a behavior proof.** It proves nothing asserted broke. It does not prove
behavior is unchanged, because it only checks what someone thought to assert.

Run a differential: the pre-change and post-change subject over a harvested corpus of real inputs,
requiring **byte-identical output**.

**Cover every MODE the subject runs in.** The source run's differential covered one of two modes and
missed a real deny -> ask downgrade in the other. Enumerate the modes first and record which the
differential actually exercised; an unexercised mode is an unverified mode, and it is reported as
such rather than assumed fine.

## 3. Check the harness before believing the result

Every gate in the harness-integrity checklist. In particular, for any discrimination
check involved, confirm it asserts that its **two arms differ**, not merely that each produced its
expected string. Four of five harnesses in the source run failed by exiting identically in both arms
and reporting a confident verdict.

## 4. Report

State the target as **met** or **not met**, with the measurement that explains why.

```text
Target:     <realistic> / <ideal>        Floor: <value>
Counter:    <before> -> <after>          [headline]
Duration:   <p50/p95 before> -> <after>  [or: REFUSED, <reason from is_measurable>]
Verdict:    MET | NOT MET | UNMEASURABLE
Behavior:   UNCHANGED (differential: N inputs, modes covered: <list>)
            | CHANGED: <what changed>    [ranked above the performance claim]
Overrides:  <any recorded gate override, or none>
Reproduced by an independent verifier: yes/no, and what diverged
```

Rules that bind the report:

- **Never round a miss into a win.** A target missed by 8% is not met.
- **A correctness regression outranks any speedup** and is stated separately, above the performance
  claim, never folded into it.
- **The counter is the headline; the duration is context.** On a host that failed
  `is_measurable()`, there is no duration line at all, only the refusal and its reason.
- **An unexercised mode is reported, not omitted.**
- **Say which claims rest on the plugin's own conventions** rather than on sourced practice: the
  p50/p95-over-20 default, the refusal threshold, and counts-over-wall-clock for anything other than
  instruction counts.

## Boundary

- **Does not measure.** `/performance:snapshot` captures; this re-derives and reports.
- **Does not review the diff for general quality.** That is the review lane. This checks one measured
  claim.
- **Does not merge.** Under any autonomy setting this plugin may open a PR and never merge one.

## Gotchas

- **A green CI run is not verification.** It was green in the source run while two blocking defects
  were live.
- **A verifier that inherits the numbers is not independent.** Withhold the reasoning, not just the
  conclusion.
- **`git checkout --` is not a restore mechanism** when the code under test is uncommitted. It
  silently reverts the fix and destroys the work. Restore from saved bytes, and verify the restore.
- **"The tests pass" answers a different question than "behavior is unchanged".** Only a differential
  over real inputs answers the second, and only for the modes it ran.
- **UNMEASURABLE is a legitimate, complete verdict.** It is not a failure of the work; reporting a
  number the host cannot support would be.
