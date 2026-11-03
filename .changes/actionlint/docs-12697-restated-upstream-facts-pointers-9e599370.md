---
bump: patch
---

### Changed

- The README no longer explains why ShellCheck misbehaves under actionlint or where actionlint
  finds its configuration file. It keeps the choice to turn the run-block linters off at commit
  and run them in CI, and points at actionlint's ShellCheck integration and configuration file
  sections, each with an as-of date and a recheck trigger.
- `setup` no longer describes how a missing `node` shows up in the transcript; the FAIL and its
  reason stay.
- `setup` no longer states where actionlint finds its config file. The check still reports
  whether one exists, as INFO, and points at actionlint's configuration file section.
- `setup` no longer describes what each reconfiguration route prints, exits with or stores, the
  rerun's `-s` default, or when a saved value takes effect. It keeps passing the scope
  `claude plugin list` reports, reading each route's output and rerunning `check` in a fresh
  session, and points at the plugin commands and manifest reference sections.
