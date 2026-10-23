---
bump: minor
---

### Changed

- The pr-merge lane no longer escalates `verify:fail` or `verify:earlier-fail` to a person: both only refuse while an `address-feedback` round answers the fail's notes. `verify:repeated-fail` still escalates, and now wins over a `fail` at the head once fails reach `merge.max-verify-fails`, counting the other pull requests for the same issue, so the round past the cap is not spent. Its escalation quotes the head fail's summary.
- `pull-request comments --ci` lists a `verifier` author: the pr-verify verifier's fail notes for the head, a finding like a `reviewer` body.

### Removed

- The carried-quote rule that kept an earlier `verify:fail` reason in a `verify:earlier-fail` escalation, and that turned an earlier-fail or repeated-fail whose last quote named this head back into `verify:fail`.
