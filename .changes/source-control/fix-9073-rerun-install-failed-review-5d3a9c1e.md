---
bump: patch
---

### Fixed

- The babysit merge gate now re-runs an AI review check that failed with the lane's `failure-class=install-failed` line (the runner isolation or the Claude Code CLI install failed before the review ran), at once rather than after the five-hour wait a rate limit gets ([#9073](https://github.com/melodic-software/claude-code-plugins/issues/9073)). Before, such a check stayed red until a person re-ran it. The existing rules still apply: only the first attempt is re-run, at most once per check per head, and only on the pinned live head. The review evidence now defines `install-failed` once and binds the second attempt after it. The classes the gate re-runs (`GATE_RERUN_CLASSES`) come from that same definition, and a test asserts that the review evidence binds a second attempt after each of them. A rejected credential is still left to a person, even when its line sits beside one the gate re-runs. Any other class is still never re-run. The refusal reason now names the classes the gate re-runs.
