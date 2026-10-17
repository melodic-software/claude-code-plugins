---
bump: minor
---

### Added

- The pr-merge lane (`babysit_merge.py --unattended --authority pr-merge`) reads the pr-verify verdict when `merge.require-verifier-verdict` is true, from artifacts `pr-verify-<pr>-<head-sha>-<verdict>` authenticated by their run (`.github/workflows/pr-verify.yml`, event `workflow_run`, on main, this repository, head on main). A FAIL counts whatever its run concluded and under any pull request number: at the head it refuses `verify:fail`, at another head of the pull request (number, commit or head branch) `verify:earlier-fail`. A PASS counts only from a successful run, only while the pull request's closing issues are the ones it recorded (`verify:spec-changed` otherwise), and only when it records a linked issue a trusted human other than the author wrote (`verify:untrusted-spec` otherwise). A pull request older than 80 days refuses `verify:too-old`, any failed read `verify:unreadable`, and no verdict `verify:missing`. Queued entries are dequeued on the same rules at their live head; a dependency manager's pull request is refused before the verdict is read.
