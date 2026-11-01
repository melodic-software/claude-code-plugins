---
description: "Ranked menu of every installed skill that fits this moment (Now, Next, Skipped upstream, Later, Spotlight), hiding nothing. Use when: 'what are my options', 'which skill fits here', 'what am I forgetting'. One next stage: /session-flow:workflow."
argument-hint: "[topic-slug]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Lay out the skills that fit this moment as a ranked, nothing-hidden menu
---

**Arguments.** `[topic-slug]`. e.g. /session-flow:recommend-skills, /session-flow:recommend-skills my-topic

# Recommend skills

**The human decides.** This skill's judgment goes into *rank* and *annotations*. It never goes into
*presence*.

## The two rules

1. **Never omit a candidate's name.** Not because a step looks already done, not because it looks
   unnecessary, not to keep the output short. A skill the evidence says already ran is ranked
   normally and annotated `(ran this session)`. The one exception is the operator's own exclude
   setting (below): the states it names are dropped, and the output says which.
2. **Never invent a candidate.** Every name rendered must come from the resolved catalog. A thin
   source yields a short menu, never one filled with plausible-sounding names: a menu that routes
   to something that does not exist is worse than a short menu.

### Omit irrelevant, never unnecessary

The output size turns on this test:

- **Irrelevant → omit.** The skill's *domain* does not apply to this session at all: songwriting
  skills in a code session, Kindle tooling in a research session. No reasonable operator would
  consider it.
- **Unnecessary → keep, annotate.** The skill's domain applies and the operator *could* reasonably
  run it; the model merely believes they need not. That belief is an annotation.

When unsure which side a candidate falls on, it is unnecessary. Keep it.

## Resolve the candidate set

Two separate needs, resolved separately. Detail, formats, and failure behavior:
[`context/candidate-ladder.md`](context/candidate-ladder.md).

**Names. Completeness is a correctness property.** The in-context skill listing is *not* an
acceptable sole source: it is budgeted and does not carry every skill, and our premise is that
the skills an operator has forgotten are the ones it serves worst (pointer record and live
sections:
[candidate-ladder § Why the in-context listing cannot be the sole source](context/candidate-ladder.md#why-the-in-context-listing-cannot-be-the-sole-source);
as of 2026-10-11; recheck trigger: that section's pointer record or its recheck trigger
changes). Ladder:

1. The skills index from `/harness-ops:inventory`, if that plugin is enabled: invoke it via the
   Skill tool, asking for its Skills index (`--skills-index`) on stdout, with `--exclude` only
   when the exclude setting below names states. It
   prints one JSON record per skill from its frontmatter, `enabled`, `disabled` and
   `not-installed` alike; reuse it rather than walking the plugin cache, whose layout is
   undocumented and version-keyed. **Read its output from stdout, never pass `--out` into the
   consuming project**: this skill writes nothing but its Spotlight ledger. A `disabled` record is
   named with a `(disabled)` annotation and a `not-installed` one with `(not installed)`, never
   listed as runnable and never silently dropped. **Done when** the returned set contains at least
   one `enabled` skill absent from the in-context listing, proving it reached past the listing's
   blind spot;
   if it returns nothing usable, fall to rung 2.
2. An operator-supplied catalog file, when the consuming project provides one. **Done when** a
   declared catalog path resolves and parses; if the project declares none, fall to rung 3.
3. The in-context listing. Last resort. **Done when** the pool is built *and* the output carries
   the truncation disclosure; a pool from this rung without that line is an incomplete result, not
   a finished one.

**Descriptions and stage metadata. Enrichment, not completeness.** The index rows carry each
skill's `description` and `when_to_use`; otherwise use whatever descriptions the listing still
carries; otherwise absent.

**Shortlist, then read.** Assign buckets from each index row's `description` and `when_to_use`,
and shortlist the tier-1 candidates (at most five per bucket). Then read the shortlisted SKILL.md
files where a path is readable: `plugins/<plugin>/skills/<skill>/SKILL.md` in a marketplace
checkout, or `.claude/skills/<skill>/SKILL.md` for a personal or project skill. Their
`metadata.workflow-stage` refines the shortlist's buckets and what each would add here; where no
file is readable, the index row stands in. Read no SKILL.md beyond the shortlist: the rest render
by name.

**Exclude setting.** `recommend_skills_exclude` = `${user_config.recommend_skills_exclude}`. A
value still reading `${user_config.…}`, empty, or `none` is the default: exclude nothing and pass
no `--exclude`. Otherwise it is a comma-separated subset of `disabled` and `not-installed`; pass it
as the index's `--exclude`, and say once near the top which states it dropped. An unknown state is an error to
report, never a guess.

**Absent enrichment means tier 2, never omission.** A skill with no available description cannot be
promoted to tier 1 (which needs one). It still appears by name in tier 2. The output shape absorbs
a thin catalog without breaking rule 1.

**Disclose a degraded pool.** When the pool came from rung 3, or enrichment was unavailable, say so
in the output. Presenting a truncated pool as complete is the green-with-hidden-findings failure
`docs/contracts/liveness-assertion/` (in the consuming marketplace) forbids.

## Read the trajectory

**Durable state is the primary signal; the conversation is secondary.** A long session is when the
operator most needs this skill and when the conversation is least reliable: compaction drops the
early turns and need not keep every skill this session loaded.

- **Pointer**: [Extend Claude with skills § Skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle),
  for which skills compaction re-attaches.
- **As of**: 2026-10-11
- **Recheck trigger**: that section changes what compaction keeps of invoked skills.

**Do not build a probe.** `/session-flow:orient` already reads branch and git state, handoff
save-points, workflow checklists, running-retro ledgers, open PRs, and work-items, a superset of
what this skill needs, in this plugin. Invoke it, or consume its briefing if it already ran this
session.

**Slug selection** for artifact-grounded reads: an explicit argument wins; else the
most-recently-modified topic slice; else the branch-derived slug. Resolve every path from the
memory root (default `.work/`), which is configurable, so never hardcode it.

**When the memory root is unreadable or empty. Say so; do not infer.** In a worktree, a sibling
lane, or a fresh clone the memory slice is invisible, so *every* upstream artifact reads "absent".
Inferring from that would announce that the operator skipped every upstream stage, which is the
opposite of the truth. Report `cannot ground upstream stages here` and leave the bucket empty with
that reason.

## The five buckets

Full derivation rules and rendering: [`context/buckets.md`](context/buckets.md).

| Bucket | Holds | Tiers |
|---|---|---|
| **Now** | Fits the current moment | 1 + 2 |
| **Next** | Two or three steps ahead on the trajectory | 1 + 2 |
| **Skipped upstream** | Stages upstream of the detected position **whose output artifact is absent on disk**. Artifact-grounded, never inferred from conversation | 1 + 2 |
| **Later** | Everything else in-domain: relevant to this project but beyond the Next horizon | **2 only** |
| **Spotlight** | Exactly three, ordered least-recently-surfaced | 1 only |

**`Later` is the catch-all that makes rule 1 true.** Without it, a skill that is in-domain but
downstream, testing and review skills early in a session, fits no bucket and would have to be
dropped, silently breaking the never-omit rule. It renders **tier 2 only**: bare names with a count,
roughly one wrapped line. Anything genuinely out-of-domain is still omitted
under the irrelevant test above; `Later` catches relevance, not everything.

`Skipped upstream` is deliberately artifact-grounded: "everything upstream" is definitionally the
whole early catalog and carries no information. Verify a
stage from its artifact, not from conversation vibes.

`Spotlight` rotates so ranking alone does not re-show the same five skills forever. It reads and writes one small ledger of what it last surfaced. Path and record shape are
fixed in [`context/buckets.md`](context/buckets.md) so two sessions cannot pick different ones and
lose the rotation. It is deliberately **not** in `${CLAUDE_PLUGIN_DATA}`: a fixed filename there
would be one file per *machine*, and a spotlight shown in one repository would suppress it in
another (why: "Verification record: plugin data dir" under
`${CLAUDE_PLUGIN_ROOT}/reference/structure.md#full-path-write-procedure`; as of 2026-10-11;
recheck trigger: that record changes what the data dir is keyed to).

## Render two tiers

Per bucket:

- **Tier 1. At most five, ranked.** Each carries: the invocation name, one line of what it would add
  *to this conversation* (never its generic description), and when you would skip it. Annotations
  ride here.
- **Tier 2. Everything else in that bucket, by bare invocation name, with an explicit count.**
  `Also live now (23): /a:b, /c:d, …`

**Budget: the shape is the cap.** Five ranked options per bucket at three lines each, plus one
wrapped tier-2 line per bucket, is the whole output. Never render every option in full.

One word expands any tier-2 roster to full treatment (`expand now`, `spotlight all`). That is
progressive disclosure, not filtering: nothing was withheld, only deferred a keystroke.

## Boundaries. Four neighbors, four different jobs

- **`/session-flow:workflow`** answers *which stage comes next* and routes to **exactly one** owner,
  by its own mandate never presenting both and leaving the operator to disambiguate. That rule
  governs **stage** routing. This skill owns **option surfacing**, the whole set, ranked, for a
  human to pick from. Reach for `workflow` when you want a decision; reach here when you want the
  menu.
- **`/session-flow:orient`** reports *where you stand* and deliberately prescribes nothing. This
  skill consumes that position rather than restating it.
- **`/discipline:use-your-skills`** corrects the **model's** drift, a skill it should have fired and
  did not. This addresses the **human's** awareness. Different subject entirely.
- **The handoff document's §14 "Suggested skills"** already recommends fully-qualified skills tied to
  remaining work. That is a durable artifact written for a cold reader resuming later; this is a live
  ephemeral menu for the operator right now.

## What this skill does NOT do

- **Does not decide.** It ranks and annotates. Picking is the operator's.
- **Does not filter by merit.** "Already done" and "unnecessary" never remove an option. See the two
  rules. A design that ranks-then-truncates reintroduces the same gatekeeping through the cutoff.
- **Does not build its own durable-state probe.** It routes to `/session-flow:orient`, invoked via the Skill tool.
- **Does not execute what you pick.** Presentation only; invoking the choice is a separate act.
- **Does not enable or install anything.** No `/plugin` or `claude plugin` install or enable
  command, and no edit to `enabledPlugins` or `skillOverrides`, even when the best fit is a
  `(disabled)` or `(not installed)` skill or the operator asks. Name the skill and the command the
  operator would run; running it is theirs.
- **Asks at most one question.** When the trajectory reads too thin to rank, ask the one question
  whose answer would most change the ranking, then render. After the answer, or with no answer,
  render the menu; never ask a second.
- **Does not enumerate a catalog in its own body.** The candidate set is resolved at runtime; an
  embedded inventory would be a permanent token cost that rots as the fleet changes.

## Next

/session-flow:workflow

A menu has no single successor; the workflow router picks the one next stage.

## Gotchas

- A skill turned off via `skillOverrides` can still appear in a catalog but cannot run.
  Recommending it hands the operator a dead option. Annotate it if the override is visible.
  - **Pointer**: [Extend Claude with skills § Override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings)
  - **As of**: 2026-10-11
  - **Recheck trigger**: that section changes what an override value does or which skills it
    applies to.
- Most built-in commands are not `Skill`-invocable. They can be *named* as options (`/compact`,
  `/clear`) but not invoked on the operator's behalf; say which is which (pointer record:
  [continuation § Autonomy: two tiers, each explicitly licensed](../workflow/context/continuation.md#autonomy-two-tiers-each-explicitly-licensed);
  as of 2026-10-11; recheck trigger: that section's pointer record or its recheck trigger
  changes).
- An empty bucket is a real result and says so, with its reason. Silence reads as an oversight.
