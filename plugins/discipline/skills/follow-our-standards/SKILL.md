---
name: follow-our-standards
description: "Re-anchor to your organization's engineering standards, then audit the work in flight against them and correct violations with doc citations. Use when: 'follow our standards', 'follow the standards', 're-anchor to standards', 'does this match our conventions', 'audit against standards', 'you're drifting from our conventions', or at conversation start on a repo governed by shared conventions."
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: situational  # only in a repo that declares standards
  discipline-batch-rank: 60
  workflow-stage: anytime
  summary: Re-anchor to org engineering standards and audit the work in flight
---

# Follow our standards

A drift corrector for alignment to the consuming organization's engineering
standards. The method — re-anchor, audit the work in flight, correct
forward, report, and the tone that firing this is not an accusation — lives
in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to standards discipline.

## Resolve the standards source

The authority is the consuming organization's own conventions; never work
from recall of them. Resolve a readable copy per the method doc's ladder:

1. **The consuming project declares its standards source.** When the
   repo's own `CLAUDE.md` / `.claude/rules/` names where the conventions
   live — a shared standards repository, a docs tree, a conventions
   directory — resolve and read THAT. A local checkout is preferable to a
   remote fetch when one exists; a remote read (via the host's CLI or web
   tree) is the fallback.
2. **No external source declared → the repo's own conventions.** Read the
   conventions the repo carries itself — its `CLAUDE.md`, `.claude/rules/`,
   `CONTRIBUTING`, docs — and re-anchor those.
3. **Nothing declared anywhere → the portable baseline** below.

State which source resolved so the citations are traceable.

## Loading — relevance-routed progressive disclosure

Do not load the whole convention set. Route through its own index — a
top-level `README` or agent-instruction file — and pull only what the work
in flight needs. Discover the applicable docs through that front door
rather than hardcoding a doc map that will drift. Always re-anchor the core
design principles; load a specific convention (testing, naming,
error-handling, domain modelling, and the like) only when the current work
touches it. When the repo you are working in declares its own
design-doctrine docs, add them to the route set and load one when the work
in flight is designing what that doctrine governs.

## The principles this re-anchors

Re-assert the core engineering principles as active for the rest of the
task — as pointers into whatever docs resolved above, read there, not
restated here:

- single source of truth / DRY;
- low coupling and high cohesion;
- change-together-lives-together — the vertical slice;
- SOLID;
- clean, intention-revealing code.

When no convention source resolved, these five are the portable baseline
the audit runs against.

## Skill-specific audit notes

- **Each finding cites the doc it breaks** — path plus the principle at
  issue. A finding without a citation is an opinion, not a standards
  violation: locate it in the conventions or drop it.
- **Respect a managed / locally-owned seam when the standards source
  declares one.** Some standards distributions mark which downstream files
  are upstream-owned (change via a reviewed sync) versus locally
  customizable. When such a manifest exists, never propose editing a
  managed materialization as the source of a change; route it upstream. If
  the source declares no such seam, this note does not apply.
- **Route shared-policy fixes upstream — never silent deviation, never
  silent conformance.** A change that belongs in the shared standards, not
  this repo, is **named and drafted** for that repo's proper change path and
  routed to the human, rather than patched into the downstream copy.
  "Routed" means proposed and OFFERED: name the change, draft it, and offer
  to open the standards PR — do not open that PR yourself without the user's
  explicit opt-in (the plugin-wide outward-artifact gate in the method doc).
  When the work disagrees with a standard, that disagreement goes upstream
  too — do not quietly ignore the standard, and do not quietly comply with
  one you have reason to think is wrong. (This is the upstream-routing path
  that `/discipline:reason-dont-recite` hands a standards disagreement to.)

## What this skill does NOT do

- **Does not design the sync pipeline.** Upstream/downstream sync and
  dedup design are out of scope; this skill only respects an existing
  managed / locally-owned seam when one is declared.
- **Does not open the standards PR itself.** It names and drafts the
  shared-standards change and routes it to the human; opening the PR — or
  any outward artifact — waits on the user's explicit opt-in, mirroring the
  OFFER gate the sibling `/discipline:recheck-against-upstream-deep` applies
  to its work-items routing.
- **Does not fabricate a citation or a violation.** Cite the doc that
  actually resolved; report "conforms" honestly when it does.

## Gotchas

- When only a remote fetch or the portable baseline resolved, cite THAT —
  not an assumed local path a reader might expect, since the standards may
  live in several places.
- The convention set evolves; trust the source's own index over any doc
  list reproduced from memory.
