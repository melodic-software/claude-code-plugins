---
name: reuse-or-replace
description: "Re-anchor the anti-fragmentation discipline that when an established way of doing something already exists — a code idiom, structure, error-handling approach, naming shape, doc format, or process — new work REUSES that established way or openly REPLACES it (migrate the old uses, record the decision); it never silently stands up a second, parallel way alongside. Then audit the work in flight for an invented approach that diverges from an established way with no stated reason. Replacing the established way is first-class — when evidence backs an improvement, or its rationale is missing, incumbency-only, or stale — the sin is the SILENT second way, not divergence itself. Use when: 'reuse or replace', 'we already have a way of doing this', 'don't invent a second way', 'keep it one way', 'follow the existing pattern or replace it', 'be consistent', 'you added a parallel way', 'this diverges from how we do it elsewhere', or at conversation start on work that extends an established codebase, structure, or process."
user-invocable: true
disable-model-invocation: false
---

# Reuse or replace

A drift corrector for anti-fragmentation discipline: one way to do a thing,
not two. When an established way already exists, new work reuses it or openly
replaces it — it does not add a silent second way beside it. The method —
re-anchor, audit the work in flight, correct forward, report, and the tone
that firing this is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to reusing or replacing an
established way rather than splitting into a parallel one.

## The discipline this re-anchors

When a codebase, structure, or process already has an **established way** of
doing something, new work must not silently stand up a **second, parallel
way** beside it. Two coexisting ways of doing the same thing is fragmentation
— it splits the reader's model, doubles the surface that drifts, and taxes
every future change with a "which one?" decision. Resolve the source of truth
per the method doc's ladder: if the consuming project states a
consistency / one-way rule in its own `CLAUDE.md` / `.claude/rules/`, re-anchor
THAT. Otherwise re-anchor this portable baseline.

Facing an established way, new work has exactly **two honest options** — the
two this skill is named for:

- **Reuse it.** Follow the established way, so the codebase keeps one way.
- **Replace it.** Openly argue the established way should change, then — if it
  should — *migrate* the old uses to the new way and *record* the decision.
  Replacement converges the codebase on the new single way.

The **sin is neither of those**: it is leaving the established way in place and
quietly adding a divergent way alongside it, so both now exist. That silent
second way is what this skill exists to catch.

### Misconstrual guard — this is NOT "always conform" (mandatory)

Reusing is **not** blind conformity, and this skill never demands straight
obedience to the incumbent way. Replacing the established way is a
**first-class, encouraged** move, not a deviation to be suppressed. The
established way *should* be replaced when:

- **evidence backs an improvement** — research or measurement shows a better
  way (route the evidence-gathering to `/re-anchor:do-your-research`);
- **its rationale is missing** — nobody can say why it is done this way ("I
  don't know, it just is");
- **it rests on incumbency only** — "we've always done it this way" is the
  sole support;
- **it is stale or outdated** — newer developments may have superseded it;
  a challenge on this ground requires *fresh* research, not recall.

Blind trust in the status quo is explicitly bad: don't reuse the established
way just because it is the established way. The discipline is not "never
diverge" — it is "**never diverge silently**." When you replace, do it in the
open and carry it through — migrate the old uses. When you reuse, reuse because
the way holds up, not merely because it is there — that interrogation is
`/re-anchor:reason-dont-recite`'s axis (below).

### The burden rule — divergence is priced by blast radius

Replacing the established way (or otherwise diverging from it) is allowed, but
it carries a burden: a **stated rationale**, recorded proportional to the
divergence's blast radius.

- **Durable or architectural** divergence — a new structural pattern, a
  different error-handling model, a second workflow — records its rationale
  where durable decisions live: the repo's ADR or docs convention.
- **Small, local** divergence records it where the change is reviewed: the
  PR description or the commit message.
- **No recorded reason at all** is the finding. An unexplained second way is
  fragmentation whether or not it is defensible on its merits — the burden is
  to say *why*, not merely to be right.

## Scope — the unlintable "approach" level

This skill owns consistency of **how work is done** where judgement, not a
tool, decides it: code idioms and shapes, module and file structure, naming
shapes, error-handling and logging approaches, API and interface conventions,
documentation formats, and process or workflow choices.

**Mechanical style is out of scope** — indentation, quote style, import
order, line length, and everything a formatter or linter settles
deterministically belong to those tools, not to a judgement corrector. This
skill fires at the level a linter cannot reach: the *approach*, not the
whitespace.

## Distinct axes — the two skills this must not be confused with

Firing this cleanly requires keeping it apart from two siblings; the
boundaries are deliberate, not incidental.

- **`/re-anchor:reason-dont-recite` (evaluation-side).** That skill
  interrogates *inherited* content — is this existing convention actually
  justified, or coasting on precedent? This skill is **production-side**:
  when *creating new work*, reuse the established way unless you state a
  reason to replace it. They meet at the challenge: when this skill's audit
  finds you *want* to replace the established way, the question "is the
  established way even right?" is reason-dont-recite's, and the evidence for a
  better way is `/re-anchor:do-your-research`'s. Reuse-or-replace governs the
  *second way*; those govern the *justification*.
- **`/re-anchor:pick-for-the-problem` (carve-out — does NOT overlap).** That
  skill governs selecting a tool, library, framework, or dependency to fit
  the problem, and names incumbency as a *selection sin*. This skill
  **never governs that selection.** Consistency of idioms, structure, and
  process is reuse-or-replace; choosing *what tool or dependency to adopt* is
  pick-for-the-problem, where matching the incumbent choice can be exactly
  the wrong reflex. Do not apply this skill to a build-vs-buy or
  which-library decision — route it there.

## Audit — what to look for

Name concrete, located findings (per the method doc's step 2):

- a new pattern, idiom, or structure standing beside an existing one that
  already solves the same thing, with no stated reason for the second way;
- a divergent error-handling, logging, naming, or interface approach
  introduced where the codebase already has an established one;
- a second workflow, process, or document format added alongside the
  established one rather than reusing or replacing it;
- a divergence whose blast radius is durable/architectural but whose
  rationale was never recorded in the repo's ADR/docs convention;
- a small local divergence with no rationale in its PR or commit;
- an established way reused only because it is there, where its rationale
  is missing, incumbency-only, or stale — a challenge that was owed and
  skipped (route to `/re-anchor:reason-dont-recite` /
  `/re-anchor:do-your-research`).

Correct each forward now: reuse the established way for the new work; or,
where replacement is warranted, record the rationale at the blast-radius-
appropriate level AND — if the established way is genuinely superseded —
migrate the existing uses and retire it rather than leaving both. Never settle
for the silent second way.

## What this skill does NOT do

- **Does not mandate conformity.** A well-grounded replacement that supersedes
  the established way and migrates its uses is a correct outcome, not a
  violation; the duty is to keep one way, not to freeze the incumbent one.
- **Does not police mechanical style.** Formatting and lint-settled choices
  belong to the linter/formatter; this skill audits the unlintable approach
  level only.
- **Does not govern tool or dependency selection.** That is
  `/re-anchor:pick-for-the-problem`; incumbency there is a selection sin, not
  a consistency target.
- **Does not fabricate a finding.** New work that already reuses the
  established way, or replaces it with a recorded reason, audits clean; say so.

## Gotchas

- The tell is **two ways where one would do** — not divergence itself. A
  single replacement that openly superseded the old way (uses migrated,
  decision recorded) kept the codebase on one way; it is the goal, not the
  finding. The finding is the old way and the new way both left standing.
- "Be consistent" read as "never replace" inverts the skill. Blind trust in
  the status quo is the failure mode on the *other* side; the misconstrual
  guard exists because straight conformity is not the goal — one way is.
- A recorded reason is the burden, not correctness. An unexplained second way
  is a finding even if it would have been defensible; the fix is to state the
  rationale (and keep one way), not to argue the divergence was fine.
