---
bump: patch
---

### Changed

- `/review:explain-change` and `/review:quality-gate` read pull requests through `/source-control:pull-request view` and `list` instead of calling `gh` themselves. explain-change has the read write the facts and the diff to files under the OS temp directory, and its risk checker, publish gate, and recording check read those files. quality-gate drops its pre-computed open-PR list and reads the current branch's pull request base when it needs it, saying so in the report when that read fails.
