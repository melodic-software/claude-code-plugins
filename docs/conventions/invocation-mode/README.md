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
| `planning:questionnaire` | none — no side effects, not setup, not maintainer-only | **FLIP → `false`** (filed as [#2969](https://github.com/melodic-software/claude-code-plugins/issues/2969)) |
| `playbooks:update` | (iii) maintainer-only | KEEP `true` |
| `repo-fleet-hygiene:apply` | (i) mutating fleet apply incl. branch deletion | KEEP `true` |

The 17 missing-key skills were normalized to explicit `false` (all sat in the default class), and
the enforcement criterion shipped alongside them as `skill-quality:check` **check 24** — both under
[#2968](https://github.com/melodic-software/claude-code-plugins/issues/2968), filed rather than
edited in-lane. Fleet after that normalization (2026-08-19): 220 top-level skills = 161 `false` /
0 missing key / 59 `true`.

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
