---
bump: minor
---

### Added

- `/coupling:reduce` runs across several repositories when `--repo`, `--repos-from`, `--owner` or `--fleet` names them, per the new shared target-scope contract (`reference/target-scope.md`): one pass per repository, findings ranked on one scale, and one pull request per repository. The default stays this repository.
- `scripts/cross-repo-dups.py` lists files copied between repositories: blobs tracked in two or more of them, and file names whose copies drifted apart, with their line similarity. Copies a sync manifest or vendoring registry declares, generated files and fixture paths are left out and counted.
