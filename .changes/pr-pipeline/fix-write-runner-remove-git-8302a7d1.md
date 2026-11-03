---
bump: patch
---

### Fixed

- `pr-run-activity-write.yml` removes the head checkout's and `.base`'s `.git` directories after a skill step, as `pr-run-activity-read.yml` does, so neither `actions/checkout` post step runs git under config the skill wrote while it holds the job's runtime token. A script activity skips the step and keeps its checkout.
