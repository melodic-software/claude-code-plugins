# The re-anchor / audit / correct-forward loop

Shared by every skill in this plugin. Each corrector re-anchors one
standing discipline, applies it to the current conversation, and corrects
what has drifted. This file owns the common method; each skill's `SKILL.md`
adds only its own delta: which discipline, where that discipline's source
of truth lives, and any skill-specific action.

## What a corrector is (and is not)

An always-on rule loses salience over a long session: the instruction is
still in context near the top, but the recent turns stopped being governed
by it. A corrector re-injects the discipline near the context tail, where
it regains the pull the standing rule has lost, and forces an active
audit-and-correct pass instead of a passive reminder.

Firing a corrector is **not an accusation of violation**. It means
"re-anchor this discipline, apply it here, and check." Reaching for one as
a gentle reminder, before the work or just to set posture, is a
first-class use, not a lesser one. The audit may return clean; a truthful
"nothing to correct" is a correct outcome, not a failure to find fault.
The skill's tone must never presume drift occurred.

Valid at any point in a conversation:

- **Start**: set the posture; there is nothing yet to audit.
- **Middle**: correct observed drift.
- **End**: verify before the user acts.

## The loop

Run these in order. Skip a step only when its input is genuinely absent
(see "Conversation-start case").

1. **Re-anchor.** Re-read the discipline's source of truth (the skill names
   it) with fresh attention and treat it as active for the rest of the
   task. Loading the skill is the re-anchor. The point is not to reprint
   the rules but to make them govern the next actions. State in one line
   that the discipline now governs the work.
2. **Self-audit the work in flight.** Walk back over the conversation and
   name concrete, located findings, not a generic mea culpa. Each finding
   points at a specific turn, claim, or artifact and at the specific part
   of the discipline it breaks. If there are none, say so plainly. Do not
   invent findings to look diligent. For work that others depend on (code,
   config, a recommendation, or a claim something downstream cites; when in
   doubt, treat it as depended on), a clean self-audit is not yet the verdict:
   dispatch a fresh-context subagent with the discipline's source and the
   work, not your audit, to audit it independently and report findings
   before step 4 reports clean; what it finds goes to step 3. The
   `verification` level governs this subagent as it governs step 3's: a
   corrector that resolves no level dispatches it, and under `light`, or
   `off`, which acts as `light` here, report "clean (self-audit only)" with
   `verification: skipped (<level>)`. A context that cannot spawn (a
   batched fork) returns "clean (unconfirmed)"; the pass that dispatched it
   runs the confirmation. A corrector whose step 2 already runs in a
   fresh-context subagent (a declared delta) has met this.
3. **Correct forward now.** For each finding, do the missing work this
   turn rather than merely noting it: edit the file, fix the config,
   re-derive the choice, in the working tree, now. Where your own
   judgment is the suspected source of the drift, re-derive it in a
   fresh-context subagent (blind to the reasoning that produced the drift)
   instead of self-checking in the context that produced it. A self-check
   in the same context is weak by construction. The `verification` level the
   invoking SKILL.md resolved, when it resolves one, governs this subagent; a
   corrector that resolves no level keeps the subagent as above. Under `light`, and
   `off`, which acts as `light` here, dispatch none and do not self-check in
   its place; report the finding open with `verification: skipped (<level>)`. Prefer a cross-vendor
   advisor for that re-derivation **when one is enabled and set up**.
   One example is the OpenAI Codex plugin, when its documented surface can take this artifact,
   invoked per its own docs. Keep the fresh-context same-vendor subagent as the stated fallback,
   never a route to a command that may not resolve
   (per `docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository).
   Surface anything that cannot be corrected here rather than
   papering over it. **Outward
   artifacts are the one carve-out:** correcting forward never *files* an
   outward artifact on its own. An outward artifact is a pull request, an
   issue, a published review comment, anything published outside this
   working session. Draft it
   and route it to the user; opening or publishing it waits on the user's
   explicit opt-in (see the Non-negotiable below). In-tree correction is
   not an outward artifact and stays on the do-it-now side of this line.
4. **Report.** One short list: what was corrected, what remains open, and
   an honest "clean" where the audit found nothing, labeled
   "(self-audit only)" when step 2's confirmation did not run, and under
   `light` or `off` the line `verification: skipped (<level>)` verbatim. When the audit changed
   a recommendation the user still has pending, re-state it as old → new →
   why, where new may be a withheld open question, per
   [`recommendation-basis.md`](recommendation-basis.md).

## Declared step deltas

A corrector may modify, insert, or reorder a step of this loop when the
discipline it re-anchors demands it, but only as a **declared delta**:
stated in that skill's own `SKILL.md` alongside the reason and, for an
inserted step, where it sits relative to the numbered steps, so the
divergence is part of the skill's contract rather than silent drift from
this method. A skill
that diverges without declaring the delta is in violation of this doc, not
exercising this allowance. The Non-negotiables below are never
overridable.

## Conversation-start case

Fired before any work exists, do only step 1: acknowledge the discipline
as active for the session and stop. There is nothing to audit. Do not
manufacture findings.

## Several repositories

A corrector whose `SKILL.md` says it accepts the target forms runs over
several repositories only when its arguments or the request name a target
form (`--repo <repo>` and the others in
[`${CLAUDE_PLUGIN_ROOT}/reference/target-scope.md`](../reference/target-scope.md)
"Target forms"). With no target form, the loop above runs unchanged on the
work in flight. That contract owns repository resolution, fan-out, merging,
the cross-repository signals and per-repository writes; this section adds
only the loop's delta:

- **Step 2's input.** Another repository has no work in flight in this
  conversation, so each repository's pass audits what the `SKILL.md` names
  for it, read as the contract's "Read state" says. The target form is that
  input, so the conversation-start case above does not apply. Each pass
  resolves the discipline's source of truth from that repository's own
  instruction layer (the ladder below, run per repository) and its
  verification level from that repository, running `read-verification.sh`
  as `CLAUDE_PROJECT_DIR=<root> bash ...`, since it otherwise reads the
  session's own project.
- **The per-repository subagents.** Each is a fresh subagent, not a fork.
  When it cannot spawn agents of its own, run the subagent the loop or the
  `SKILL.md` calls for from the main thread, with that repository's root
  anchored.
- **Step 3's writes.** A correction in another repository follows the
  contract's "Writes stay per repository", and each pull request is an
  outward artifact: draft it and open none without the user's explicit
  opt-in.
- **Step 4's report.** Per the contract's "Merging findings".

## Resolving the discipline's source of truth (portability)

A corrector re-anchors a discipline the *consuming* project owns, so it
resolves that discipline's source of truth from the consumer's own
context, never from a baked-in path. Apply the resolution ladder:

1. **Declared → use it.** When the consuming project states the discipline
   in its own instruction layer, whether its `CLAUDE.md`, its
   `.claude/rules/`, or a team conventions doc it points to, re-anchor that
   text. It is already
   in the model's context; the skill raises its salience and audits
   against it.
2. **Absent → fall back to the portable baseline.** When the consumer
   declares no such rules, re-anchor the concise baseline the skill states
   in its own body. The baseline is the plugin's own contract, phrased
   generically, enough to run the audit without a consumer rules file.
3. **Cite what actually resolved.** A finding is only a violation of the
   source that was actually read this session. If only the baseline
   applied, the citation is to the baseline, not to an assumed consumer
   doc.

This is graceful degradation: the corrector is fully useful in a project
with rich standing rules and still useful in one with none.

## Non-negotiables

- **Point at the source; do not restate it.** Re-anchoring raises the
  salience of rules already in context; copying them into the skill only
  creates a second copy that drifts from the first.
- **Never fabricate a citation or a finding.** Cite the source you read;
  report "clean" when the work conforms.
- **Prefer a fresh context over self-trust for anything the work rests on.**
  The context that produced the drift is the weakest place to catch it.
- **No corrector files an outward artifact without explicit opt-in.** A
  consume-only consumer can rely on this across every skill: a corrector
  may draft an outward change and route it to the user, but opening or
  publishing one, whether a PR, an issue, or a published review comment, is
  the user's call, gated on an explicit opt-in, never a side effect of
  correcting forward.
