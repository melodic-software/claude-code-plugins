# Topic-docs placement — where discovery artifacts land

How `/discovery:explore`, `/discovery:research`, and `/discovery:research-deep` — and the
`discovery:explorer` / `discovery:researcher` agents they dispatch — resolve where generated
documents land in a consuming repo. These skills read this one document; none bakes its own paths.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode. This document records only this plugin's
deltas.

The sibling `artifact-protocol.md` defines the shared lifecycle artifact names and producer/consumer
behavior; this binding and topic-docs remain authoritative for their placement.

## What this plugin writes

Discovery writes **memory tier only** — working documents nothing downstream enforces against:

| Artifact | Location |
|---|---|
| `EXPLORE.md` (+ `EXPLORE-<scope>.md` sidecars and overflow) | `<memory_dir>/<slug>/` (default `.work/<slug>/`) — never committed |
| `RESEARCH.md` (+ `RESEARCH-<topic>.md` sidecars and overflow) | `<memory_dir>/<slug>/` — never committed |

Discovery never writes the contract tier; the `contract_tier` setting does not change where its
artifacts land. The dispatched `discovery:explorer` / `discovery:researcher` agents, and a Tier-2
`research-deep` subagent, all operate under the contract's **non-interactive / forked mode** rule:
they cannot ask, so any assumed destination is flagged in the return rather than silently adopted.

## Visibility (contract ≥ 2.0.0)

These artifacts are memory-tier, so they exist only in the checkout that wrote them. They are
exactly the cross-checkout-useful kind the contract's `.worktreeinclude` template carries into new
worktrees (one-way, at creation time) where the consuming repo materializes it. The contract's
by-value boundary is the checkout, not the process: the `-deep` forks run in the parent's checkout
and write `EXPLORE.md` / `RESEARCH.md` there directly (already visible to the parent), returning a
summary by value; a worker dispatched into its **own** checkout (worktree or background session)
returns findings by value instead, and the parent writes the memory slice.
