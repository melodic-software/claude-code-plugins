---
bump: minor
---

### Removed

- Intake no longer proposes or applies a work class. The triage rubric asks for none, and `apply-verdict` adds no `work-class:` label, swaps or takes off none on the issue, no longer reads the repository's labels, and no longer rewords the lane comment. Untrusted provenance still holds: the `untrusted` flag, or the legacy `work-class: untrusted-provenance` proposal on the lane comment's second line, writes `provenance: untrusted`, and either label on an issue still holds it.
- `admission-rules.json` drops its unread `classes` key.
