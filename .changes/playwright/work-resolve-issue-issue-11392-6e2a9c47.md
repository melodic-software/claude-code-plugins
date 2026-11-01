---
bump: minor
---

### Changed

- `/playwright:demo-video` posts a video that is verification evidence through `/source-control:pull-request evidence` when that skill is available, so the evidence step's verdict gate, leak scan and one-comment rule apply to it. A demo a person asked for, or evidence when the step is not available, still posts with `gh pr comment --attach` locally or as an Actions artifact link in CI ([#11392](https://github.com/melodic-software/claude-code-plugins/issues/11392)).
