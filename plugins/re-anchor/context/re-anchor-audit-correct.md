# The re-anchor / audit / correct-forward loop

Shared by every skill in this plugin. Each corrector re-anchors ONE
standing discipline, applies it to the current conversation, and corrects
what has drifted. This file owns the common method; each skill's `SKILL.md`
adds only its own delta — which discipline, where that discipline's source
of truth lives, and any skill-specific action.

## What a corrector is (and is not)

An always-on rule loses salience over a long session: the instruction is
still in context near the top, but the recent turns stopped being governed
by it. A corrector re-injects the discipline near the context tail, where
it regains the pull the standing rule has lost, and forces an active
audit-and-correct pass instead of a passive reminder.

Firing a corrector is **not an accusation of violation**. It means
"re-anchor this discipline, apply it here, and check." Reaching for one as
a gentle reminder — before the work, or just to set posture — is a
first-class use, not a lesser one. The audit may return clean; a truthful
"nothing to correct" is a correct outcome, not a failure to find fault.
The skill's tone must never presume drift occurred.

Valid at any point in a conversation:

- **Start** — set the posture; there is nothing yet to audit.
- **Middle** — correct observed drift.
- **End** — verify before the user acts.

## The loop

Run these in order. Skip a step only when its input is genuinely absent
(see "Conversation-start case").

1. **Re-anchor.** Re-read the discipline's source of truth (the skill names
   it) with fresh attention and treat it as active for the rest of the
   task. Loading the skill IS the re-anchor — the point is not to reprint
   the rules but to make them govern the next actions. State in one line
   that the discipline now governs the work.
2. **Self-audit the work in flight.** Walk back over the conversation and
   name CONCRETE, located findings — not a generic mea culpa. Each finding
   points at a specific turn, claim, or artifact and at the specific part
   of the discipline it breaks. If there are none, say so plainly. Do not
   invent findings to look diligent.
3. **Correct forward now.** For each finding, do the missing work THIS
   turn rather than merely noting it — edit the file, fix the config,
   re-derive the choice, in the working tree, now. Where your own
   judgement is the suspected source of the drift, re-derive it in a
   fresh-context subagent (blind to the reasoning that produced the drift)
   instead of self-checking in the context that produced it — a self-check
   in the same context is weak by construction. Surface anything that
   cannot be corrected here rather than papering over it. **Outward
   artifacts are the one carve-out:** correcting forward never *files* an
   outward artifact — a pull request, an issue, a published review comment,
   anything published outside this working session — on its own. Draft it
   and route it to the user; opening or publishing it waits on the user's
   explicit opt-in (see the Non-negotiable below). In-tree correction is
   not an outward artifact and stays on the do-it-now side of this line.
4. **Report.** One short list: what was corrected, what remains open, and
   an honest "clean" where the audit found nothing.

## Conversation-start case

Fired before any work exists, do only step 1: acknowledge the discipline
as active for the session and stop. There is nothing to audit — do not
manufacture findings.

## Resolving the discipline's source of truth (portability)

A corrector re-anchors a discipline the *consuming* project owns, so it
resolves that discipline's source of truth from the consumer's own
context, never from a baked-in path. Apply the resolution ladder:

1. **Declared → use it.** When the consuming project states the discipline
   in its own instruction layer — its `CLAUDE.md`, its `.claude/rules/`, a
   team conventions doc it points to — re-anchor THAT text. It is already
   in the model's context; the skill raises its salience and audits
   against it.
2. **Absent → fall back to the portable baseline.** When the consumer
   declares no such rules, re-anchor the concise baseline the skill states
   in its own body. The baseline is the plugin's own contract, phrased
   generically — enough to run the audit without a consumer rules file.
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
- **Prefer a fresh context over self-trust for anything load-bearing.**
  The context that produced the drift is the weakest place to catch it.
- **No corrector files an outward artifact without explicit opt-in.** A
  consume-only consumer can rely on this across every skill: a corrector
  may draft an outward change and route it to the user, but opening or
  publishing one — a PR, an issue, a published review comment — is the
  user's call, gated on an explicit opt-in, never a side effect of
  correcting forward.
