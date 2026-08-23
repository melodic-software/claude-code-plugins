# overengineering

A Claude Code plugin that audits an existing **enforcement surface** — agent hooks and standing
instructions, repository and version-control hooks, CI lanes and gate scripts, branch protections,
forge apps and automations, declared external integrations — and, on explicit request, helps peel
back what no longer earns its cost.

It is the inverse of a gap audit. A gap audit asks what is missing and default-rejects new
automation; this plugin treats **every incumbent mechanism as a retirement candidate until empirical
evidence earns its keep**.

| Skill | What it does |
|---|---|
| `/overengineering:audit` | Read-only walk of the enforcement surface. Reconstructs what each mechanism was built to solve, re-solves the problem fresh with a bias toward native and built-in mechanisms, and returns a verdict argued in cost of carry — KEEP / RETIRE / DOWNGRADE / CONSOLIDATE / UNPROVEN, with security-class artifacts capped at FLAG-FOR-HUMAN. Emits a diffable findings artifact plus an inline summary. |
| `/overengineering:realign` | The only skill that changes anything. Consumes the findings artifact and, per accepted finding, drives interview → explore/research → plan → implement through presence-gated skill composition. Nothing is touched without explicit per-item acceptance. |
| `/overengineering:delta` | The recurring lane. Captures the prior findings spine, re-runs the audit, and reports **only what moved** since the last run — above a configurable noise budget, so a repeat cycle is a short delta instead of the whole surface again. Read-only always; it never enters `realign`, and verdict changes queue for the human. |

The shared method all three skills apply lives once, in
[`context/scrutiny-method.md`](context/scrutiny-method.md); no skill restates it. The artifact that
joins them is specified once, in
[`context/findings-artifact.md`](context/findings-artifact.md).

## Why this exists

Enforcement accumulates. Each hook, gate, guard, and standing instruction was individually
justifiable when it landed, and nothing in a normal workflow ever revisits one. What accumulates is
**carry cost** — the ongoing tax every retained mechanism levies on all subsequent work — and carry
cost is invisible in exactly the place the build cost was visible: the change that introduced it.

Three postures follow, and they are what make the audit different from an opinion:

- **Every verdict cites evidence, or it is UNPROVEN.** Runtime records, version-control and CI
  history, incident records, and operator attestation are evidence. Documentation, headers, and
  rationale comments are **claims to verify** — they may be stale or generated — and a finding whose
  only support is a doc says so in those words.
- **Silence is not exoneration and not proof of waste.** A mechanism with no recorded firings is
  UNPROVEN, never a quiet KEEP and never a quick RETIRE. UNPROVEN items are ranked by carry cost and
  routed to a small, bounded, time-boxed ablation batch instead of an undifferentiated wall.
- **Rediscovery, not critique.** Critique produces a smaller version of whatever is already there.
  The audit reconstructs the original problem and re-solves it today — native mechanism first,
  then an existing mechanism already in the repo, then a narrower incumbent, and only then bespoke
  enforcement.

## The read-only boundary

`/overengineering:audit` reports and never mutates. That is the marketplace's `audit` verb contract,
and here it is also the safety property that makes the plugin runnable on a surface nobody has
reviewed in a year: the worst outcome of a bare run is a file in the memory tier and a wrong opinion.

`/overengineering:delta` inherits that boundary unchanged and adds nothing to it: it composes the
audit, compares two spines, and never invokes or enters `realign` — including when the operator asks
for it mid-run. A lane that can run on a schedule has nobody to give the per-item acceptance realign
requires, so it queues verdict changes instead of acting on them.

Everything that changes the repo happens through `/overengineering:realign`, which is invoked
deliberately, consumes the findings artifact rather than scanning on its own, and stops at a per-item
acceptance gate before every remediation. Its execution order is the method's rollback ladder —
**config-disable first, observe for a window, only then delete with a recorded rationale**. Nothing
in that ladder is autonomous.

## Protected classes

Security-class artifacts — secret and credential guards, destructive-operation guards, guards on the
disabling of other guards, access control, supply-chain integrity, security-scanning lanes, and
externally-constrained audit trails — are **fully audited**. What is capped is the recommendation,
not the scrutiny: a retirement-direction verdict on one of them is emitted as **FLAG-FOR-HUMAN**,
carrying the verdict it would have been and the whole evidence behind it. Keep-supporting evidence is
never hidden by the cap, and where protection status is uncertain, the item is treated as protected.

The set is consumer-configurable — extend it, narrow it, or empty it — through the tracked config
file below.

## Works in any repo

- **Reads your surface, assumes none.** Layers, discovery probes, and evidence sources are resolved
  from what the repository actually has. A shallow clone makes history *unavailable* rather than
  silent, and the report leads with an evidence-availability assessment naming which tiers exist
  here at all — because that changes what UNPROVEN means for every row beneath it.
- **Forge-, CI-, and harness-neutral.** The layer vocabulary is fixed and platform-independent; a
  consumer whose forge, CI system, or agent harness differs still maps onto it.
- **Neighbor plugins are routed to, never re-implemented.** Instruction-text findings, contested
  ablation of an agent's own instruction layer, prospective additions, and plugin claims-vs-reality
  each belong to a sibling plugin. Routing is presence-gated with a documented prose fallback, so no
  step blocks on a plugin that is not installed.
- **Analogical numbers are labeled as such.** No published source states a retirement threshold for
  enforcement surfaces. The thresholds this plugin ships are transfers from alerting and feature-flag
  literature, every row carries that label and its source, and a threshold cited without its label is
  a contract violation rather than a style slip.

## What it deliberately does not do

- **No autonomous retirement.** Every removal is human-reviewed, and protected and
  intentionally-dormant mechanisms — kill switches, break-glass paths, circuit breakers, whose
  designed steady state is never firing — are excluded from ablation by construction.
- **No score.** Verdicts are argued, not summed. A score invites threshold-laundering, which is the
  exact failure this plugin exists to catch.
- **No attack on quality-enabling practices.** Tests, refactoring, review, type checking, and the
  build are out of scope. A finding that reads "delete the tests" is outside the method, and the
  correct response is to say so rather than to argue it on carry cost.
- **No auto-applied fixes.** The findings artifact is deliberately **not** typed as the marketplace's
  auto-applicable review-findings kind. Routing consent-gated realignment through a fix relay would
  launder the per-item human gate that makes this plugin safe to run.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install overengineering@melodic-software
```

## Configuration

This plugin declares **no `userConfig` options**, deliberately. `userConfig` is a personal,
enable-time surface and is not a coordination surface for repository artifacts — and two of this
plugin's settings are policy, not preference: which mechanisms it may never recommend retiring on its
own, and which findings an operator has already judged. A protected set emptied silently in one
operator's personal options would defeat the FLAG-FOR-HUMAN cap for everyone reading that operator's
report, with no diff anywhere to show it happened.

Configuration therefore rides a tracked file in the consuming repo, layered per the config-cascade
convention: `.claude/overengineering.md`, carrying

- the **protected-categories set** — extend, narrow, or empty it;
- **threshold overrides** for the analogical rows, each of which can also be switched off entirely;
- the **observation window** the rollback ladder's rung 2 runs for;
- the **delta noise budget** — what the recurring lane lists rather than counts, per delta class; and
- optional **suppression entries** — the durable record of a judgment an operator has already made,
  shaped by the marketplace's finding-suppression contract and written only behind realign's
  per-item gate.

The protected-set and suppression keys sit in the cascade's policy-floor class: the team-tracked
layer wins a direct conflict, personal layers may extend or tighten only, and a personal
contribution is named in the report. Thresholds, the observation window, and the delta noise budget
take ordinary refinement.

**Keys, values, defaults, and per-key merge forms are owned by
[`reference/consumer-config.md`](reference/consumer-config.md).** All layers absent is a valid state:
the bundled defaults apply and the run says so.

## Running it on a cadence

`/overengineering:delta` is the recurring lane, and it is a **single-pass mechanic**: it runs once,
compares once, reports once, and exits. **This plugin adopts no cadence and ships no schedule
file** — a plugin that scheduled itself on install would be an unratified standing commitment in
somebody else's repository, which is the exact class of thing it exists to find and retire. Four
consumer-agnostic wiring shapes, and the trade each makes, are in
[`skills/delta/context/recurring-wiring.md`](skills/delta/context/recurring-wiring.md).

The property that makes a recurring run worth having is that it **stops re-serving the surface**. The
first cycle establishes a baseline and reports no deltas; every later cycle reports only what moved,
filtered through a noise budget with per-class rules, and a cycle where nothing moved is one line.
Recurrence changes nothing about the read-only boundary: no cadence reaches `realign`, and verdict
changes queue for a human rather than being acted on.

## Where the artifacts land

Both files the plugin writes — the findings artifact, and the spine baseline the delta lane captures
before it re-audits — are memory tier, concern-scoped, branch-keyed, and never committed;
[`reference/topic-docs.md`](reference/topic-docs.md) owns the resolution and the placement of each.
Both are ephemeral by design: the findings artifact is rewritten in place on every re-audit, with
operator judgments carried forward by stable finding id so a decision is never wiped and re-reported,
and the baseline is recaptured each cycle. Judgments that must outlive the branch are persisted as
tracked suppression entries instead.

## Sources

The method's reasoning is grounded in primary sources, cited in full with their qualifiers in
[`context/scrutiny-method.md`](context/scrutiny-method.md):

- [Martin Fowler, "Yagni"](https://martinfowler.com/bliki/Yagni.html) — the four costs, the
  carry-cost frame, and the explicit scope boundary around quality-enabling practices
- [Kohavi et al., controlled-experiment case studies](https://ai.stanford.edu/~ronnyk/ExP_DMCaseStudies.pdf)
  — the base rate behind the default-skeptical posture
- [John Ousterhout, *A Philosophy of Software Design*](https://milkov.tech/assets/psd.pdf) —
  incremental accumulation, and why a single removal reads as no improvement
- [Rob Ewaschuk, "My Philosophy on Alerting"](https://gist.github.com/msgodf/86a3fc7fcd3ce663ff37)
  and the [Google SRE book, ch. 6](https://sre.google/sre-book/monitoring-distributed-systems/) —
  the removal default and the qualitative bar that transfers more safely than any number
- [LaunchDarkly flag-hygiene documentation](https://launchdarkly.com/docs/guides/flags/technical-debt)
  — evidence-gated decommissioning and the two-stage removal order
- [Uber's Piranha (ICSE-SEIP 2020)](https://manu.sridharan.net/files/ICSE20-SEIP-Piranha.pdf) — the
  one industrial-scale precedent for batched, owner-routed retirement, its human-review requirement,
  and the intentionally-dormant finding

## License

MIT (SPDX-License-Identifier: MIT).
