---
bump: patch
---

### Added

- `behavior-probes`: a `hub-start` area of seven auto-mode cases, built by a new `cases/lib/hub-layout.sh` scaffold, checks what a session started in one repository may write in a sibling repository and its worktree under a stand-in `autoMode.environment`. Record 22 holds the live run: every action ran.
- `behavior-probes`: a case `auto-mode/flag-automode-rule-denies-local-classifier`, and reruns on records 4 and 5. Record 5 now records that the server-side auto-mode check does not apply an `autoMode` rule passed with `--settings`, while the built-in classifier does.
