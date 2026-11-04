---
bump: major
---

### Removed

- The one-release reads of the repository team file `.claude/source-control.md`, kept since the keys moved to `docs/conventions/source-control.yaml`. The team layer is that YAML alone for the commit and PR convention keys (`lib/convention-key.sh layer` prints `yaml` or `none`, never `legacy-md`), for `parse-branch-issue.sh`, for the seven babysit repository-policy keys and the `babysit_loop_*` keys `babysit_repo_config.py` reads from a target repository's default branch, and for the unattended merge gate's `babysit_loop_merge`. Two effects reach a repository that still keeps keys only in `.claude/source-control.md`: a lower `babysit_loop_merge` there no longer caps the gate's rung, and hold lists set only there (`babysit_merge_block_labels`, `babysit_extra_dependency_manager_logins`, `babysit_approval_downgrade_logins`) stop applying. Move every key it still carries into `docs/conventions/source-control.yaml`, then delete the file. The user-global `~/.claude/source-control.md` and the personal overlay `.claude/source-control.local.md` are still read ([#9737](https://github.com/melodic-software/claude-code-plugins/issues/9737), [#12287](https://github.com/melodic-software/claude-code-plugins/issues/12287)).
