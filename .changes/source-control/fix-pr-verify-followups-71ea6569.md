---
bump: minor
---

### Added

- The pr-merge lane escalates a verifier refusal that needs a human (`verify:earlier-fail`, `verify:too-old`, `verify:untrusted-spec`, `verify:spec-changed`) once `merge.report-only` is false: it adds the tracker's human-gated role label to the pull request when absent and keeps one `<!-- babysit-merge-verify-escalation -->` comment naming the refusal and the head, so a rerun writes nothing. While report-only holds it only reports.

### Fixed

- The verdict reader keeps a failed artifact listing for the gate run, so an outage refuses every queued entry `verify:unreadable` without paging the listing again for each.
- With several pass verdicts at one head, each is checked and all must allow, rather than only the first the listing returned.
- The dependency-manager exemption for a queued entry requires a `Bot` account, not only a dependency manager's login; pr-verify's resolver skips on the same rule.
