---
bump: minor
---

### Changed

- The `maintenance-scan-architecture` lane files its findings on a lanes App token instead of the job's `GITHUB_TOKEN`: its one slot, `file-architecture-findings`, has the `mutate-tracker` effect, File Findings requests the token from the broker and revokes it after filing, and its `GITHUB_TOKEN` drops `issues: write`. The issues start intake as the lanes App's own filings, and `own-agents.hold-sources` in `admission-rules.json` no longer lists `source: architecture-improve`, so admission takes them like any own-agent filing up to the source cap instead of holding them for a person.
