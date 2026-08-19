---
description: "Audit whether each installed skill is actually VISIBLE to the model — and diagnose why most of a fleet never gets used. A skill is invisible when its description is dropped by the skill-listing context budget (Claude Code drops descriptions starting with the least-invoked skills, so an unused skill loses the keywords that would let it be matched and stays unused), when frontmatter is malformed or a description is missing, when skillOverrides or a disabled plugin hides it, or when disable-model-invocation keeps it out of context by design. Reports reachability, observed usage, and whether it is losing the budget contest — computing whether the listing overflows from documented settings, and withholding every verdict the data cannot support rather than reporting absence of data as absence of use. Read-only; never disables, deletes, or edits a skill. Use when: 'why do I never use most of my skills', 'why does Claude never suggest this skill', 'are my skill descriptions being dropped', 'is my skill listing over budget', 'which skills can the model actually see', 'which skills are starved', 'I have too many skills to know when to use them', 'audit skill visibility'. Not for: which skills are unused versus their context cost as a one-shot check (Claude Code ships that in /doctor and the Stats tab), repo-authoring listing-budget lint (use skill-quality's check-listing-budget), enumerating what is installed (use /claude-ops:inventory), or reading telemetry infrastructure (use /claude-ops:observability)."
argument-hint: "[--fixture <path>] [--render markdown|json] [--now <RFC3339>] — fixture-driven at this phase"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Which skills the model can actually see, which are starved, and which are unobservable
  cadence: weekly
---

## Purpose

Answers one question: **can the model actually see each of my skills — and if not, why?**

That is the question behind the one operators usually ask, which is *why does most of
my skill fleet never get used?* A skill the model cannot see cannot be chosen, so
"unused" is very often a visibility failure wearing a preference costume.

**Visibility is Claude Code's own term** for this: `skillOverrides` is documented under
"Override skill visibility". This skill audits every way a skill loses it.

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
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-skill-visibility/scripts/audit_skill_visibility.py" \
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
