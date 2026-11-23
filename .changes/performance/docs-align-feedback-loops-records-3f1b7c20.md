---
bump: patch
---

### Changed

- `/performance:target` names the pre-PR check (run once per head before a pull request opens) as a lane between the push hook and CI, moves a slow check from a hook to the pre-PR check or CI, and names the git-hooks installer's read-only `inspect` inventory as a source of hook timings.
