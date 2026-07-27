# Changelog — upstream-drift convention

Notable changes to the upstream-drift contract (SemVer). Changing a required part, the canonical
name, or an enforceability verdict is a major bump; additive guidance is a minor bump; docs-only
clarification is a patch.

## 1.0.0 — 2026-07-26

Initial published contract
([#1638](https://github.com/melodic-software/claude-code-plugins/issues/1638)): one name (recheck
trigger) and one shape (dated verification stamp + observable recheck trigger) for records derived
from upstream-owned sources.

- Canonical name adopted from `melodic-software/standards`
  `conventions/engineering/documentation-and-citations.md`; "revisit trigger", "re-derivation
  trigger", and "what would reopen it" become superseded synonyms that migrate on touch.
- Required parts fixed: claim/decision, basis, as-of date, recheck trigger; observability bar
  stated; date-is-never-authority rule stated.
- Drift-signal finding recorded: no `ETag` and no per-page `Last-Modified` on the official docs'
  raw-markdown endpoints (verified 2026-07-26 by header inspection), so content hashing is the only
  viable mechanical drift signal; the fleet defers building a hash store, with its own recheck
  trigger.
- Enforceability classified per `enforceability-tiers.md`; the stamp-carries-trigger presence check
  named as the one deterministic candidate, deferred per the routing rule.
- Migrated citing surfaces: hook-config-delivery, ecosystem-commands, loop-lane, topic-docs,
  PLUGIN-PHILOSOPHY (component stances + registry row), OFFICIAL-DOCS, MIGRATION-PLAYBOOK.
