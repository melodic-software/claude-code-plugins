---
bump: minor
---

### Added

- `/knowledge:map-corpus` can map a repository. Name it as a repository seed pinned to a commit SHA, with `--include` and `--exclude` path globs, and the new `repo-tree` discovery rung lists its files from the forge's tree listing. `parse_discovery.py --rung repo-tree` computes the URL set through a forge adapter (GitHub's fetch steps are in `reference/providers/github/repo-tree.md`). `check_linkmap.py` accepts the rung and passes a corpus whose only seed is a repository seed. The rung and its `repository` record are additions to `discovery-output/v1` and `link-map/v1` (#7368).
