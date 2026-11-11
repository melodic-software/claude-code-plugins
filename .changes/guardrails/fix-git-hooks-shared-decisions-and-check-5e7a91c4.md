---
bump: patch
---

### Fixed

- The `setup` skill's git-hook decisions reference no longer restates when husky sets `core.hooksPath`; the `husky-install` row keeps its action: tell the user to run the project's install.
- The `setup` skill's git-hook decisions reference keeps its lefthook `use_stdin` and remote `source_dir` actions but drops the restated lefthook behavior and error string, pointing at lefthook's `use_stdin` and `remotes` docs instead. On lefthook 2.2.2 both pre-push jobs receive the pushed refs, with `parallel` off and on. The row still tells the user, when `parallel: true` is set on another lefthook version, that `pre-push-content` may not receive the refs and could pass a push it never checked.
- The lefthook remote test now checks that the second pre-push job (`pre-push-content`) also blocks from the refs on stdin, and the `lefthook-remote.yml` comment says so instead of tying stdin to the jobs running in turn.
- `setup check` no longer downgrades a tool a git-hook entry needs (`jq` for `reference-verify`) to INFO while every guard is off and that entry is installed: the entries run at commit or push outside Claude Code and read no toggle.
