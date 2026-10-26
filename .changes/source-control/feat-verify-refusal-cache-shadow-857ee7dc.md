---
bump: minor
---

### Added

- The babysit-prs verdict-evidence script's `evidence` command takes `--answers-in`, `--answers-out`, `--answers-mode` and `--answers-only`. It hashes every input of the read into a key: the pull request, its linked issues, the verdict artifacts that can count against it, its PASS runs at the head, the config, the rung and main's trust files. A fresh refusal of a stable kind is kept under that key; an allow, or any unreadable answer, never is. A kept entry expires within the hour, when the pull request turns too old to verify, or when a PASS artifact at the head expires. Under `serve` a matching kept refusal is answered with `cached: true` and no further read. Any other mode still reads in full and adds a `cache` object comparing the kept answer with the fresh one. Any read behind the key that fails, and any answers file of another version, repository or reader code, leads to a full read.
