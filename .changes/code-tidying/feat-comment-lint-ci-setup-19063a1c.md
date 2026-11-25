---
bump: minor
---

### Added

- `git-hooks/comment-lint-ci.sh <head> <base>` re-runs the comment lint over a change in any CI system, judged against the base branch's settings; it takes both commits as arguments and reads no CI vendor variable. A shared hook install commits it beside the hook.
- `/code-tidying:setup apply install-ci` finds the repository's CI system, how its jobs get Python and their change's commits, asks only what that leaves open, and proposes the step in that system's own format, written only on the user's yes. No CI system is a default.
- `/code-tidying:setup check` reports the CI job that runs the script, a hand-run recipe, or drift when a call no longer matches the script's interface.
