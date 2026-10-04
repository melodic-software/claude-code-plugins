---
description: "Re-anchor: deterministic sub-work (counts, diffs, transforms, arithmetic) gets a script; reason over its output. Use when: 'script the deterministic work', 'you should have scripted that', 'don't eyeball that', 'you counted that by hand', 'compute that, don't estimate', 'diff it with a tool', 'stop hand-tallying', 'run it instead of guessing', or at conversation start on count-, diff-, transform-heavy work. Fires on drift, not a work order ('script it', 'diff these files', 'count the routes'). Mode lever-check plus a block summary: answers build-a-lever or edit-by-hand for one change repeated across sites."
argument-hint: "[lever-check <block summary>]"
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: situational  # only when count/diff/transform work is in play
  discipline-batch-rank: 90
  workflow-stage: anytime
  summary: Script counting, diffing, and transforms instead of eyeballing them
---

# Script the deterministic work

A drift corrector for the discipline of offloading deterministic sub-work to
a script instead of performing it in your head. The method, re-anchor, audit
the work in flight, correct forward, report, and the tone that firing this is
not an accusation, lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to scripting deterministic work.

## The discipline this re-anchors

When a sub-task is purely deterministic. Its answer follows mechanically
from its input with no judgment in the middle. Write a script (or invoke a
tool) that produces the answer, run it, read the output, and reason only
**after**, over that output. Counting, diffing, sorting, transforming,
matching, sweeping across files, and arithmetic are the recurring shapes. The
model is a poor calculator and a worse line-counter; a hand-tallied count or
an eyeballed diff carries a silent error the script would not.

The boundary of *what* to script is not "anything tedious". It is set by
which enforcement tier the sub-work belongs to.

### The tier vocabulary, a standards convention owns this

The source of truth for the tier distinction is the consuming organization's
enforceability-tiers convention, which classifies work by who can decide it.
Resolve it per the method doc's ladder, the consumer's own instruction layer
first, then that standards convention, then the portable baseline below. And
re-anchor the distinction rather than restating the doc's criteria:

- **Deterministic**, the answer is pass/fail, exact, or countable with no
  judgment. **Script it, run it, reason over the output.** This is the core
  of the discipline.
- **Detect-then-judge**, a mechanical pass narrows the candidates, but the
  verdict needs meaning or context. **Script only the detect half**; the
  judgment stays with the model. A script's flag is a candidate, never the
  ruling.
- **Reasoning-only**. Meaning, intent, fit, abstraction quality. **Never
  script it.** A script here manufactures false confidence. It dresses a
  judgment call as a computed fact.

When the consuming project declares no such convention, re-anchor that same
three-tier shape as the portable baseline: script the deterministic, script
only the detection of the detect-then-judge, and leave the reasoning-only to
reasoning.

### The in-task application. No standards doc yet (flagged gap)

The enforceability-tiers convention classifies *conventions* by tier and
routes a *recurring* finding to the mechanism its tier permits; it does not
speak to the in-task move this skill re-anchors. "this task needs a count or
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
scaffold, the model's output belongs in the slots that need judgment, not in
re-typing the frame each time. Prefer a native mechanism where one exists: a
repo's pull-request or issue templates, for instance, already emit the
scaffold with no generation cost. Same rule as the analysis side. Reserve
model output for judgment; the structure is deterministic.

## Audit. What to look for

Name concrete, located findings (per the method doc's step 2, self-audit):

- a count, total, or tally produced by reading and adding in prose rather
  than by a command whose output was read back;
- two files, lists, or versions compared by eye where a diff or a set
  operation would be exact;
- a sort, dedupe, filter, or reformat performed inline in the answer instead
  of by a tool, so the result cannot be reproduced or trusted;
- a sweep, "every file that matches", "all call sites of X", asserted from
  memory of what was read rather than from a search that enumerated them;
- arithmetic or a mechanical transform worked through by hand mid-answer;
- a deterministic scaffold, a PR body, an issue, a report, config
  boilerplate. Hand-typed frame and all, where a script or a native template
  would emit the structure and leave only the judgment slots to fill;
- **the reverse over-reach**, an existing script or tool that *decides a
  judgment call*: a detect-then-judge script's flag consumed as the verdict,
  or reasoning-only work (meaning, intent, fit, abstraction quality) handed to
  a script, so a judgment is dressed as a computed fact. This is the same
  boundary crossed in the other direction; the audit hunts both ways, not just
  hand-work that should have been scripted.
- one change applied by hand at many sites where a lever was the cheaper and
  checkable route, or a lever run across every site with no hand-edited site
  to compare it against (the Lever check below sets the rule).

Correct each forward now: write and run the script or tool, read its real
output, and re-derive the conclusion from that output. Do not keep the
hand-computed figure alongside it. Where the sub-work is detect-then-judge,
script the detection and keep the verdict; where it is reasoning-only, leave
it un-scripted and say why. Where an **existing** script already over-reaches
into judgment, correct in the other direction. **de-script it**: demote a
detect-then-judge flag back to a candidate the model rules on, and return
reasoning-only work to reasoning rather than letting the script's output stand
as the answer.

## Distinct from standing automation

The enforceability-tiers convention's own routing sends a **recurring**
deterministic finding to a **standing** mechanism, a linter, analyzer, or
commit hook that fires on every change. That is the territory of an
automation-gaps capability (`/harness-config:audit-automation-gaps` when that
plugin is installed; prose guidance otherwise): institutionalize the check
so it never reaches review again.

This skill owns the complementary case: the **one-off, session-time** need.
The current task needs a count, a diff, or a transform right now; the answer
is to make a script *now*, often throwaway, feed it the input, and reason
over its output. Recurring → a standing hook; one-off in flight → script it
this turn.

## Lever check (`lever-check <block summary>`)

`$ARGUMENTS` whose first word is `lever-check` selects this mode; any other
text runs the corrector above, with the text read as the request. The mode
answers one question for a block of work that applies one change at several
sites: build a lever (a script or tool that makes the change at every site),
or edit each site by hand. `/implementation:implement` calls it before a
block that applies one change at three or more sites, and
`/implementation:implement-dispatch` calls it before it fans one change out
to workers. The block summary names the change, the sites, and how many
there are.

1. **Resolve `lever_scope`**, once per call, lowest layer first: the default
   `deterministic`; the user's option, `${user_config.lever_scope}` (empty or
   a literal, unexpanded placeholder means unset); and the `lever_scope` key
   of the repository's `docs/conventions/discipline.yaml`, which wins when
   set, read only under the root rule in
   [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md).
   A value other than `deterministic` or `non-trivial` is named with its file
   or option, the key and the value, and that layer is dropped: a valid
   repository value still wins over an invalid user value, and an invalid
   repository value resolves `deterministic`, never the user's value. An
   invalid value never stops the check. Report one line, for example
   `lever_scope: non-trivial (docs/conventions/discipline.yaml)`.
2. **Classify the change.** It is mechanical when the edit at each site
   follows from that site's text alone, with no reading of the surrounding
   intent: a rename, a fixed rewrite of a call shape, a moved import path, a
   format conversion. It needs judgment when two sites with the same text
   could need different edits.
3. **Answer `build-a-lever` or `edit-by-hand`, with the reason.**
   - Under `deterministic`: `build-a-lever` for a mechanical change; a
     throwaway script is enough. `edit-by-hand` for a change that needs
     judgment, naming the kind of site that needs it.
   - Under `non-trivial`: a mechanical change gets the same answer as under
     `deterministic`. A change that needs judgment also gets
     `build-a-lever`, unless it is a few one-line edits that cost less to
     make than a tool would cost to set up. For it the lever is an
     established codemod or refactoring tool for the language (a
     language-server rename, a structural search-and-replace tool, the
     ecosystem's codemod runner), never a refactoring script written from
     scratch for this change. When no such tool covers the change, answer
     `edit-by-hand` and say that no tool fit.
4. **Pilot before the rest.** With `build-a-lever`, under either value, the
   caller edits the first site by hand, runs the lever on a clean copy of
   that site, and diffs the two results. A difference means the lever is
   wrong: fix it and diff again before it touches any other site.
5. **One pass or a fan-out.** When the caller is about to fan the change out
   to workers, also answer `one-pass: yes` or `one-pass: no`. `yes` means a
   single run of the lever covers every unit, so the caller dispatches one
   worker that builds, pilots and runs the lever over all of them instead of
   one worker per unit editing by hand. `no` names the units the lever cannot
   reach.

Report the result as these lines, then return to the caller:

```text
lever_scope: <value> (<layer>)
answer: build-a-lever | edit-by-hand
reason: <one sentence>
one-pass: yes | no   (fan-out calls only)
```

The mode answers and stops. It writes no lever and edits no file; the caller
does the work under its own cadence.

## What this skill does NOT do

- **Does not script a judgment call.** Scripting reasoning-only work, or
  treating a detect-then-judge script's flag as the verdict, is
  over-application. It converts a judgment into a false computed fact. The
  tiers set the boundary; honor it in both directions.
- **Does not demand a permanent tool for a one-off.** A short throwaway
  script that runs and returns real output satisfies the discipline; building
  standing automation is the other capability's job.
- **Does not fabricate a finding.** Work whose deterministic parts were
  already scripted audits clean; say so rather than inventing hand-work to
  correct.

## Next

- A lever-check answer goes back to its caller: /implementation:implement
- A deterministic check that recurs needs a standing hook: /harness-config:audit-automation-gaps

## Gotchas

- "Reason after over results" here means *where the computation happens*. Let
  the tool compute, then reason over what it returned. It is a different sense
  of "reason" from `/discipline:reason-dont-recite`, which is about
  interrogating inherited content. Same word, unrelated axis.
- The subtle miss is the detect-then-judge trap: a script that flags
  candidates is doing the deterministic half correctly, but its output is a
  shortlist for judgment, not the answer. Reading the flag as the ruling
  re-hides the judgment the tier split exists to protect.
- A script that was never actually run is worse than hand-work: it looks
  rigorous while its output is imagined. The discipline is script **and run**
Reason over real output, not over what the script would presumably print.
