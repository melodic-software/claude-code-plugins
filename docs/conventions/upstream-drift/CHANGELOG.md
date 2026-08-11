# Changelog — upstream-drift convention

Notable changes to the upstream-drift contract (SemVer). Changing a required part, the canonical
name, or an enforceability verdict is a major bump; additive guidance is a minor bump; docs-only
clarification is a patch.

## 1.2.0 — 2026-08-10

Adds [§Reading the basis — the fetch route](README.md#reading-the-basis--the-fetch-route): a rung
ladder for reading an upstream page the firing procedure already tells you to re-fetch. No required
part, canonical name, or enforceability verdict changed — the four parts and the observability bar
are untouched; this says how the basis is read, which every firing already depended on and no
surface owned.

- **The failure the rung ladder closes is a false negative, not a fetch error.** A summarizing fetch
  of a long page truncates, and a summarizer then answers "what does this page contain" from the
  truncated span — an answer indistinguishable from genuine absence. `env-vars` produced exactly
  that on three independent fetches. Two rules bind every read regardless of rung: no verbatim
  quote, no claim; and a truncated read supports no absence claim, ever.
- **Rung 1 — `curl` the `.md` channel and search the file locally — is the default**, verified
  against `env-vars` on 2026-08-10 (361,797 bytes, 458 lines, 315 variable rows including the
  `CLAUDE_CODE_MAX_*` range that had truncated away three times; two fetches, identical SHA-256).
  Rung 2 is a summarizing fetch, admissible only when the read shows the page arrived whole. Rung 3
  is a verbatim mirror.
- **The route is hoisted, not invented — from two surfaces that derived it independently.**
  `claude-ops`'s `changelog` skill carried it page-scoped; `knowledge`'s `docpage-digest` publisher
  profile carried it claim-scoped, binding absence-establishing fetches to `curl` on the raw `.md`
  channel after two of its own runs asserted a false absence. Two independent derivations is the
  signal a rule wants an owner, and the one-owner-per-concern rule puts the general form here while
  leaving their scope-specific detail with them. The profile's warning that a raw-markdown channel
  can 404 per page is carried across as the reason a run verifies the channel before trusting the
  rung.
- **The mirror rung keeps the freshness-corroboration protocol from
  [#2182](https://github.com/melodic-software/claude-code-plugins/pull/2182)** and generalizes its
  bar: corroborate against a fact the page's own content can only carry after a known upstream
  change, never against the mirror's self-reported sync time. A mirror-based record says on its face
  it is one rung below primary and states retirement of that basis in its trigger.
- **Currency of a rung-1 read is fixed at what the docs actually support** — the fetch date and
  nothing more, because the endpoints publish no per-page content date. The 2026-08-10 fetch
  independently re-confirmed that 1.0.0 header finding: `Last-Modified` came back equal to `Date`.

## 1.1.0 — 2026-08-10

Adopters registry gains a row for
[`PLUGIN-PHILOSOPHY` recorded gate runs](../../PLUGIN-PHILOSOPHY.md#recorded-gate-runs)
([#2175](https://github.com/melodic-software/claude-code-plugins/issues/2175)). No required part,
canonical name, or enforceability verdict changed.

- The new table is the registry's first entry of the **recorded-decision** kind that also carries a
  per-row trigger: each row states the observable event for its own verdict, rather than the
  divergence-at-fetch trigger the component-stances and `OFFICIAL-DOCS` rows share. The row says so,
  so a reader does not carry the wrong firing rule across from the sibling table.

## 1.0.0 — 2026-07-26

Initial published contract
([#1638](https://github.com/melodic-software/claude-code-plugins/issues/1638)): one name (recheck
trigger) and one shape (dated verification stamp + observable recheck trigger) for records derived
from upstream-owned sources.

- Canonical name adopted from `melodic-software/standards`
  `conventions/engineering/documentation-and-citations.md`; "revisit trigger", "re-trigger",
  "re-derivation trigger", and "what would reopen it" become superseded synonyms that migrate on
  touch.
- Required parts fixed: claim/decision, basis, as-of date, recheck trigger; observability bar
  stated; date-is-never-authority rule stated.
- Firing procedure stated per record kind: four-part records re-fetch their cited basis and refresh
  their date; named triggers on in-repo decisions re-derive from the state the trigger names.
  Read-time validation is distinguished from a firing — a lookup that finds no drift obliges no
  edit; divergence at fetch is what fires.
- Drift-signal finding recorded: no `ETag` and no per-page `Last-Modified` on the official docs'
  raw-markdown endpoints (verified 2026-07-26 by header inspection), so content hashing is the only
  viable mechanical drift signal; the fleet defers building a hash store, with its own recheck
  trigger.
- Enforceability classified per `enforceability-tiers.md`; the stamp-carries-trigger presence check
  named as the one deterministic candidate, deferred per the routing rule.
- Migrated citing surfaces: hook-config-delivery, ecosystem-commands, loop-lane, topic-docs,
  PLUGIN-PHILOSOPHY (component stances + registry row), OFFICIAL-DOCS, MIGRATION-PLAYBOOK. The
  adopter table states per row what the surface carries: conforming four-part records, named
  triggers on an in-repo decision, or deliberately trigger-less terminal exclusions.
