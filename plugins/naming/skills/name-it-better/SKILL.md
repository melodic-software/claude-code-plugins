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
   [`context/sources.md`](context/sources.md): intention-revealing and
   semantically accurate to the responsibility, evolution-safe (the name
   sets scope and bounds), context-sensitive, free of overloaded or
   disinformative terms, and drawn from the domain's ubiquitous language.

## Default pass

1. **Distill a context brief.** Capture, in a few lines: the
   responsibility of the thing, its scope and lifetime, hard constraints
   (language casing rules, length, collisions to avoid), the existing
   surrounding vocabulary, and a blocklist of overloaded terms to avoid.
   This brief — NOT the conversation — is all the generators receive.
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
   generators — or that collides with the existing vocabulary. Score every
   surviving candidate against the criteria resolved above.
4. **Shortlist + recommend.** Present a short ranked list with a
   one-line rationale per candidate and a single RECOMMENDED pick, marked
   and listed first.
5. **Human picks.** Stop and let the user choose. Do not apply the name.

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

- Resolving what a domain concept IS (not just its label) → a
  domain-modelling capability. Hand a settled domain term there.
- Sweeping references after a rename is decided → a rename-references
  capability. This skill picks the name; that one propagates it.

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
- `tournament` costs several generators plus judges; reserve it for names
  that are genuinely expensive to change, not routine locals.
