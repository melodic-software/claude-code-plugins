---
bump: patch
---

### Fixed

- The pr-merge gate no longer holds a pull request at `verify:earlier-fail` after its link changed from `Refs:` to closing the issue and the verifier passed the new head. An earlier FAIL at a head of the same change now clears when every counted pass at the head records `spec_kind` `closes` and every counted FAIL at that head records `spec_kind` `refs` for this pull request with a linked issue: a closing pass is judged against the whole spec, which includes the slice that failed. A `refs` pass after a `closes` FAIL, two verdicts of the same kind, a missing or unknown `spec_kind`, and a FAIL record that cannot be read, records no linked issue, or records another pull request, head or verdict all keep the refusal. Every other refusal is unchanged.
