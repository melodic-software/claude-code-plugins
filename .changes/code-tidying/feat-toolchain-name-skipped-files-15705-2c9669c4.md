---
bump: minor
---

### Changed

- `changed-code-files.sh`, `scope-code-files.sh` and `comment-census.py` read one shared extension
  list, `scripts/code-extensions.txt`. As an intended change, `changed-code-files.sh` now lists the
  seven extensions it lacked: `.mts`, `.cts`, `.mjs`, `.cjs`, `.pyi`, `.bash` and `.psm1`.
- When that list is missing or empty, each of the three scripts exits 4 and prints
  `cannot read the extension list <path>` on stderr, with nothing on stdout.
