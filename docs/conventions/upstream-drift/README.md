# Upstream drift — verification stamps and recheck triggers

Owner doc for **how this repository records a fact or decision derived from a source it does not
own** — an official doc page, an upstream issue thread, a probed platform behavior — so the record
stays honest as the upstream moves. One name and one shape: a dated **verification stamp** paired
with a **recheck trigger**, the stated observable event that obliges re-deriving the record.

The fleet previously practiced this in five-plus places under three names — "recheck triggers"
([hook-config-delivery](../hook-config-delivery/README.md)), "revisit triggers"
([ecosystem-commands](../ecosystem-commands/README.md), the
[migration playbook](../../MIGRATION-PLAYBOOK.md)), "re-derivation triggers"
([loop-lane](../loop-lane/README.md)) — plus the unlabeled "What would reopen it"
([topic-docs](../topic-docs/README.md)) — with no shared definition of what a trigger must contain
and no statement of what makes one checkable. Under the
[convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry)'s one-owner-per-concern rule
that is the fragmentation this doc closes
([melodic-software/claude-code-plugins#1638](https://github.com/melodic-software/claude-code-plugins/issues/1638)).

## Boundary

`melodic-software/standards` `conventions/engineering/documentation-and-citations.md` owns the
general org-wide rule — upstream bodies are read-on-demand; prefer citing and fetching at read time
over storing a snapshot; a time-bound external claim in durable content needs a recheck trigger —
and this doc takes the concept's name from it. This doc owns the repo-level specialization: the
required parts of a conforming record, the observability bar a trigger must clear, the drift signal
for the doc pages this fleet depends on most, and the enforceability classification. It does not
own:

- **In-repo duplication.** Facts this repo owns are governed by pointer-not-copy
  (`melodic-software/standards` `conventions/engineering/reference-dont-duplicate.md`) and, for
  byte-identical cross-plugin files, `scripts/cross-plugin-source-registry.txt`.
- **Synced materializations.** A `managed` component from the standards distribution drifts and
  reconciles through its reviewed sync-PR pipeline, not through stamps in prose.
- **Where a refreshed outcome lands.** Each versioned convention's own `CHANGELOG.md` records the
  outcome of its rechecks; this doc only requires that the outcome be recorded somewhere durable.

One deliberate tightening, made explicit so it never reads as drift: the org standard accepts "a
date, an automation, or a tracked task" as recheck-trigger forms. The upstream surfaces this fleet
restates move without notice on research-preview cadences, where a bare date decays silently — so
here a date alone does not qualify; a trigger names an observable event (see
[the observability bar](#the-observability-bar)). This narrows only what this repository accepts;
the upstream form list is the org standard's to change.

## A date is never authority

A dated verification stamp is an **as-of record**: it tells the reader when the claim last matched
its source, and nothing more. It never confers standing authority — a stale stamp reads identically
to a fresh one, and upstream surfaces move without notice: Claude Code changes its own conventions
between releases, sometimes with no version signal on the surface in question, and experimental
surfaces churn outright. The load-bearing part of the record is therefore the **trigger**, not the
date: anything restating a volatile upstream specific carries a stated re-derivation event, or it
is drift waiting to happen. Before acting on any stamped claim, re-fetch the cited basis — the
stamp is the ceiling on how current the claim can be, never a guarantee.

The discipline covers two record kinds, one shape:

- a **verified-fact stamp** — a restated upstream specific ("verified 2026-07-17 against \<page>");
- a **recorded decision** — a deferral or rejection derived from upstream facts as they stood on a
  date, whose premises can rot the same way the facts can.

## Required parts

A conforming record carries four parts:

1. **The claim or decision** — what exactly was verified, or what was decided and on what premise.
2. **The basis** — the specific source it was derived against: the official page URL (with anchor
   where one exists), the upstream issue, or the probe/method for an empirical finding. "Verified"
   with no stated basis is not re-checkable.
3. **The as-of date** — when the derivation happened.
4. **The recheck trigger** — the observable event that obliges re-derivation.

Prefer the pointer: where a surface can defer to the live source at read time, cite it and restate
nothing — then no stamp is needed at all. The four-part record is the fallback for surfaces that
must restate a volatile specific to function.

## The observability bar

A trigger names an event whose firing a reader — human or agent — can decide from evidence: a
release or changelog entry touching a named surface, an upstream issue changing state, a capability
shipping or leaving an experimental key, a second consumer appearing, a recurring occasion such as
each fleet audit. "Periodically", "when things change", or an unstated intention to revisit do not
qualify: a trigger whose firing cannot be checked is a date with extra words.

## When a trigger fires

Re-fetch the cited basis and re-derive the claim or decision from what is actually there — never
patch the record from memory. Refresh the as-of date **with the outcome**, drift or no drift. On a
versioned surface the outcome lands as a changelog entry; refreshing a date with no verdict change
is no version bump. Where re-verification finds drift, the changed value lands in the owning
record, never silently in a consuming surface.

## Drift signal — content hashing, deferred

There is no mechanical per-page change signal on the official Claude Code docs: the raw-markdown
endpoints serve no `ETag`, and `Last-Modified` is a deploy/serving stamp rather than a per-page
content date (verified 2026-07-26 by header inspection of three `code.claude.com/docs/en/*.md`
endpoints fetched seconds apart — each returned a `Last-Modified` matching its own fetch time;
recheck trigger: those endpoints start serving an `ETag` or a stable per-page `Last-Modified`).
**Content hashing of a fetched page body is therefore the only viable mechanical drift signal** for
these pages.

The fleet **defers** storing hashes: no upstream-page hash store exists today, and every recheck is
a manual re-fetch at trigger time. Recheck trigger for the deferral itself: a stale stamp causes a
real defect a stored hash would have flagged, or stamped claims accumulate past what manual
re-fetch at audit time covers — at which point a hash store becomes its own designed issue, not an
inline addition here.

## Enforceability

Classified per `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`:

| Judgment | Tier |
|---|---|
| Every verification stamp carries a recheck trigger | **Deterministic** by nature (a presence check) once stamps and triggers use greppable forms. The candidate check — flag any `Verified <date>` line or row whose surface states no trigger — is named but **not built**: per the tiers doc's routing rule, worth-mechanizing defaults to "not yet". Build trigger: a trigger-less stamp lands on `main` again after this doc. |
| The trigger clears the observability bar | **Reasoning-only** — whether an event is decidable from evidence is a judgment about meaning. |
| A trigger has fired | **Reasoning-only** today; **detect-then-judge** if a hash store lands — the hash mismatch flags, and judgment decides whether the page change touches the claim, because a changed page is not a changed fact. |

## Adopters

Migrated at this contract's 1.0.0 — each cites this doc and keeps its content:

| Surface | Was |
|---|---|
| [hook-config-delivery](../hook-config-delivery/README.md) §Recheck triggers | already the canonical name |
| [ecosystem-commands](../ecosystem-commands/README.md) task-runner deferral | "Revisit triggers" |
| [loop-lane](../loop-lane/README.md) §Versioning | "Re-derivation triggers" |
| [topic-docs](../topic-docs/README.md) §Implementers restate the rules | "What would reopen it" |
| [PLUGIN-PHILOSOPHY](../../PLUGIN-PHILOSOPHY.md) component-stances staleness disclaimer | unlabeled discipline |
| [OFFICIAL-DOCS](../../OFFICIAL-DOCS.md) staleness warning and per-row verified dates | unlabeled discipline |
| [MIGRATION-PLAYBOOK](../../MIGRATION-PLAYBOOK.md) decision records | "Revisit trigger" |

Elsewhere the name binds on touch: living surfaces still saying "revisit trigger", "re-derivation
trigger", or "what would reopen it" (several plugin reference docs already use the canonical
`## Recheck triggers` heading) adopt the canonical name and required parts the next time they
change. **History is never rewritten**: `CHANGELOG.md` entries, dated audit records, and ADR
sections keep the wording they shipped with; a new ADR uses the canonical name going forward.

## Why this name

"Recheck trigger" is what the org standard (`documentation-and-citations.md` §"Time-bound external
claims need a recheck trigger") already calls the concept — a repo-level owner doc renaming the
rule it specializes would fork the vocabulary one level up. It is also the majority name in this
fleet, and the `## Recheck triggers` heading is the one the docs-hygiene plugin's audit-noise
section-exemption list already recognizes.

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). Changing a required part, the
canonical name, or an enforceability verdict is a major bump; additive guidance is a minor bump;
docs-only clarification is a patch.

## External authority

- `melodic-software/standards` `conventions/engineering/documentation-and-citations.md` — the
  org-wide read-on-demand rule and the concept's name.
- `melodic-software/standards` `conventions/engineering/enforceability-tiers.md` — the tier
  vocabulary and the routing rule.
- `melodic-software/standards` `conventions/engineering/reference-dont-duplicate.md` — the in-repo
  counterpart this doc's boundary defers to.
