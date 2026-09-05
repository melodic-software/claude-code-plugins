# ranking — WSJF-style scoring, confidence mapping, instrument-first, dedupe order

How candidates from every dimension compete in one ranked list. The output contract (row shape,
highest value-to-effort first) lives in SKILL.md; this leaf is the scoring mechanics.

## Value-to-effort: cost of delay against job size

Rank each candidate on its **cost of delay against its job size** (the WSJF shape: cost of delay
= value + time criticality + risk reduction/opportunity enablement):

| Component | Question |
|---|---|
| Value | What does fixing this win — for users, operators, or the team? |
| Urgency (time criticality) | Does the cost grow while it waits? Is a window closing? |
| Risk reduction | Does it retire a failure mode, flakiness, or a class of toil? |
| Job size | S / M / L — the same band the row publishes |

Weigh the three cost-of-delay components together against the size band and order the list by
that judgment. A large candidate leads only when its cost of delay is correspondingly larger.

Rules that keep the ranking honest:

- Compare candidates against each other in this run, not against an absolute bar, and re-rank
  every run (a recurring sweep re-ranks; rankings are not sticky).
- The size band (S/M/L) is also the row's published size; when a size-band narrowing
  (`--small` / `--medium` / `--large`) is in effect, filter before ranking — with ONE
  exemption: the instrument-first candidate (below) is never filtered out by the band. When the
  target is unmeasured, that candidate is surfaced and top-ranked regardless of the requested
  band, marked `outside requested band` when it is — the hard rule wins over the filter, never
  silently the other way around.
- The value-to-effort *rationale* in the row is the one-line justification naming which
  components drive the placement.
- Ties break toward the stronger evidence rung.

## Evidence strength → confidence (aligned to SKILL.md's ladder rungs)

Confidence is a function of the evidence rung, stated plainly in the row — it tempers the
cost-of-delay estimate, never inflates it:

| Rung | Evidence class | Confidence label |
|---|---|---|
| 1 | Measured telemetry (Tier 1/2 sources) | high |
| 2 | Repo and CI history (hotspots.md, ci-health.md, dependency staleness) | medium-high |
| 3 | Structural presence signals (coverage presence, TODO density, missing automation) | medium-low |
| 4 | Model judgment (this session's read of the target) | low — always labeled "judgment" |

A candidate cites the *best* rung it actually has; mixing rungs in one citation is fine
(`churn rung 2 + judgment rung 4`) but the confidence label follows the weakest load-bearing
piece. Evidence gaps never lower a candidate's rung retroactively — they are recorded as
gap lines so the reader knows what the ranking could not see.

## The instrument-first rule

When the target has **no measurement above rung 4** anywhere (no telemetry, no usable repo or
CI history), the top-ranked candidate becomes the instrumentation itself: a concrete proposal
naming *what to measure*, *where the signal lands*, and *which rung it unlocks for future
runs*. Examples: add a baseline CI workflow (unlocks rung 2 CI health per ci-health.md),
unshallow the clone (unlocks rung 2 churn per hotspots.md), configure a Tier 2 telemetry
source (unlocks rung 1).

A single dimension missing its measurement is not this rule. That is an ordinary evidence gap:
record the `gap:` line, rank the dimension's candidates on the rung they do have, and propose
instrumentation for it as a normal candidate competing on value-to-effort like any other.

With no measurement at all, creating the measurement is the highest-value move, because it
unlocks every future ranking. The instrumentation candidate is handed to the pipeline like any
other improvement: it is not a disclaimer, it is the recommendation.

Ranking it: value and risk-reduction inherit from what the missing measurement would rank
(usually high); size is typically S or M. That is why it genuinely rises to the top rather
than being pinned there artificially.

## Dedupe and dismissed-candidate memory — consultation order

Two memories are consulted, in this order, and they answer different questions:

1. **Dismissed-candidate memory first, during candidate assembly** (both modes). Read the
   dismissed memory keyed alongside the reports (home and shape: unattended.md) and suppress
   matching candidates before ranking is presented or any filing happens. It is checked first
   because it is local and cheap, and because a dismissed candidate must never consume a
   filing-cap slot or trigger a tracker query. Suppression is a soft default: the invocation
   prompt can override it ("include previously dismissed candidates"), and the report notes
   how many were suppressed.
2. **Open-work-item dedupe at filing time, per candidate.** Before filing (unattended) or
   offering to file (interactive), run the tracker's search-before-create pre-flight —
   `work-items:track`'s add action carries it (adapter "Search items", `--state all`). Run the
   search *before* spending a cap slot, so a duplicate never counts against the adaptive
   filing cap. A match means skip-and-note in the report (filing duplicates is a bug, not a
   tuning knob), not silently drop.

The order matters: memory prunes the candidate set; tracker dedupe guards each individual
filing. Reversing it wastes tracker queries on candidates the operator already said no to.
