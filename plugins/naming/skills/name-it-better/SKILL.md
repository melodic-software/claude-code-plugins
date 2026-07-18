---
name: name-it-better
description: "Generate and evaluate fresh name candidates for anything — a variable, function, file, module, skill, repo, or domain term — then let the human pick. Use when the target name is still UNDECIDED: 'name it better', 'better name', 'that name is wrong', 'suggest names', 'what should I call this', 'need a name for', 'come up with a name', 'help me rename this to something better'. Not for an already-decided rename ('rename X to Y', 'I renamed X') — that routes to the rename-references sweep. Spawns blind fresh-context generators from distinct lenses; never auto-locks a name. Optional 'tournament' arg for high-stakes, hard-to-refactor names."
argument-hint: "[tournament]"
user-invocable: true
---

# Name it better

## Purpose

Produce better name candidates for anything that needs one — an
identifier, file, module, skill, repo, or domain term — and hand the
human a scored shortlist to choose from. The dominant trigger is a
reactive retry: a name was just suggested and rejected, and the same
context that produced it will only produce more of the same. So the
generators run BLIND to the conversation, from distinct lenses, to break
the anchor. A blank-slate naming request is the same machinery without a
rejected incumbent.

**The human always picks.** This skill narrows and recommends; it never
auto-locks a name.

## Criteria — cite the source of truth, do not copy it

Score against the consuming organization's naming criteria, resolved from
its own context, never from a baked-in path:

1. **Declared conventions win.** When the consuming project names where its
   naming and domain-language conventions live — its `CLAUDE.md`,
   `.claude/rules/`, a shared standards source it points to — score against
   THAT. Read the criteria there; do not restate them here. A criterion the
   user wants that is missing from those conventions flows UP into them
   (their standards change), not hardcoded into this skill.
2. **None declared → the general criteria** grounded in
   [`context/sources.md`](context/sources.md), applied in this
   research-ordered priority — a higher tier breaks ties over every tier
   below it:
   1. **Semantic accuracy (anti-misleading).** The name must not lie about
      what the thing does. A misleading name is empirically worse than a
      vague or meaningless one, so this outranks everything below.
   2. **Scope fit.** Length and detail scale with the thing's scope and
      lifetime; never repeat information the surrounding context (package,
      type, module) already supplies.
   3. **Comprehensibility.** Prefer full, intention-revealing words over
      abbreviations — bounded: established idioms and conventionally short
      names (loop `i`, a receiver) are not penalised.
   4. **Trigger / evocative utility.** How well the name cues recall at the
      moment of use — a genuine tiebreaker, but the lowest-priority one.

   This ordering governs the scoring and judging steps. It is the fallback
   only: a consuming project's declared criteria (rule 1) override it
   wherever the two differ.

## Semantic vs syntactic — the modality layer

Naming criteria split in two. The **semantic layer** — accuracy, scope
fit, no collisions, noun-for-a-thing / verb-for-an-action — carries across
every modality, and is what the generators and judges optimise. The
**syntactic layer** — casing, length budgets, separator and affix
conventions — is modality- and vendor-specific; apply it as a final
shaping pass over the semantic winners, never as a scoring axis that
overrides meaning. Shaping can change the string, so RE-RUN the collision
and reject-list checks on the shaped form: a normalization
(`SessionStore` → `session_store`) can recreate an existing sibling or a
rejected incumbent that the pre-scoring check could not match.

- **Route documented conflicts out; do not pick a side.** Where authorities
  genuinely disagree — abbreviation policy, acronym casing, camelCase vs
  snake_case — this skill takes no house position. Defer to the consuming
  ecosystem's own style guide (rule 1's declared conventions); the
  conflicting primaries are catalogued in
  [`context/sources.md`](context/sources.md).
- **Claude Code skills are the sharp special case.** For a skill, the
  DESCRIPTION — not the name — is what drives model-side discovery. So
  optimise the name for human semantic accuracy, and put the trigger
  phrases and example requests in the description, not the name.

## Default pass

1. **Build the structured context brief.** This brief — NOT the
   conversation — is all the generators receive, so it must carry every
   field they need, each captured by name:
   - **Responsibility** — what the thing DOES, in one line.
   - **Firing / usage context** — when it is reached for, and how it reads
     at the call site.
   - **Scope boundaries** — what it is NOT: the adjacent things it must not
     be confused with or blur into.
   - **Collision vocabulary** — the existing sibling names it must not
     duplicate.
   - **Word-level blocklist** — individual words ruled out, each WITH its
     reason (overloaded, misleading, collides, already rejected).

   Rejected incumbent NAMES deliberately stay out of the brief — the main
   thread holds them as its reject list and disqualifies matches at merge
   time (anti-anchoring: a generator shown a rejected name re-derives it).
   Only the abstracted REASON a name failed enters the brief, as a
   blocklist entry or scope-boundary correction.

   The brief mirrors the replicated concept → word → structure naming model
   (grounded in [`context/sources.md`](context/sources.md)): the named
   fields fix the concepts and constraints; the generators then choose the
   words per concept and arrange the structure.
2. **Fan out blind generators.** Spawn ~3 fresh-context subagents, each
   seeded ONLY with the brief (blind to this conversation and to each
   other), each working a distinct lens:
   - **responsibility-literal** — name exactly what it does;
   - **moment-of-use** — name for how it reads at the call site;
   - **domain-lore** — name from the domain's ubiquitous language.

   Running them blind and independent is deliberate anti-anchoring; the
   method grounding is in [`context/sources.md`](context/sources.md).
3. **Merge and score.** Pool the candidates, dedupe, and disqualify any
   candidate that matches the rejected incumbent (if any) — carried by the
   main thread as an explicit reject list, never shared with the
   generators — that contains a word-level blocklist entry (a generator
   can miss the brief's constraint; the merge step enforces it), or that
   collides with the existing vocabulary. Score every
   surviving candidate against the criteria resolved above, breaking ties
   by their declared priority order.
4. **Shortlist + recommend.** Present a short ranked list with a
   one-line rationale per candidate and a single RECOMMENDED pick, marked
   and listed first.
5. **Human picks.** Stop and let the user choose. Do not apply the name.

## Iterate on the rejection reason

If the human rejects the shortlist or a specific candidate, the rejection
is data, not a dead end. Capture the REASON as an explicit new constraint
and fold it into the next round's brief before regenerating:

- a word that drew the objection becomes a **word-level blocklist** entry,
  carrying that reason;
- a "wrong scope / wrong thing" objection becomes a **scope-boundary**
  correction;
- a "these all miss what matters" objection **reweights the criteria** for
  the next round — but only within the space the consuming project's
  declared conventions leave open. Declared conventions still win: a
  rejection that contradicts them routes upstream as a proposed convention
  change, never a silent local reweighting.

Rejected names and rejected words never re-enter — the reject list and the
word-level blocklist only grow across rounds. Each new round is a fresh
blind fan-out seeded with the corrected brief, never a patch of the last
round's candidates.

## `tournament` action

When `$ARGUMENTS` contains `tournament`, run this in place of the default
pass.

`/naming:name-it-better tournament` — for a high-stakes name that will be
hard to refactor later. Widen to ~5 generators (optionally different
models), then run elimination rounds with independent scoring judges until
one candidate remains, and present it plus the runners-up for the human
choice.

The reject-list and collision disqualification from the default pass's
merge step still apply: pool the widened candidates and disqualify any that
match the rejected incumbent or collide with the existing vocabulary BEFORE
the elimination rounds begin — a rejected or colliding name must never enter
the bracket, let alone reach the finalist.

HONEST FRAMING: a "naming tournament / bracket" is NOT a documented
software-naming technique. This mode ADAPTS elimination brackets plus
pairwise social-choice scoring as a convergence mechanism — see
[`context/sources.md`](context/sources.md). Present it as such, not as an
established standard.

## Adjacent skills — hand off, do not overlap

- **The target is a domain concept.** Naming a domain term well depends on
  first settling what the concept IS, not just its label. Route that to a
  domain-modelling capability, then name the settled concept once it
  returns. Pointer only — this skill does not do the domain modelling.
- **A rename is already decided.** Sweeping references after the fact →
  a rename-references capability. This skill picks the name; that one
  propagates it.

Invoke an adjacent capability through its slash command when present;
degrade to prose guidance when it is absent.

## What this skill does NOT do

- **Never auto-locks a name.** It always ends at a human choice.
- **Does not apply the rename.** Propagating a chosen name across call
  sites is a rename-references capability's job.
- **Does not copy or invent criteria.** It scores against the resolved
  source of truth; missing criteria route upstream, not into the skill.
- **Does not claim tournament mode is a documented technique** — it is an
  adaptation, flagged as one.
- **Does not pick a house side on documented style conflicts** —
  abbreviation policy, acronym casing, and casing style route to the
  consuming ecosystem's own style guide, never a baked-in verdict.

## Gotchas

- If the generators are fed the conversation instead of just the brief,
  the anti-anchoring purpose is defeated — they will re-derive the
  rejected name. Seed them with the brief ONLY.
- A blind generator can still independently re-derive the rejected
  incumbent (common for generic labels like `Manager` or `Context`). That
  is not a blinding failure — the main thread's reject list disqualifies
  it at merge time regardless of how a candidate was produced.
- A candidate that scores well but collides with existing vocabulary is
  disqualified, not shortlisted — collision-check before scoring.
- A rejected candidate's REASON must become a brief constraint (a blocklist
  word, a scope correction, a criteria reweight) before the next round, or
  the blind fan-out re-derives the same reject.
- `tournament` costs several generators plus judges; reserve it for names
  that are genuinely expensive to change, not routine locals.
