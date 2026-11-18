---
bump: minor
---

### Added

- **`loosened_check_decision_record` setting.** An optional https URL prefix in
  `docs/conventions/review.yaml`, read from the default branch, with no user option. Set, a
  loosening, a removed check and a quarantined flaky test also need the spec to cite the owner's
  decision: a line link under that prefix and the owner's words after `verbatim:`. Unset, no citation
  is needed. When the default branch cannot be read, the citation counts as unmet.

### Changed

- **`/review:quality-gate`, "Fail a change that loosens a check".** A finding asks for the change to
  be undone or for the spec to supply what it lacks, never for an issue to be linked or filed.
- **`/review:code-review`.** A thread's answer or resolution never settles a loosened-check finding,
  and a verifier never rejects one on that ground.
