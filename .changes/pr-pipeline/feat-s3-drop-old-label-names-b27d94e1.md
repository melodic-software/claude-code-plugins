---
bump: patch
---

### Removed

- Lanes, holds and the issue-status model no longer read `status: needs-decision`, `status: needs-info` or `work-class: untrusted-provenance`, and intake no longer reads a proposed work class from the triage comment. A field-only hold now reads as `needs-owner-decision` or `needs-reporter-info`.
