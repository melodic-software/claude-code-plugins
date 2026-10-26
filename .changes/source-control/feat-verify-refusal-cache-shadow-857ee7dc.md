---
bump: minor
---

### Added

- The babysit-prs verdict-evidence script's `evidence` command takes `--answers-in`, `--answers-out`, `--answers-mode` and `--answers-only`. It hashes the read's inputs into a key: the pull request, its linked issues, the verdict artifacts that can count against it, its PASS runs at the head, the config, the rung and main's trust files. Review-body and inline-comment edits, and who resolved a thread, are not hashed; since only refusals are kept, a change there can only delay an arm until the entry expires. A fresh refusal of a stable kind is kept under that key; an allow, or any unreadable answer, never is. A kept entry expires within the hour, when the pull request turns too old to verify, or when a PASS artifact at the head expires. Under `serve` a matching kept refusal is answered with `cached: true` and no further read. Any other mode still reads in full and adds a `cache` object comparing the kept answer with the fresh one; `--answers-only` applies under `serve` alone. Any read behind the key that fails, any answers file that cannot be loaded or is of another version, repository or reader code, and any other error of the cache's own leads to a full read, or to no answer under `--answers-only`, with a `cache` object marking the error. Under `--answers-only` a pull request with no kept entry is a miss with no probe.
