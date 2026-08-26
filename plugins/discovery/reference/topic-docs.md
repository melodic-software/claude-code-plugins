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
| `EXPLORE.md` (+ `EXPLORE-<section>.md` sidecars and overflow) | `<memory_dir>/<slug>/` (default `.work/<slug>/`) — never committed |
| `RESEARCH.md` (+ `RESEARCH-<section>.md` sidecars and overflow) | `<memory_dir>/<slug>/` — never committed |
| `INTENT.md` (+ `INTENT-<section>.md` sidecars) | `<memory_dir>/<slug>/` — never committed |

`INTENT.md` is **private to `/discovery:trace-intent`**: it appears in this table because this is
where the plugin states what it writes, and deliberately **not** in the sibling
`artifact-protocol.md`, because it is not a shared lifecycle kind. Nothing outside this plugin
consumes it by name. Promoting it would oblige an identical edit to five byte-identical copies of
that protocol file plus a version bump, which is a price worth paying for an artifact several
plugins read and not for one that stays here.

Discovery never writes the contract tier; the `contract_tier` setting does not change where its
artifacts land. The dispatched `discovery:explorer` / `discovery:researcher` / `discovery:intent-tracer`
agents, and a Tier-2 `research-deep` subagent, all operate under the contract's **non-interactive /
forked mode** rule: they cannot ask, so any assumed destination is flagged in the return rather than
silently adopted.

## The write boundary — stated once

**This is the single statement of where a dispatched agent may write.** All three agent definitions
point here rather than restating it; three earlier restatements disagreed with each other about
whether scratch was inside the boundary or outside it.

A dispatched `discovery:explorer` / `discovery:researcher` / `discovery:intent-tracer` writes to
exactly these:

| Destination | Who | Notes |
|---|---|---|
| The artifact files — index and sidecars, plus `research-checklist.md` where the family owes one — inside the **memory-slice path named in the dispatch prompt** | all three | the deliverable; only research owes a checklist |
| **Scratch inside that same slice**, named `scratch-<purpose>` (a file, or a directory holding several) | all three | sanctioned: `artifact-protocol.md` lists "scratch" among the memory-tier kinds under `<memory_dir>/<topic-slug>/` |
| The **memory root's** self-ignoring `.gitignore` guard, when it is absent | all three | the one write outside the slice, and the reason the memory root is its own envelope field |

Nothing else. Not repository source, not the contract tier, not another slice, not the consumer's
root `.gitignore`.

**Naming and cleanup are owned, not left open.** Scratch carries the `scratch-` prefix so a consumer
reading the slice can tell a working file from a deliverable without opening it, and so the
acceptance gate — which keys on the `<INDEX>-<section>.md` sidecar contract — can never mistake one
for an artifact. **The run that created scratch deletes it before it returns.** If the run dies
first, cleanup falls to the parent's recovery ladder, which already clears the slice (or assigns a
fresh sub-slice) before any re-dispatch; scratch left in a slice that is being kept is a defect to
report, not to tidy silently.

**The `discovery:researcher`'s session scratch directory is a different place and stays outside this
boundary.** `Bash`-mediated downloads of artifacts too large to fetch in context (`curl` into the
session scratch dir the harness provides) land there, not in the slice. It is not a memory-tier
location, nothing in it is a deliverable, no artifact ever records a path into it, and this plugin
owes it no cleanup. The same applies to `discovery:intent-tracer` where it pulls down a long-form
document too large to read in context. `discovery:explorer` has no equivalent: its Bash is read-only,
so it downloads nothing.

## Visibility (contract ≥ 2.0.0)

These artifacts are memory-tier, so they exist only in the checkout that wrote them. They are
exactly the cross-checkout-useful kind the contract's `.worktreeinclude` template carries into new
worktrees (one-way, at creation time) where the consuming repo materializes it. The contract's
by-value boundary is the checkout, not the process: the `-deep` dispatch resolves to `research-deep`,
whose isolated subagent runs in the parent's checkout and writes `RESEARCH.md` there directly
(already visible to the parent), returning a summary by value; a worker dispatched into its **own**
checkout (worktree or background session) returns findings by value instead, and the parent writes
the memory slice.

**Where that rule is reachable from.** A worker does not choose the by-value mode by reading this
file; it is `persistence: by-value` in the return payload (`agents/explorer.md`,
`agents/researcher.md`, `agents/intent-tracer.md`), and the parent acts on it at the
`persistence: by-value` rung of each family's recovery ladder —
`${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md`,
`${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md` and
`${CLAUDE_PLUGIN_ROOT}/skills/trace-intent/context/dispatch.md`.
The parent writes the slice from the payload's verbatim artifact bodies and then re-runs the
acceptance gate against disk. The mode changes **who writes**, never **whether the gate passes**:
findings returned in place of an artifact are a failed dispatch, not a fallback.
