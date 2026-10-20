---
bump: patch
---

### Fixed

- The clean skill's destructive guard now gates only while a mutating clean run is open, tracked by a per-session run marker that `scan` and `scan-batch` never write, so it no longer blocks unrelated commands for the rest of the session.
- On the Bash tool the guard matches each command's parsed words instead of the raw text, so destructive text inside a quoted argument (an issue comment body, a commit message) no longer blocks the command.
- The run marker's idle timeout counts from the last call to one of the clean skill's mutating scripts (dry-run included) or acknowledged or destructive command, so ordinary shell calls no longer keep a marker alive after a run that skipped its close step, while a long dry-run or confirmation phase still reaches its apply gated.
