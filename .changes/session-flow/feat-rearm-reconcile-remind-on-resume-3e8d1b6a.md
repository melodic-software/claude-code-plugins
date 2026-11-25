---
bump: minor
---

### Added

- A resume-context hook (`resume_context_enabled`, on by default): when a pasted resume prompt
  starts with its `Read @<handoff file>` directive (or a `/goal` paste ends with it) and the file
  exists, it adds `reference/resume.md` to that turn once per session. The resumed session raises
  due reminders in its first reply, offers a re-drafted goal when the handoff flags one, reads rate
  limits on subscription accounts, reconciles only recorded off-thread work, continues the work,
  then lists its scheduled tasks and re-arms each recorded loop, cron task and monitor that is
  missing. Any other prompt stops in the node launcher.
- Environment to re-establish records `[loop]`, `[cron]`, `[monitor]` and `[off-thread]` entries.
  `validate` fails an entry that lost text to redaction without `restore: manual`, and warns on a
  loop or cron entry whose line count does not match its prompt.

### Changed

- The resume directive also asks the session to raise its due reminders and re-establish its
  Environment last, for a session the hook does not reach. Older directives still validate.
- New handoff files carry surviving loops under Environment to re-establish instead of the
  below-rail `Re-arm <i> of <n>` block; recovery still reads that block from older files.
