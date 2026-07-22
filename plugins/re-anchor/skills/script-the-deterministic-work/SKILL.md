---
name: script-the-deterministic-work
description: "Re-anchor the discipline that purely deterministic sub-work — counting, diffing, sorting, transforming, matching, sweeping, arithmetic — gets a script that runs and returns real output, and the model reasons only afterward over that output — then audit the work in flight for transforms executed by hand and re-derive them from a script's result. Use when: 'script the deterministic work', 'you should have scripted that', 'don't eyeball that', 'you counted that by hand', 'compute that, don't estimate', 'diff it with a tool', 'stop hand-tallying', 'run it instead of guessing', or at conversation start on count-, diff-, or transform-heavy work. Not for authoring a requested script or migration ('script it' as a work order is script-writing, not this corrector), and not for a first-turn count/diff/transform work order ('diff these files', 'count the routes', 'convert all of these') — doing that task with a tool is just doing the task; this corrector fires on drift, mid-flight or retrospective, or as posture at the start of transform-heavy work."
user-invocable: true
disable-model-invocation: false
metadata:
  re-anchor-batch: situational  # only when count/diff/transform work is in play
  re-anchor-batch-rank: 90
---

# Script the deterministic work

A drift corrector for the discipline of offloading deterministic sub-work to
a script instead of performing it in your head. The method — re-anchor, audit
the work in flight, correct forward, report, and the tone that firing this is
not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to scripting deterministic work.

## The discipline this re-anchors

When a sub-task is purely deterministic — its answer follows mechanically
from its input with no judgement in the middle — write a script (or invoke a
tool) that produces the answer, run it, read the output, and reason only
**after**, over that output. Counting, diffing, sorting, transforming,
matching, sweeping across files, and arithmetic are the recurring shapes. The
model is a poor calculator and a worse line-counter; a hand-tallied count or
an eyeballed diff carries a silent error the script would not.

The boundary of *what* to script is not "anything tedious" — it is set by
which enforcement tier the sub-work belongs to.

### The tier vocabulary — a standards convention owns this

The source of truth for the tier distinction is the consuming organization's
enforceability-tiers convention, which classifies work by who can decide it.
Resolve it per the method doc's ladder — the consumer's own instruction layer
first, then that standards convention, then the portable baseline below — and
re-anchor the distinction rather than restating the doc's criteria:

- **Deterministic** — the answer is pass/fail, exact, or countable with no
  judgement. **Script it, run it, reason over the output.** This is the core
  of the discipline.
- **Detect-then-judge** — a mechanical pass narrows the candidates, but the
  verdict needs meaning or context. **Script only the detect half**; the
  judgement stays with the model. A script's flag is a candidate, never the
  ruling.
- **Reasoning-only** — meaning, intent, fit, abstraction quality. **Never
  script it.** A script here manufactures false confidence — it dresses a
  judgement call as a computed fact.

When the consuming project declares no such convention, re-anchor that same
three-tier shape as the portable baseline: script the deterministic, script
only the detection of the detect-then-judge, and leave the reasoning-only to
reasoning.

### The in-task application — no standards doc yet (flagged gap)

The enforceability-tiers convention classifies *conventions* by tier and
routes a *recurring* finding to the mechanism its tier permits; it does not
speak to the in-task move this skill re-anchors — "this task needs a count or
a diff **now**, so script it now." That application has **no dedicated
standards convention** to cite. When the consuming project's standards source
declares one, route through it; when it does not, treat that as a flagged gap
(a candidate upstream standards addition), not license to invent a rubric
here beyond the portable baseline above.

### Generation, not just analysis

The discipline runs in both directions. Analysis feeds input to a script and
reasons over its output; generation emits deterministic *structure* from a
script or template and fills only the judgment slots by hand. A PR body, an
issue body, a report, a skill skeleton, or config boilerplate is mostly fixed
scaffold — the model's output belongs in the slots that need judgment, not in
re-typing the frame each time. Prefer a native mechanism where one exists: a
repo's pull-request or issue templates, for instance, already emit the
scaffold with no generation cost. Same rule as the analysis side — reserve
model output for judgment; the structure is deterministic.

## Audit — what to look for

Name concrete, located findings (per the method doc's step 2):

- a count, total, or tally produced by reading and adding in prose rather
  than by a command whose output was read back;
- two files, lists, or versions compared by eye where a diff or a set
  operation would be exact;
- a sort, dedupe, filter, or reformat performed inline in the answer instead
  of by a tool, so the result cannot be reproduced or trusted;
- a sweep — "every file that matches", "all call sites of X" — asserted from
  memory of what was read rather than from a search that enumerated them;
- arithmetic or a mechanical transform worked through by hand mid-answer;
- a deterministic scaffold — a PR body, an issue, a report, config
  boilerplate — hand-typed frame and all, where a script or a native template
  would emit the structure and leave only the judgment slots to fill;
- **the reverse over-reach** — an existing script or tool that *decides a
  judgement call*: a detect-then-judge script's flag consumed as the verdict,
  or reasoning-only work (meaning, intent, fit, abstraction quality) handed to
  a script — so a judgement is dressed as a computed fact. This is the same
  boundary crossed in the other direction; the audit hunts both ways, not just
  hand-work that should have been scripted.

Correct each forward now: write and run the script or tool, read its real
output, and re-derive the conclusion from that output — do not keep the
hand-computed figure alongside it. Where the sub-work is detect-then-judge,
script the detection and keep the verdict; where it is reasoning-only, leave
it un-scripted and say why. Where an **existing** script already over-reaches
into judgement, correct in the other direction — **de-script it**: demote a
detect-then-judge flag back to a candidate the model rules on, and return
reasoning-only work to reasoning rather than letting the script's output stand
as the answer.

## Distinct from standing automation

The enforceability-tiers convention's own routing sends a **recurring**
deterministic finding to a **standing** mechanism — a linter, analyzer, or
commit hook that fires on every change. That is the territory of an
automation-gaps capability (`/claude-config:audit-automation-gaps` when that
plugin is installed; prose guidance otherwise): institutionalize the check
so it never reaches review again.

This skill owns the complementary case: the **one-off, session-time** need.
The current task needs a count, a diff, or a transform right now; the answer
is to make a script *now* — often throwaway — feed it the input, and reason
over its output. Recurring → a standing hook; one-off in flight → script it
this turn.

## What this skill does NOT do

- **Does not script a judgement call.** Scripting reasoning-only work, or
  treating a detect-then-judge script's flag as the verdict, is
  over-application — it converts a judgement into a false computed fact. The
  tiers set the boundary; honour it in both directions.
- **Does not demand a permanent tool for a one-off.** A short throwaway
  script that runs and returns real output satisfies the discipline; building
  standing automation is the other capability's job.
- **Does not fabricate a finding.** Work whose deterministic parts were
  already scripted audits clean; say so rather than inventing hand-work to
  correct.

## Gotchas

- "Reason after over results" here means *where the computation happens* — let
  the tool compute, then reason over what it returned. It is a different sense
  of "reason" from `/re-anchor:reason-dont-recite`, which is about
  interrogating inherited content. Same word, unrelated axis.
- The subtle miss is the detect-then-judge trap: a script that flags
  candidates is doing the deterministic half correctly, but its output is a
  shortlist for judgement, not the answer. Reading the flag as the ruling
  re-hides the judgement the tier split exists to protect.
- A script that was never actually run is worse than hand-work: it looks
  rigorous while its output is imagined. The discipline is script **and run**
  — reason over real output, not over what the script would presumably print.
