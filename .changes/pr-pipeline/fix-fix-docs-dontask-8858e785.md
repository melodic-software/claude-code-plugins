---
bump: patch
---

### Fixed

- fix-docs runs again, now in the read runner's default `dontAsk` mode instead of `auto`, which
  run-claude-cli's subprocess env scrub forced back to the default mode
  ([run 39723040443](https://github.com/melodic-software/claude-code-plugins/actions/runs/39723040443)).
  Its Bash runs only explicit allow rules: each `ai-slop:audit` script by absolute path under
  `.lane/plugins`, bare and double-quoted, plus `sha256sum` and `mkdir -p` in `.lane/scratch`
  for the fix flow's digests, and `Edit(./.lane/scratch/**)` so a redirect into the scratch
  directory is approved. It denies `git`, the `user-scope.sh` script, `NotebookEdit` on the
  staged plugin and the write lanes' shell deny set. The staging step also makes `.lane/prompt.md`
  and `.lane/` read-only, so a script's `--out` lands only in `.lane/scratch`.
