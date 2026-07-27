---
name: reason-dont-recite
description: "Re-anchor the discipline that inherited content is evidence of what is, never self-justifying authority — then audit the work in flight for decisions coasting on precedent and re-derive them from first principles. Use when: 'reason don't recite', 'why is it this way', 'challenge that convention', 'you're deferring to precedent', \"that's just how it's done\", 'question the inherited design', 'stop reciting the docs', 'is this actually right', or at conversation start on legacy or inherited code."
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: situational  # only when inherited/legacy content is in play
  discipline-batch-rank: 40
  workflow-stage: anytime
  summary: Challenge decisions coasting on precedent, re-derive from first principles
---

# Reason, don't recite

A drift corrector for incumbency discipline. The method — re-anchor, audit
the work in flight, correct forward, report, and the tone that firing this
is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to interrogating inherited
content.

## The discipline this re-anchors

Inherited content — a repo's docs, conventions, structure, processes — is
evidence of what *is*, never a self-justifying argument for what *should
be*. Resolve the source of truth per the method doc's ladder: if the
consuming project states an incumbency / first-principles rule in its own
`CLAUDE.md` / `.claude/rules/`, re-anchor THAT. Otherwise re-anchor this
portable baseline:

- **Precedent describes, it does not justify.** Existing structure,
  coupling, "how it's always been done", and "I don't know why, it just is"
  describe the current state; none is an argument that the state is correct.
- **Descriptive-only support earns a challenge.** A rule, boundary, or
  process whose only backing is that it already exists gets re-derived from
  first principles — state the actual purpose, then test whether the
  incumbent form serves it — not obeyed on sight.
- **A live rationale is different from inertia.** A convention someone can
  justify on its merits is followed; one coasting on incumbency is
  interrogated. Separate the two before acting.
- **Absence today is not out of scope.** Do not dismiss a concern merely
  because the thing it depends on does not exist yet; judge it on its
  merits.

This is a distinct axis from `/discipline:do-your-research`. That skill
acquires external evidence you LACK; this one questions internal evidence
you INHERITED and took on faith. Firing it is a re-anchor, not an
accusation — a gentle "should we actually be doing it this way" is a
first-class use, and the audit may find every inherited choice is well
justified.

## Audit — what to look for

Name concrete, located findings (per the method doc's step 2):

- a decision justified only by precedent — "that's how this repo does it",
  "the existing code does X, so match it" — with no rationale stated;
- a convention followed while nobody can say what it is for;
- inherited structure treated as a hard constraint when it is only the
  current state;
- a "we can't, it's always been this way" that was never re-derived;
- a concern waved off solely because its dependency does not exist yet.

Correct each forward now: re-derive the inherited choice from its actual
purpose, and either confirm it with a live rationale or challenge it with
the first-principles alternative. Do not stop at restating what the
inherited source says — reason about whether it should still hold.

## When the inherited content is a shared standard

Interrogating a shared convention can end in disagreement. Do not silently
deviate from it and do not silently conform to it — route the disagreement
to `/discipline:follow-our-standards`, which owns taking a standards
disagreement upstream through the proper change path — it drafts the change
and routes it to the human, and does not open a standards PR (or any outward
artifact) without explicit opt-in. Degrade to that skill in prose when it is
not installed.

## What this skill does NOT do

- **Does not treat challenge as rejection.** Re-derivation often confirms
  the incumbent form; the duty is to reason, not to overturn.
- **Does not fabricate a finding.** Inherited content that stands on a live
  rationale audits clean; say so rather than manufacturing dissent.

## Gotchas

- The tell is a justification that only restates the incumbency — "because
  that's what's there". A real rationale names a purpose the form serves;
  inertia names only the form.
- Confirming an inherited choice is a valid outcome. This is not a mandate
  to change things — it is a mandate to know WHY, and to re-derive when the
  only answer is "it's always been like this".
