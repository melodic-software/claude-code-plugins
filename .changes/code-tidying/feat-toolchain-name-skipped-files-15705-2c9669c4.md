---
bump: minor
---

### Changed

- `changed-code-files.sh`, `scope-code-files.sh` and `comment-census.py` read one shared extension
  list, `scripts/code-extensions.txt`. As an intended change, `changed-code-files.sh` now lists the
  seven extensions it lacked: `.mts`, `.cts`, `.mjs`, `.cjs`, `.pyi`, `.bash` and `.psm1`.
- Each of the three scripts exits 4 and names the list's path when it cannot read the list, instead
  of matching no file.
