---
bump: patch
---

### Added

- **An eval case for `ready`'s evidence step.** `pull-request-ready-posts-evidence-after-flip` runs `ready --evidence` on an offline draft whose head is verified and confirmed, and checks that the evidence comment goes up after the flip, with the publishable capture attached, and that the report names it. The pull request eval forge now answers `gh repo set-default --view` with its repository, so phases that resolve the target repository through `target-repo.sh` run offline.
