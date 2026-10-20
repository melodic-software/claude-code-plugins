---
bump: patch
---

### Changed

- Write lanes deny the shell commands that can print a file or the environment (`echo`, `printf`, `cat`, `head`, `tail`, `grep`, `find`, `env`, `printenv`, `strings`, `od`, `xxd`, `diff`, `sed`, `awk`, `sort`, `cut`, `tr`, `base64`, `nl`, `tac`, `rev`, `uniq`, `fold`, `column`, `jq`, `xargs`, `more`, `less`) and `Read` of `/proc`; the skill reads files with `Read`, `Grep` and `Glob`. `resolve-issue` fetches only the Claude Code, Claude platform, GitHub, Node.js and Python docs hosts, and no longer runs `scripts/run-test-file.sh` or `check-skill.sh`; the pull request's CI runs the tests ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).
