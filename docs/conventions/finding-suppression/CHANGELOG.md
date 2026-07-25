# Finding Suppression Convention — Changelog

Notable changes to the finding-suppression key contract. Versioned by `contract_version` (SemVer),
governing the keys, the per-entry shape, and the merge form only — the layering axis is versioned
independently by [config cascade](../config-cascade/README.md). Adding or removing a required key, or
changing what an existing key means, is a major bump; adding an optional key or relaxing a rule
additively is a minor bump.

## 1.0 — 2026-07-24

Initial published contract, landing with its first adopter (`claude-config`'s `audit-pass` skill).

- Keys: `suppressions` as a mapping keyed by `finding_id`, each entry storing the finding's
  **constituents** — `check`, `claim`, and every `(surface, anchor)` site — plus required `reason`
  and `date`. An entry missing any required key is reported malformed and does not suppress, as is
  one whose constituents do not hash to its own key: the constituents are authoritative and the key
  is derived from them.
- Merge form: per-key override, declared per the cascade contract's requirement.
- Policy-floor precedence inversion claimed, with the class's third condition — provenance reported
  per entry — stated as a behavioral obligation rather than a declaration.
- Five obligations on a consuming skill: layer resolution, a visible `suppressed` section, four-way
  entry resolution (SAME-UNCHANGED / SAME-CHANGED / OLD-CLOSED-NEW-OPENED / CLOSED, only the first
  silent, with an unaccounted disappearance failing the consumer's own self-check), refusal to write
  into a derived-exclusion path, and never editing a user-scope file.
- Trades recorded: required reason/date against the bare-id precedent, the declined `review`-plugin
  precedent, constituents required from the first contract rather than migrated in later, a one-sided
  change carrying forward as `needs-reconfirmation` rather than being dropped or silently
  re-suppressed, no expiry key, and the Claude-specific location premise.
