---
bump: patch
---

### Fixed

- A post-merge report kept from an earlier pr-merge tick is no longer refused as `code-changed` by a commit that only edits whole-line comments, blank lines or trailing whitespace in `docs/conventions/pr-pipeline.yaml`. A block scalar or a quote left open on a line still compares the file as written.
- `babysit_verify_evidence.py settle --idle-tick` reads cheapest first: the report's own refusals before any read, and the two verifying-run listings before the lane room's reuse rule, so a miss either one decides spends none of that rule's reads. Every refusal is kept, and the report checks run again last.
- `settle` prints how the lane room's reuse rule settled (`outcome`, with what moved), so a refused reuse names its cause in the log.
