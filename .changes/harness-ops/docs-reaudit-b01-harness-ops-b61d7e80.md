---
bump: patch
---

### Changed

- Skill and reference docs now point at the live Claude Code docs section for upstream behavior (`doctor` gating, WebFetch output, plugin variables, settings precedence, `/loop` and its expiry, hook scheduling, CLI flags) instead of restating it, with an as-of date and a recheck trigger on each record.
- Corrected statements about this plugin's own files: the platform-specific functions in the install-state engine, the test that pins the observer-flag text, an extraction-table example, the Windows process check in `refresh`, the `sync-run.sh` synopsis, CLI write serialization, the OTEL store path, the privacy filter's write-time gate and token length, and several dangling citations.
- Replaced machine host names with placeholders and qualified bare upstream issue numbers. No behavior change.
