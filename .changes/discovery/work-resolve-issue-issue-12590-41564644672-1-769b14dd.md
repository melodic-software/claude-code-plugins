---
bump: minor
---

### Changed

- `/discovery:explore` no longer asks before looking into a file that is missing from disk. It first runs `git status` and `git log` on that path, both read-only. A staged or committed delete counts as intentional: the run skips it and lists it in the output as an intentionally deleted file. A file deleted only in the working tree is investigated. The run asks only when neither command names the path or a command fails. A dispatched run records that question in `open_questions`.
