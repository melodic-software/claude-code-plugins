---
bump: minor
---

### Added

- `intake-reenter` replies once per issue to a listed human's `**Decision recorded.**` comment on an issue `needs-human` holds, on its label or its Work status field, saying the hold stays until a listed human releases it and how. It still releases nothing ([#18251](https://github.com/melodic-software/claude-code-plugins/issues/18251)).
- `intake-reenter` replies once per issue to a listed human's comment whose first line opens with "decision recorded" in another case or punctuation, naming the exact first line `**Decision recorded.**`. Its job now starts on any open issue for a comment that says "decision recorded" in any case.
- The lane sweep's triage-sweep job, on the daily run, lists the open issues a merged `Refs:` pull request parked at Work status confirmed for a done-check in one `github-actions[bot]` digest issue (`done-check.mjs`), which it closes when the list is empty.
