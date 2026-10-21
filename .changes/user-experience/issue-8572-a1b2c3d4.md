---
bump: patch
---

### Fixed

- Reject a team-file `output_home` or `research_paths` entry with a dot-leading segment anywhere in it (such as `docs/.env` or `a/b/.git`), not only as the first segment.
