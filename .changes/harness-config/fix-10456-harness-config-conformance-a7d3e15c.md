---
bump: patch
---

### Fixed

- `/harness-config:audit-permission-state`: the reader takes the project file from the primary
  working directory rather than the repository root, so a session started in a subdirectory no longer
  reports the root's rules as in effect. The output names the directory it used. Its cloud-session
  note also covers self-hosted runner images and project cloud threads.
- `/harness-config:audit`: the baseline drops the `Bash(git push)` ask row, which `Bash(git push *)`
  already covers, so a project with the wider rule is no longer flagged for lacking the bare one. An
  absent `effort:` no longer reads as the session level, the family alias record no longer rests on a
  stale probe, and the effort table baseline matches the current page, with the listed levels unchanged.
- `/harness-config:audit-instructions`: harness thinking-disable forms no longer fire the rejected
  pairing row on models where they have no effect, exit-2 stderr is no longer stated as always
  reaching Claude, and the first-run hold and a mis-aimed settings pointer are gone.
- `/harness-config:audit-permission-grants` and the plugin README: the user settings file is no
  longer named as where a prompt approval lands.
- `/harness-config:audit-pass`: the handoff no longer compares a `/doctor` version floor its pointer
  has stopped stating, names `skillOverrides` as a documented suppression channel, and the report
  location record points at the plugin data rules instead of quoting them.
