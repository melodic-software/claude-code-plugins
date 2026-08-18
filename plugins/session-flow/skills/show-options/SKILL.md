---
description: "Lay out which skills fit this moment as a decidable menu — a ranked shortlist per bucket plus the complete remainder by name, so nothing is hidden and the human chooses. Buckets: Now, Next, Skipped upstream (artifact-grounded), and a rotating Spotlight of three. Never omits an option because it judges the step already done or unnecessary — that judgment becomes an annotation and may affect rank, never presence. Resolves candidates from the full installed catalog rather than the in-context skill listing, which omits every manual-only skill and truncates most descriptions. Use when: 'what should I run next', 'what are my options', 'what am I forgetting', 'which skill fits here', 'what else could I run', 'show me my options', 'what skills apply now'. Writes one small rotation ledger per invocation so the Spotlight advances; otherwise read-only. Not the staged-workflow navigator that routes to exactly one next stage (/session-flow:workflow), not a situation report (/session-flow:orient), and not the model-side corrector for a skill that should have fired (/discipline:use-your-skills)."
argument-hint: "[topic-slug] (e.g. /session-flow:show-options, /session-flow:show-options my-topic)"
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: anytime
  summary: Lay out the skills that fit this moment as a ranked, nothing-hidden menu
---

# Show options

The operator cannot hold ~200 installed skills in their head. This turns the catalog from something
they must remember into something they consult: a menu of what fits *this* moment, ranked, with
nothing withheld.

**The human decides.** This skill's judgment goes into *rank* and *annotations*. It never goes into
*presence*.

## The two rules

Both are load-bearing, and one without the other fails:

1. **Never omit a candidate's name.** Not because a step looks already done, not because it looks
   unnecessary, not to keep the output short. A skill the evidence says already ran is ranked
   normally and annotated `(ran this session)`.
2. **Never invent a candidate.** Every name rendered must come from the resolved catalog. Rule 1
   creates pressure to fill buckets from a thin source; filling them with plausible-sounding names
   is the worse failure, because a menu that confidently routes to something that does not exist is
   worse than a short menu.

Rule 1 is not novel here — it is this plugin's existing doctrine. The
[`${CLAUDE_PLUGIN_ROOT}/reference/structure.md`](${CLAUDE_PLUGIN_ROOT}/reference/structure.md)
**"Every section is always present"** rule holds that a section with nothing to report says so
explicitly, because "a cold reader cannot otherwise tell 'nothing to report' from 'the author
forgot', and the absence is itself load-bearing." Same reasoning, applied to options.

### Omit irrelevant, never unnecessary

These are one word apart and the whole output size turns on the difference, so the test is written
rather than left to judgment:

- **Irrelevant → omit.** The skill's *domain* does not apply to this session at all: songwriting
  skills in a code session, Kindle tooling in a research session. No reasonable operator would
  consider it.
- **Unnecessary → keep, annotate.** The skill's domain applies and the operator *could* reasonably
  run it; the model merely believes they need not. That belief is an annotation.

When unsure which side a candidate falls on, it is unnecessary — keep it.

## Resolve the candidate set

Two separate needs, resolved separately. Detail, formats, and failure behavior:
[`context/candidate-ladder.md`](context/candidate-ladder.md).

**Names — completeness is a correctness property.** The in-context skill listing is *not* an
acceptable sole source: it omits every `disable-model-invocation: true` skill outright, and when the
listing overflows its budget it drops descriptions **starting with the least-invoked skills** — the
forgotten ones this skill exists to surface. Ladder:

1. `/claude-ops:inventory` — if that plugin is installed. It owns whole-fleet enumeration and its
   bundled script already reports every installed skill including manual-only ones; reuse it rather
   than walking the plugin cache, whose layout is undocumented and version-keyed.
2. An operator-supplied catalog file, when the consuming project provides one.
3. The in-context listing — last resort, and its truncation is **disclosed in the output**.

**Descriptions and stage metadata — enrichment, not completeness.** Read frontmatter where the files
are reachable; otherwise use whatever descriptions the listing still carries; otherwise absent.

**Absent enrichment means tier 2, never omission.** A skill with no available description cannot be
promoted to tier 1 (which needs one) — it still appears by name in tier 2. The output shape absorbs
a thin catalog without breaking rule 1.

**Disclose a degraded pool.** When the pool came from rung 3, or enrichment was unavailable, say so
in the output. Presenting a truncated pool as complete is the green-with-hidden-findings failure
`docs/conventions/liveness-assertion/` (in the consuming marketplace) exists to forbid: a surface
fails loud or routes its findings somewhere visible — never both green and silent.

## Read the trajectory

**Durable state is the primary signal; the conversation is secondary.** This inverts the intuitive
order for a reason: a long session is exactly when the operator most needs this skill and exactly
when the conversation is least reliable, because compaction drops the early turns and re-attaches
only the most recent skills.

**Do not build a probe.** `/session-flow:orient` already reads branch and git state, handoff
save-points, workflow checklists, running-retro ledgers, open PRs, and work-items — a superset of
what this skill needs, in this plugin. Invoke it, or consume its briefing if it already ran this
session. Seven session-flow skills already inline near-identical probe blocks; an eighth copy is the
duplication `/discipline:point-dont-copy` forbids.

**Slug selection** for artifact-grounded reads: an explicit argument wins; else the
most-recently-modified topic slice; else the branch-derived slug. Resolve every path through the
plugin's topic-docs binding
([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)) —
the memory and contract roots are configurable, so never hardcode them.

**When the memory root is unreadable or empty — say so; do not infer.** In a worktree, a sibling
lane, or a fresh clone the memory slice is invisible, so *every* upstream artifact reads "absent".
Inferring from that would announce that the operator skipped every upstream stage, which is the
opposite of the truth. Report `cannot ground upstream stages here` and leave the bucket empty with
that reason.

## The four buckets

Full derivation rules and rendering: [`context/buckets.md`](context/buckets.md).

| Bucket | Holds |
|---|---|
| **Now** | Fits the current moment |
| **Next** | Two or three steps ahead on the trajectory |
| **Skipped upstream** | Stages upstream of the detected position **whose output artifact is absent on disk** — artifact-grounded, never inferred from conversation |
| **Spotlight** | Exactly three, ordered least-recently-surfaced |

`Skipped upstream` is deliberately artifact-grounded: "everything upstream" is definitionally the
whole early catalog and carries no information. `workflow` already sets this precedent — verify a
stage from its artifact, not from conversation vibes.

`Spotlight` exists because ranking alone re-shows the same five skills forever, which serves a
decision but teaches nothing. Rotation forces encounters with different corners of the catalog over
time. It reads and writes one small ledger of what it last surfaced, in the resolved memory tier —
accepting that the ledger resets per worktree and per clone, and that concurrent sessions are
last-write-wins. It is deliberately **not** in `${CLAUDE_PLUGIN_DATA}`, which is keyed to the plugin
id and nothing else, so a fixed filename there would be one file per *machine* and a spotlight shown
in one repository would suppress it in another.

## Render two tiers

Per bucket:

- **Tier 1 — at most five, ranked.** Each carries: the invocation name, one line of what it would add
  *to this conversation* (never its generic description), and when you would skip it. Annotations
  ride here.
- **Tier 2 — everything else in that bucket, by bare invocation name, with an explicit count.**
  `Also live now (23): /a:b, /c:d, …`

**Budget: the whole output stays around 60 lines.** Measured evidence for the cap: the one-tier form
of this same design rendered 139 options across 275 lines — 97.8% of the catalog, i.e. the generated
cheat sheet with an extra column, which an operator reads once and never again.

One word expands any tier-2 roster to full treatment (`expand now`, `spotlight all`). That is
progressive disclosure, not filtering: nothing was withheld, only deferred a keystroke.

## Boundaries — four neighbours, four different jobs

- **`/session-flow:workflow`** answers *which stage comes next* and routes to **exactly one** owner,
  by its own mandate never presenting both and leaving the operator to disambiguate. That rule
  governs **stage** routing. This skill owns **option surfacing** — the whole set, ranked, for a
  human to pick from. Reach for `workflow` when you want a decision; reach here when you want the
  menu.
- **`/session-flow:orient`** reports *where you stand* and deliberately prescribes nothing. This
  skill consumes that position rather than restating it.
- **`/discipline:use-your-skills`** corrects the **model's** drift — a skill it should have fired and
  did not. This addresses the **human's** awareness. Different subject entirely.
- **The handoff document's §14 "Suggested skills"** already recommends fully-qualified skills tied to
  remaining work. That is a durable artifact written for a cold reader resuming later; this is a live
  ephemeral menu for the operator right now.

## What this skill does NOT do

- **Does not decide.** It ranks and annotates. Picking is the operator's.
- **Does not filter by merit.** "Already done" and "unnecessary" never remove an option — see the two
  rules. A design that ranks-then-truncates reintroduces the same gatekeeping through the cutoff.
- **Does not invent names.** A thin catalog yields a short menu, never a plausible one.
- **Does not build its own durable-state probe.** It routes to `/session-flow:orient`.
- **Does not execute what you pick.** Presentation only; invoking the choice is a separate act.
- **Does not enumerate a catalog in its own body.** The candidate set is resolved at runtime; an
  embedded inventory would be a permanent token cost that rots as the fleet changes.

## Gotchas

- The listing's drop-order is *least-invoked first*, so the skills most worth surfacing are the ones
  whose descriptions vanish first. Sourcing names from the listing alone quietly inverts this skill's
  purpose.
- A skill set to `"off"` via `skillOverrides` still appears in a catalog but cannot run. Recommending
  it hands the operator a dead option — annotate it if the override is visible.
- Built-in commands other than a small allowlist are not `Skill`-invocable. They can be *named* as
  options (`/compact`, `/clear`) but not invoked on the operator's behalf; say which is which.
- An empty bucket is a real result and says so, with its reason. Silence reads as an oversight.
