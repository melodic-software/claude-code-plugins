---
bump: patch
---

### Fixed

- The code review, security review and intake triage callers now honor the lane kill switches. A `kill-switch` job ahead of each reusable call runs `check-kill-switch` on `CLAUDE_LANES_DISABLED` and `CLAUDE_LANES_REPO_DISABLED`, which fail closed, and the call runs only when it says proceed. The code review lane also stops when `CLAUDE_REVIEW_DISABLED` is `true`, and the security review lane when `CLAUDE_SECURITY_REVIEW_DISABLED` is `true`. Intake has no switch of its own. The pinned ci-workflows reusables still read none of these variables.
