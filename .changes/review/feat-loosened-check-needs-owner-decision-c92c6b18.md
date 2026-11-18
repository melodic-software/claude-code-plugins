---
bump: minor
---

### Changed

- **`/review:quality-gate`, "Fail a change that loosens a check".** A loosening, a removed check and
  a quarantined flaky test now also need the spec to cite the owner's decision: a line link to its
  row in the owner-decisions record and the owner's words after `verbatim:`. A finding asks for the
  change to be undone or the decision to be cited, never for an issue to be linked or filed.
- **`/review:code-review`.** A thread's answer or resolution never settles a loosened-check finding,
  and a verifier never rejects one on that ground.
