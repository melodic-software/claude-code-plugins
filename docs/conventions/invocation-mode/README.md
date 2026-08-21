# Skill invocation-mode rubric

Owner doc for choosing a skill's **invocation mode** — whether the model may invoke it
(`disable-model-invocation: false`, the fleet default) or only a human may
(`disable-model-invocation: true`). Consumed by skill authors at design time
(`playbooks:skill-authoring`), by the fleet gate (`skill-quality:check`), and by audits grading
existing skills. One home per the convention registry
([`docs/PLUGIN-PHILOSOPHY.md`](../../PLUGIN-PHILOSOPHY.md) "Convention registry"); this doc decides,
other surfaces point here.

Provenance: AI Hero course steering lane 8
([#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910), 2026-08-17) —
an evidence-driven re-derivation, assuming correct neither upstream's user-invoked default
(mattpocock/skills `SKILL-MECHANICS.md`) nor this fleet's de facto model-invoked posture.

## The default, and why

**Model-invoked (`disable-model-invocation: false`) is the default.** Every exception must name
one of the three classes below. The key is written **explicitly** on every skill — the official
default for an absent key is `false` (docs table row, code.claude.com/docs/en/skills, verified
2026-08-17), but an explicit key makes the choice auditable and is enforced by a
`skill-quality:check` criterion.

Evidence behind the default (verified 2026-08-17 against current official docs unless noted):

- **A `true` skill is model-invisible everywhere.** `disable-model-invocation: true` removes the
  skill from Claude's context entirely — the description never enters the listing, no other
  skill can reach it mid-session, subagent preload is blocked, and (v2.1.196+) scheduled-task
  prompts cannot name it. Only the human `/name` path remains. Hiding a skill from the model is
  therefore a *total* trade, not a listing-budget optimization.
- **Surface coverage:** Claude desktop/web surfaces drop user-invoked skills from the listing
  (upstream issue mattpocock/skills#693) — a user-invoked default would make skills invisible on
  those surfaces.
- **Cloud scope:** remote sessions never load `~/.claude` user scope; project/marketplace skills
  are the only steering that reaches cloud sessions, so marketplace skills carry the full
  discoverability burden there.
- **Multi-repo product:** consumers do not memorize 200+ skill names; model-side discoverability
  is part of what this marketplace sells. This inverts upstream's solo-operator premise.
- **Listing budget is manageable, not a forcing function:** every skill name is always listed;
  only descriptions are dropped (least-invoked first) under the ~1%-of-context budget
  (`skillListingBudgetFraction`), with a per-entry cap (`skillListingMaxDescChars`, 1,536 chars).
  The per-skill `skillOverrides: "name-only"` lever reaches project/user skills only — plugin
  skills are explicitly exempt ("Plugin skills are not affected by `skillOverrides`. Manage
  those through `/plugin` instead"), so for this marketplace's fleet the applicable levers are
  trimming descriptions at the source and plugin enablement via `/plugin`.
  `skill-quality:check listing-budget` is the standing measurement instrument.

## Exception classes (the only reasons to write `true`)

1. **(i) Side-effect / manual-timing workflows.** The skill mutates state whose timing must be a
   deliberate human choice (fleet sync, batched deletion, machine-level session control), or its
   triggering signal is private to the human (e.g. `discipline:wait-what` — only the human knows
   comprehension broke), or it enters a persistent session-consuming mode the human should choose
   deliberately (e.g. `education:teach`).
2. **(ii) Setup skills.** Per the PLUGIN-PHILOSOPHY setup contract ("Setup is explicit and
   repeatable"): `setup` skills are named `setup` and carry `disable-model-invocation: true`.
3. **(iii) Maintainer-only skills.** Operate on this marketplace's working tree (vendored-content
   sync, drift checks); meaningless or harmful for consumers to reach via the model.

A skill claiming `true` under none of these classes is wrongly graded: flip it to `false` (or make
the case for a new class *in this doc* first — the class list, not the skill, is the unit of
extension).

## The invocation-reach invariant

A `disable-model-invocation: true` skill **cannot be invoked by any other skill** — cross-skill
reach requires model invocation. CONFIRMED against current official docs 2026-08-17 (see the
tracked strand in [`docs/upstream/mattpocock-skills.md`](../../upstream/mattpocock-skills.md)).
Consequences: any skill another skill chains to MUST be `false` (this is the rubric's
cross-skill-reach axis), and no skill body may instruct model invocation of a `true` target —
the audit-side trigger that guards this lives in the SSOT strand.

## Cross-skill invocation phrasing

When a skill body chains to another skill, name the mechanism explicitly — "invoke
`/plugin:skill` via the Skill tool" (or an equivalent that names the Skill tool) — never bare
`/name` prose, which reads as a suggestion to a human rather than an instruction the model
reliably executes. Scope: this binds NEW and EDITED skill text; the existing fleet is mixed
(many skills already use the explicit form, others chain bare — e.g. the knowledge pipeline
handoffs), and normalizing the existing operative chains is the filed sweep
[#3002](https://github.com/melodic-software/claude-code-plugins/issues/3002) (adopted
2026-08-18, lane 6 of the AI Hero course vetting — `docs/upstream/aihero-course.md`). Upstream
basis, named
provenance: mattpocock/skills standardized the same rule in `.agents/invocation.md` (upstream
PRs #878 and #880) on his measured claim — his repo's measurement, not re-verified here — that
explicit Skill-tool phrasing has a higher cross-skill hit rate than bare `/name` prose.

## Splitting by invocation

When one skill serves both an autonomous-reach audience and a manual-timing audience, split it so
each half takes its honest mode (upstream's "splitting by invocation", adopted via this rubric).
The write-side authoring skill (`docs-hygiene:write-for-agents`, #2962) points here for its
when-to-split doctrine.

## Router-skill verdict: REJECTED (2026-08-17)

Upstream's router pattern — a model-invoked skill whose job is routing the agent to user-invoked
skills — is rejected for this fleet: under the model-invoked default, the always-in-context
listing already does that job, and this fleet's `true` set is *deliberately* model-invisible, so
a router reaching into it would defeat the exception classes. The human-side cognitive-load
problem is answered by `docs/SKILL-CHEAT-SHEET.md` and `claude-ops:inventory`.
**Carve-out:** domain-scoped *composition* routers (`discipline:sweep-all` — membership derived
from corrector metadata) are a distinct, admitted pattern; they compose model-invoked skills
rather than recovering discoverability for hidden ones.

## Fleet grade — 2026-08-17 (ADR 0005-bounded)

Bounding question: *do the 10 non-setup `disable-model-invocation: true` skills fall into an
exception class?* (Fleet measurement, re-counted 2026-08-17 at the chain-close merge: 215
top-level skills = 141 `false` / 17 missing key / 57 `true` = 47 `*:setup` + these 10. The 47
setup skills are class (ii) by contract; the 141
`false` skills conform to the default and are not swept, per
[ADR 0005](../../adr/0005-bound-instruction-surface-work-by-question-not-population.md).)

| Skill | Class | Verdict |
|---|---|---|
| `claude-ops:lanes` | (i) machine-level session mutation, manual timing | KEEP `true` |
| `claude-ops:plugins` | (i) mutating fleet sync | KEEP `true` |
| `discipline:wait-what` | (i) trigger is human-internal | KEEP `true` |
| `disk-hygiene:clean` | (i) destructive-capable, manual-only by design | KEEP `true` |
| `dometrain:sync` | (iii) maintainer-only | KEEP `true` |
| `education:teach` | (i) deliberate mode-entry, persistent coaching state | KEEP `true` |
| `firecrawl:update` | (iii) maintainer-only | KEEP `true` |
| `planning:questionnaire` | none — no side effects, not setup, not maintainer-only | **FLIPPED → `false`** ([#2969](https://github.com/melodic-software/claude-code-plugins/issues/2969); the re-check for a latent rationale found none — see below) |
| `playbooks:update` | (iii) maintainer-only | KEEP `true` |
| `repo-fleet-hygiene:apply` | (i) mutating fleet apply incl. branch deletion | KEEP `true` |
| `session-flow:show-options` | none — a human-facing catalog surface: no side effect whose timing must be human-chosen, an *uttered* trigger rather than a human-internal one, not setup, not maintainer-only | **FLIPPED → `false`** ([#3024](https://github.com/melodic-software/claude-code-plugins/issues/3024); graded after the fact, and the re-check against ADR 0016's latent rationale did not hold it — see below) |

The 17 missing-key skills were normalized to explicit `false` (all sat in the default class), and
the enforcement criterion shipped alongside them as `skill-quality:check` **check 24** — both under
[#2968](https://github.com/melodic-software/claude-code-plugins/issues/2968), filed rather than
edited in-lane. Fleet after that normalization (2026-08-19): 220 top-level skills = 161 `false` /
0 missing key / 59 `true`.

**The one flip, and the latent rationale it was re-checked against (2026-08-19, #2969).** The grade
found no exception class for `planning:questionnaire`, so the flip was gated on first looking for a
reason the grade could not see. The candidate was a trigger collision with `planning:interview` —
both plausibly firing on "I need to ask…"-shaped requests. There is none: the two are separated by
*who holds the knowledge*, and each description already routes to the other on that axis
(`questionnaire` says to run `/planning:interview` when the user can answer themselves;
`interview`'s phrases — "ask me questions first", "what do you need to know" — are about
interrogating the user, while `questionnaire`'s phrases name the third-party holder who is asked in
the user's place). Two costs of the `true` surfaced instead, both now paid: its trigger phrases were
deliberately left unoptimized because a
hidden skill's description is never matched against user text (planning CHANGELOG 0.30.1), and its
own description advertises a hand-off from an interview branch that the invocation-reach invariant
made unreachable while it stayed hidden. Fleet after the flip: 162 `false` / 58 `true` = 48 `*:setup`
plus 10 non-setup.

**The second flip: `session-flow:show-options`, graded after the fact (2026-08-21, #3024).** It
landed 2026-08-18, a day after the grade, so the table's population predated it and the ADR 0005
bound left it unswept rather than silently covered — check 24 emitted its hand-verify note for
exactly that case. It is now graded, and the verdict is a flip.

*It is not the rejected router.* That verdict names a model-invoked skill routing **the agent** to
user-invoked skills, and rejects it on two grounds: the always-in-context listing already does that
job, and a router reaching into the deliberately-hidden `true` set would defeat the exception
classes. Neither reaches this skill. The first is false here by measurement — ADR 0016 records the
listing omitting every `true` skill and dropping ~82% of descriptions least-invoked-first, which is
the whole reason this skill resolves from the installed catalog instead. The second turns on
*naming* versus *reaching*: `show-options` renders a menu and explicitly does not execute what the
human picks, and both surfaces the router verdict itself blesses as the answer to the human-side
problem — `docs/SKILL-CHEAT-SHEET.md` and `claude-ops:inventory` (itself `false`) — already name the
`true` set to a human from a model-reachable surface. Naming hidden skills to a human is settled
practice in this fleet; only the agent invoking them is what the exception classes forbid. Nor is it
the composition-router carve-out, which composes model-invoked skills rather than surfacing hidden
ones.

*No exception class fits.* Not (ii) or (iii) — it is consumer-facing and neither setup nor
maintainer-only. Not (i) on any of its three limbs: the Spotlight ledger is incidental bookkeeping,
not state whose timing must be a deliberate human choice; the skill is a one-shot render
("presentation only"), not a persistent mode-entry; and its trigger is the opposite of
`discipline:wait-what`'s human-internal one — "what should I run next", "what are my options",
"what am I forgetting" are *utterances*, fully observable in the transcript, not an unspoken state
only the human can detect.

*The latent rationale it was re-checked against, per the #2969 precedent.* Here one existed and was
dated: [ADR 0016](../../adr/0016-source-skill-recommendation-from-the-catalog-not-the-listing.md)
shipped V1 manual-only for three stated reasons. None holds as an exception class. (1) *Costs no
listing-budget description* — the default section above rejects exactly this move: hiding a skill
from the model is a total trade, not a listing-budget optimization. (2) *Avoids a verbatim trigger
collision with `session-flow:workflow`* — the same shape as #2969's candidate, and it dissolves the
same way: ADR 0016 itself resolved that collision reciprocally, amending `workflow`'s
"never present both" mandate to govern **stage** routing and cede option surfacing, and each
description now routes to the other on that axis. Hiding is redundant belt-and-braces over a
collision already fixed by another mechanism. (3) *Graduation is evidence-gated* — the real
objection, but its own criterion measures the bucket cut rather than the mode (the ADR says to
revisit the buckets first and the posture second), and the evidence cannot accrue while the
recursion the ADR names goes unsolved: the operator must remember to invoke the skill about
forgetting skills.

*The two costs of the `true`, both now paid* — the same pair #2969 surfaced. Its trigger phrases
were dead, because a hidden skill's description is never matched against user text: a human who
says "what are my options" out loud got nothing. And the invocation-reach invariant made
`workflow`'s shipped boundary paragraph a dangler, pointing the model at a target it could not
reach. The cost the flip incurs is one description entering the listing budget, which the default
section holds is manageable and not a forcing function.

*What the flip does not buy, stated rather than left implicit.* It does not guarantee trigger
matching. The fleet's aggregate listing measures **117,695 chars against an 8,000-char budget
(~14.7× over)** — `skill-quality:check listing-budget` over `plugins/*/skills`, 2026-08-21 — and
under overflow Claude Code drops the least-invoked skills' descriptions to **name-only** first, a
drop order a never-invoked skill sits at the front of. The floor this flip establishes is therefore
name-only visibility, not description matching. That floor is still strictly above where `true`
sat: `disable-model-invocation: true` removes the skill from context *entirely* — name included —
and blocks cross-skill reach and subagent preload, whereas a name-only entry is listed,
model-invocable, and chainable. Whether any given description survives the aggregate is a
fleet-wide budget question, owned by `claude-ops:audit-skill-visibility` and measured by the
instrument above; it is not a reason to hide a skill, which the default section forecloses in
terms ("hiding a skill from the model is a *total* trade, not a listing-budget optimization").

ADR 0016 is amended in place to record the revised posture; its core decision — resolve candidates
from the catalog, not the listing — is untouched and is what makes this skill worth reaching.

Fleet after this flip (2026-08-21): 222 top-level skills = 165 `false` / 0 missing key / 57 `true`
= 48 `*:setup` plus 9 non-setup. **Every non-setup `true` skill in the fleet now carries a verdict
in the table above**, and the table's two flips are the only entries that are not KEEP.

## Cross-references

- PLUGIN-PHILOSOPHY: setup contract (class ii source), Instruction economy (listing-cost
  doctrine), Convention registry (this doc's row).
- `skill-quality:check`: `listing-budget` (measurement) and check 24, the explicit-key criterion
  (enforcement — FAIL for a marketplace plugin skill, WARN elsewhere; class attribution is
  hand-verified against this doc, since only a `setup` skill's `true` is decidable by a static scan).
- `playbooks:skill-authoring`: authoring-time pointer here ("Choosing the mode at authoring time").
- Steering-lane provenance and lesson decision rows:
  `docs/upstream/aihero-course.md` (lane 8 section; the interim steering record dissolved into
  it at harvest).
