# Ingest deferred-with-trigger decisions

This document owns the deferred-with-trigger records that outlived the
`docsite-digest` contract-slice Brief (the Brief governed `map-corpus` authoring;
the slice pruned after the skill shipped). None of these is actionable until its
named trigger fires. Re-check each trigger — and re-measure item 3's cost —
before treating an item as actionable.

Operational surfaces (`map-corpus` Phase 1 stop behavior, gate messages, non-goals)
state what a run must do today. This document is the durable record of *why* those
surfaces stop short, and of the three Broader ingest questions the Brief also
deferred. Source: GitHub issue #2707 (filed so the records survive Brief prune).

## 1. Discovery rung 3 (in-page link extraction) and the `firecrawl` seam

**Label (authoring):** Q19. **Arbiter:** USER-RESERVED.

`map-corpus` discovery is rungs 1–2 only (`llms.txt`, sitemap); an origin seed
resolving neither stops loudly. Rung 3 has an unresolved design fork: a
presence-gated `/firecrawl:firecrawl map` call with a documented in-skill
fallback, versus a recorded reason the skill reimplements in-page link
extraction. `firecrawl` already ships `map <url>` (URL-only discovery) and
`crawl <url>`, but the design boundary bars a bare unguarded cross-plugin
reference and `dependencies` are reserved for hard requires.

**Trigger:** the first corpus whose seeds resolve neither an `llms.txt` nor a
sitemap, so rung 3 is actually reached. The answer changes the mapper's
constraints and prerequisite set, so the user arbitrates it.

## 2. Repository-tree enumeration rung

V1 ingress for repository files is human-enumerated **resource seeds** (a
non-root seed URL is itself a corpus resource, rung `seed`, no discovery at its
origin; GitHub files seeded in `raw.githubusercontent.com` form because a `blob`
URL snapshots HTML chrome). The first corpus hand-enumerated its 12 spec-repo
blobs. A `git ls-tree` / tree-API enumeration rung is deferred.

**Trigger:** the first corpus whose repository half is too large to enumerate by
hand.

## 3. Renaming `docpage-digest`

Deliberately out of scope for the mapper: the skill keeps its name and its
`docpage-digest-checklist.md` filename, which is load-bearing for run identity —
a rename makes every existing work slice present as "no URL recorded", and the
skill's collision check then permanently refuses to resume them.

**Trigger:** an orchestrator that justifies the cost. **Cost measured at the time
of deferral** (2026-08, re-measure before acting): 48 occurrences across 14
tracked files; a two-plugin change with two CHANGELOG entries and two version
bumps; a regenerated `docs/CATALOG.md`; 24 CHANGELOG occurrences that must
**not** be rewritten; an unresolved question about ADRs 0006 and 0007 citing the
live path; and an explicit migration of 14 live work slices.

## 4. Retrofitting sibling ingest skills to a shared ingest-slice contract

Retrofitting `youtube-digest`, `course-digest`, and `book-distill` to a shared
ingest-slice contract was rejected for now on evidence, not preference: their
input contracts, human-interaction points, terminal artifacts, and git posture
diverge — `youtube-digest`'s slice artifacts are a committed durable substrate,
the opposite of the mapper's untracked, self-ignoring root.

**Trigger:** a shared web-scoped ingest-slice contract existing first (item 5's
prerequisite).

## 5. Cross-type routing

A webpage's embedded YouTube video routing into the YouTube pipeline. Today such
a URL is classified `companion` for the interview and never dispatched to a
sibling pipeline.

**Trigger:** the ingest-slice contract is authored web-scoped first; routing
waits for it.

## Disposition

No trigger has fired as of the filing of #2707. This document is preservation,
not a work queue. Closing #2707 means the records live here; it does not mean
any trigger has fired.
