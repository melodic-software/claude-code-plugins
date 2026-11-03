---
bump: patch
---

### Changed

- Upstream facts restated in the README, `distill`, `docpage-digest` and `setup` are now
  pointers to the docs section that owns them, each with an as-of date and a recheck trigger:
  how the Read tool handles a PDF, where a `sensitive` option is stored, when Edit and Write need
  a prior Read, and where `${user_config.*}` resolves. The local rules stay: Read a renamed file
  at its new path before editing it, rerun `check` in a fresh session, and keep course-platform
  credentials in shell env vars.
- `docpage-digest` no longer names which systems lack `sha256sum`, and its Anthropic docs profile
  no longer lists the raw-markdown channel's fence, tab and URL-escaping artifacts, which no docs
  page records. `source.*` still stays the unaltered fetch, and digests still reproduce channel
  artifacts without repairing them.
