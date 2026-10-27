---
bump: patch
---

### Fixed

- The pr-merge gate reads a Dependabot pull request's `.github/dependabot.yml` and standards Dependabot policy at the default branch head as well as at its base, so a tightening on main reaches pull requests opened before it. Main's head is read once per run-cache window, never saving a failed read, and read fresh again before an enqueue. A manifest directory counts as covered, for the content rule and for a lanes App fix, only when both sides list its ecosystem and directory, since a union would let either side widen coverage. A review-only entry that either side lists sends the update to review. A policy that either side cannot read makes every update `dependabot-policy-unreadable`, and a failed read refuses.
