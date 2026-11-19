---
bump: patch
---

### Added

- **An eval case for `ready`'s evidence step.** `pull-request-ready-posts-evidence-after-flip` runs `ready --evidence` on an offline draft whose head is verified and confirmed, and checks that the evidence comment goes up after the flip, with the publishable capture attached, and that the report names it. The forge now serves `gh run list` for the head (one run on a draft, a new one after the flip), so `ready`'s check for a run after the flip passes as the skill prescribes, and its tests cover that and its `gh repo set-default` answers.
