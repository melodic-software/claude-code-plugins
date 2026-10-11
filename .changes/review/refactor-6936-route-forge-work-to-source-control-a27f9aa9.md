---
bump: patch
---

### Changed

- `/review:explain-change` and `/review:quality-gate` read pull requests through `/source-control:pull-request view` and `list` instead of calling `gh` themselves. explain-change has the read write the facts and the diff to files under the OS temp directory, and its risk checker, publish gate, and recording check read those files. quality-gate drops its pre-computed open-PR list and finds the current branch's open pull request with `list --head`; a failed read stops the review as an unresolved base instead of falling back to the default branch. The explain-change publish gate takes `--facts <file>` and reads the visibility itself.
