---
bump: patch
---

### Fixed

- A post-merge report kept from an earlier pr-merge tick is no longer refused as `code-changed` by a commit that only edits whole-line comments, blank lines or trailing whitespace in `docs/conventions/pr-pipeline.yaml`. Those are read by the config parser's own rules (`yaml-subset.awk`): lines split on `\n` only, one trailing `\r` dropped, and only a space or tab is a blank. A block scalar, a quote left open on a line, or any other control or line-separator character still compares the file as written, and a change to `yaml-subset.awk` refuses the report.
- `babysit_verify_evidence.py settle --idle-tick` reads cheapest first: the report's own refusals before any read, and the two verifying-run listings before the lane room's reuse rule, so a miss either one decides spends none of that rule's reads. Every refusal is kept, and the report checks run again last.
- `settle` prints how the lane room's reuse rule settled (`outcome`, with what moved), so a refused reuse names its cause in the log.
