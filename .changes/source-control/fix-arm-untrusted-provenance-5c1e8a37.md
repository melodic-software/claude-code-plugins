---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py evidence --lane-link` now applies the trust hold to the linked issue, so a label naming untrusted work that lands on it after admission, while the lane builds, stops the arm. The issue's labels come with the link's GraphQL read, and its timeline costs one more REST read. A label holding `untrusted` in any case refuses as `untrusted-provenance`, one removed by a non-human or through an App as `untrusted-provenance-removed-by-non-human`, and labels that cannot be read whole as `issue-labels-unreadable`; a failed timeline read refuses as `unreadable:`. Each one is reported as `ineligible`. The checks live in one function, `babysit_merge_policy.trust_refusal`, which `eligibility` now calls too.
