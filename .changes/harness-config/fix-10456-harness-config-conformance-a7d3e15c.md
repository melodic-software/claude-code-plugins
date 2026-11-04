---
bump: patch
---

### Fixed

- `/harness-config:audit-permission-state`: the reader takes the project file from the primary
  working directory rather than the repository root. Below the repository root, where it cannot tell a
  session started there from one that ran a Bash `cd`, it also reads the root's file as
  `project toplevel`, so a root-started session's deny rules survive a `cd`; run it from the session's
  start directory, since after a `cd` from another subdirectory that directory's file is not read. The
  output names both directories,
  the lint checks each file's values, and `--merge-only` keeps the note that one may be over-reported.
  Its cloud-session note also covers self-hosted runner images and project cloud threads.
- `/harness-config:audit`: the baseline drops the `Bash(git push)` ask row, which `Bash(git push *)`
  already covers, so a project with the wider rule is no longer flagged for lacking the bare one. An
  absent `effort:` no longer reads as the session level, the family alias record no longer rests on a
  stale probe. The `fallbackModel` chain cap is read from model-config's Fallback model chains section,
  where the page now states it, so the check no longer skips every chain. The effort pin check finds the defaults item by what it says, so a renumbered list no
  longer hides a changed default, and its baseline matches the current page, with the listed levels
  unchanged.
- `/harness-config:audit-instructions`: harness thinking-disable forms no longer fire the rejected
  pairing row on models where they have no effect, exit-2 stderr is no longer stated as always
  reaching Claude, and the first-run hold and a wrong settings pointer are gone.
- `/harness-config:audit-permission-grants` and the plugin README: the user settings file is no
  longer named as where a prompt approval lands.
- `/harness-config:audit-pass`: the handoff no longer compares a `/doctor` version floor its pointer
  has stopped stating, names `skillOverrides` as a documented suppression channel, and the report
  location record points at the plugin data rules instead of quoting them.
