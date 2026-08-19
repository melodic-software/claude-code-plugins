---
description: "Diagnose why most of an installed skill fleet never gets used — separating skills STARVED by Claude Code's skill-listing context budget (which drops descriptions starting with the least-invoked skills, so an unused skill loses the keywords that would let it be matched, and stays unused) from skills genuinely not wanted, from skills the run simply cannot observe. Computes whether the listing is overflowing at all from documented settings, and withholds every cold verdict the data cannot support rather than reporting absence of data as absence of use. Read-only; never disables, deletes, or edits a skill. Use when: 'why do I never use most of my skills', 'which skills are starved', 'are my skill descriptions being dropped', 'is my skill listing over budget', 'skill adoption', 'which skills are cold', 'I have too many skills to know when to use them', 'audit skill starvation'. Not for: which skills are unused versus their context cost as a one-shot check (Claude Code ships that in /doctor and the Stats tab), repo-authoring listing-budget lint (use skill-quality's check-listing-budget), enumerating what is installed (use /claude-ops:inventory), or reading telemetry infrastructure (use /claude-ops:observability)."
argument-hint: "[--fixture <path>] [--render markdown|json] [--now <RFC3339>] — fixture-driven at this phase"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Separate starved skills from unwanted and unobservable; withhold unsupported verdicts
  cadence: weekly
---

## Purpose

Answers one question: **why does most of my skill fleet never get used?**

Claude Code budgets the model-visible skill listing at a fraction of the context
window (`skillListingBudgetFraction`, default 0.01) and, when it overflows,
**drops descriptions starting with the skills you invoke least** — names always
survive, descriptions do not. A skill at zero usage therefore loses its
description, loses the keywords a request would match against, and stays at
zero. Unused is partly self-causing, and the loop is documented.

So the useful question is not *which skills are unused* — Claude Code already
reports that in `/doctor` and the Stats tab. It is **which skills are starved by
that loop and still wanted, versus genuinely unwanted, versus not observable at
all.**

## The refusal that defines this skill

A usage store younger than the window being asked about **cannot** distinguish
"never invoked" from "never observed". Reporting the second as the first libels
most of a fleet on any fresh install — measured here: a 3-day-old install
against 30/90-day tiers put 210 of 213 skills in a "never used" bucket.

This skill therefore computes an `observed_horizon`, clamps every window to it,
and routes any claim the span cannot support into a first-class `withheld`
section with its reason. **A declined verdict is reported, never omitted.**

## Run it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-skill-starvation/scripts/audit_skill_starvation.py" \
  --fixture <bundle.json> --render json
```

Python 3.11+ is the only requirement — no third-party packages, matching
`inventory.py` and `install_state.py`.

## Reading the output

Three independent fields per skill; a single flat verdict would collapse
questions that demand different actions.

| Field | Answers | Phase |
|---|---|---|
| `observation` | What has actually been seen, within a stated horizon | **live** |
| `reachability` | Can the model ever select this skill | **live** |
| `starvation` | Is it competing for description budget, and likely losing | Phase 3 |

`observation` values: `active` · `cooling` · `dormant` · `no-observation-in-horizon`
· `not-observable`. The last is the default whenever the data cannot support
better, and it is never a synonym for unused.

`reachability` values: `model-reachable` · `user-only` · `hidden` ·
`misconfigured` · `unknown`. Only `model-reachable` with no observation is a
starvation candidate — `user-only` means you type it by design, and
`misconfigured` is a fix. Each carries its causes, evidence, and a remedy.

**The reachability causes are not an official list.** No such list is published;
this catalogue is assembled from scattered documentation plus strings in the
shipped binary, and every row says so in its `provenance`. Do not present it to
a user as documented.

## Counting rules that are not obvious

- **Never sum sources.** Native counters and the JSONL store both record the
  same invocation, so adding them double-counts. At a given instant the count is
  the MAX across sources — while two events from ONE source at the same instant
  still count twice, because those are genuinely two invocations.
- **`pluginUsage` is not a skill signal.** It counts hook, agent, MCP, and LSP
  dispatch, and is seeded at install with `usageCount: 0` beside a current
  `lastUsedAt`. Recency from it is meaningless unless `usageCount > 0`.
- **Ambiguous attribution is reported, not guessed.** Two marketplaces shipping
  a same-named plugin collapse to one usage key; those rows are marked
  `ambiguous-attribution` rather than attributed to one of them.

## Scope boundary

| Question | Owner |
|---|---|
| Why is my fleet unused — starved, unwanted, or unobserved? | **this skill** |
| Which skills are unused vs their context cost, right now? | Claude Code's own `/doctor` and Stats tab |
| Is a repo's authored listing over budget? | `skill-quality`'s `check-listing-budget.sh` |
| What is installed and invocable? | `/claude-ops:inventory` |
| Is the telemetry pipeline healthy? | `/claude-ops:observability` |

Read-only. It never disables, deletes, or edits a skill, and it never
recommends deleting one it classified as misconfigured — that class is a
fix-me, not a removal candidate.

## Gotchas

- **A short horizon is the normal case, not an error.** Fresh installs, new
  machines, and ephemeral cloud containers all produce spans below the exposure
  floor. The correct output there is a withheld verdict, not a smaller number —
  if a run reports most of the fleet as cold on a days-old install, the report is
  wrong, not the fleet.
- **Do not "fix" a fixture that asserts everything is `not-observable`.** That is
  the honesty floor being tested, and it is the defect this skill exists to
  prevent.
- **Never sum two sources.** Native counters and the JSONL store record the same
  invocation; summing them doubles every count. The reconciliation is MAX across
  sources at an instant, and it is deliberately not MAX across an entire skill —
  two same-instant events from one source are two invocations.
- **OTEL and native counts legitimately disagree.** The native counter is
  debounced (one write per skill per 60 s, suppressing the timestamp refresh
  too); telemetry is not. Divergence is expected and must not be reconciled away.
- **`misconfigured` never renders as a removal candidate.** Several of its causes
  are silent misconfigurations — a skill that looks fine and can never be
  selected. The remedy is a fix.
