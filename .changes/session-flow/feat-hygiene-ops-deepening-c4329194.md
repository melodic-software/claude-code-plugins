---
bump: minor
---

### Added

- `tidy_work.py` classifies `git-clone` directories (without walking `.git/objects`), `recovery-archive` files and directories (`.bundle`, `.tar`, `.tar.gz`, `.tgz`, `.zip`), all 11 active skill concern directories, and custom `extra_concern_dirs` from `<convention_home>/session-flow.yaml` or repeatable `--extra-concern-dir`.
- `tidy_work.py` adds `--scope {all,repo,home}` and parses repo-qualified frontmatter, headers, and `owner--repo` slugs in `~/.work/running-retros/`.
- `plugin_paths.py` owns shared `git_toplevel`, `default_memory_dir`, `is_self_ignored` (accepting `*` or `**` uniformly across `tidy_work.py`, `save_point.py`, and `observer.py`), and `validate_memory_root`; `save_point.py` exposes public `handoff_chain_meta`, removing all private `save_point._*` imports from `tidy_work.py`.
