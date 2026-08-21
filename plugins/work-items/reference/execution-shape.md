# Execution shape — per-container PR topology and journey vocabulary

One spec container = one macro journey (discovery → planning → implementation → review across
sessions), with micro cycles of the same phases inside each work item. How that journey reaches the
default branch is the container's **execution shape** — a per-container choice, never a repo-level
config (a repo runs both shapes at once: one effort ships per-item PRs while another ships a single
integration PR, and a repo-wide setting would force one topology on all efforts). This document is
the SSOT for the shape line's grammar, the two shapes' disciplines, and the journey vocabulary;
`/work-items:decompose` records the line, `/work-items:ship` reads it and states the active
discipline, and `/work-items:work` executes items under it.

## The shape line

The choice is recorded as one durable line in the **container body**, appended after the Brief
sections when the container is published (or added later by an ordinary body edit through the bound
adapter):

```markdown
**Execution shape:** per-item PRs
```

or

```markdown
**Execution shape:** integration branch → single PR
```

- Exactly one line, matched by its bolded `**Execution shape:**` prefix; the value is one of the
  two strings above.
- **Absent line = `per-item PRs`** (the default). A reader applying the default says so loudly —
  "no execution-shape line; per-item PRs assumed" — and offers to record the line rather than
  leaving the default implicit forever.
- The shared-branch shape needs one more durable fact: **which branch**. A sibling line directly
  under the shape line records it — `**Integration branch:** <branch-name>` — written when the
  shape is chosen (the branch is named at the same approval follow-up) or backfilled by the first
  session that provisions the branch. A fresh session (cloud or local) resolves the shared branch
  from this line, never from convention or guesswork; when the line is absent, a reader says so
  and offers to record it before any work joins the branch.
- The line is data in an item body like any other item text — the item-content-trust boundary
  applies. It selects between two documented disciplines; it never widens authority, and any other
  value is reported as unrecognized (fall back to stating both disciplines), not obeyed.

## The two shapes

### `per-item PRs` (default)

Independent, parallelizable items; each item is its own micro journey to the default branch.

- Each item gets its own branch (and worktree, on the `/work-items:work` path) provisioned from the
  default branch; its PR closes the item (`Closes #N` via the branch-name linkage).
- Items without dependency edges between them may run in parallel — separate branches are the
  isolation mechanism, and the seam claim (assignee + lease) is the collision signal between
  concurrent lanes.
- Verification is per-item (the item's own gates) plus the macro close-out review when the
  container's last sub-item closes.

### `integration branch → single PR`

Sequential checkpoints on one shared branch; the journey ships as one PR at the end.

- One integration branch (recorded in the container's `**Integration branch:**` line) hosts the
  whole journey; items are closed **sequentially** as work lands on it, each closure a
  checkpoint. No per-item PRs; the single PR at the end carries the journey and the container's
  close-out.
- **Shared-branch discipline** (this is what makes distributed cloud + local execution on the same
  branch safe): claim each item via the seam before working it even though work is sequential —
  two sessions (a cloud agent and a local machine) can legitimately share the branch, and the
  claim, not the branch, is the collision signal; renew the lease mid-flight on long items; pull
  before starting an item and push before closing it, so every checkpoint is durable and the next
  session (or machine) starts from it.
- **One item in flight at a time.** Sequentiality is enforced by the claim check, not assumed: a
  shared branch cannot host two concurrent checkpoints, so an active claim on **any** sibling
  sub-item defers new claims on this container — even of an independent frontier item — until the
  active item closes or its lease is reclaimed. Per-item leases alone do not serialize a shared
  branch; this container-scoped check is what does.
- **Closing a checkpoint records durable progress, not shipment.** The item closes when its work
  lands on the integration branch — that is the checkpoint contract (safe to clear context, next
  session resumes from it) — while shipment is the **container's** close: single PR merged plus
  the close-out review. An integration PR that fails review or is abandoned leaves the container
  open with its closed checkpoints intact, which is exactly the recoverable signal — the journey
  reads unfinished at the container even though its items are closed.
- Green is promised at the end: intermediate checkpoints keep the integration branch coherent, but
  full verification gates run before the single PR merges (plus any per-checkpoint gates the
  project's workflow defines). When the **last** item closes, the journey's terminal step is
  opening that single PR from the integration branch (`/source-control:pull-request` when
  installed) and running the full gates; the container's close-out runs at PR time and the
  container closes only when the PR ships.
- The standard `/work-items:work` path provisions worktrees from the default branch and opens
  per-item PRs, so items in this shape are worked on the shared branch directly (operator-driven),
  not through that path — the same caveat `/work-items:decompose` records for its
  integration-branch fallback items.

## Vocabulary

Canonical journey terms (resolved 2026-08-17). The marketplace-wide glossary write is **no longer
deferred** — `docs/GLOSSARY.md` landed 2026-08-20 (#3062) and declares itself repo-wide. Of the
three terms below, **`phase boundary` has been promoted there and this file no longer defines it**;
`work item` and `checkpoint` stay reference-local, because both are specific to this seam's
execution shapes rather than repo-wide vocabulary.

**Work item** (short: **item**)

A node in the dependency graph, phase-agnostic — it exists identically through planning,
implementation, and review. *Ticket* and *issue* are first-class invocation synonyms, not separate
concepts.

**Checkpoint**

An item closed within a shared-branch (`integration branch → single PR`) flow: progress durably
recorded on the branch and in the tracker, safe to clear context and resume — from any machine.
An item is always a graph node; it is a checkpoint only in a shared-branch flow.

**Phase boundary** — defined repo-wide in [`docs/GLOSSARY.md`](../../../docs/GLOSSARY.md), not here.

This file used to carry its own definition ("the session-level decision moment between phases of
work"), which diverged from the glossary's once that landed. Two definitions of one term, one of
them in a file claiming repo-wide authority, is worse than either alone — so the definition is
ceded and only the seam-specific relation is kept: a checkpoint is a phase boundary with durable
progress, and not every phase boundary is a checkpoint (a mid-item pause that hands off
uncommitted context is a phase boundary and no checkpoint).

Avoid: *milestone* (untracked, no graph node), *stage* / *step* (ambiguous between item and phase
boundary), *sub-issue* as a distinct concept (it is an item that happens to have a parent).

## Consumer configurability

- The shape is chosen at `/work-items:decompose`'s existing approval gate (one-line prompt when a
  container publish is approved) and lives in the container body — per-container, team-visible,
  editable later by an ordinary body edit. No repo-level or plugin-level topology setting exists.
- The container label a reader uses to discover containers resolves from the binding
  (`config.container_label`, default `work-map` — CONTRACT.md "Containers and state"); nothing in
  this document introduces a new fixed label, path, or filename.
- Phase machinery is composed presence-gated: planning close-out, review machinery, and
  session-flow skills are routed to when installed, with documented manual fallbacks when not.
