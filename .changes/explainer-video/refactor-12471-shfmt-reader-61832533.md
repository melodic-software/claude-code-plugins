---
bump: patch
---

### Changed

- The shared `hook-utils.sh` reads Bash commands from `shfmt --to-json` (`hook::bash_parse_segments`
  keeps its callback and `HOOK_SEG_*` contract), and the hand-written segmenter is removed. It
  refuses the call when shfmt or jq is missing, fails, runs past 5 seconds, or rejects the text
  (an unclosed here-doc, for one, which bash runs with a warning), and the refusal names which of
  those happened, quoting shfmt's syntax error. It uses a shfmt in `~/.local/bin` when PATH has
  none. The 5-second bound is the `read -t` builtin, so a parse forks the same processes on every
  run and needs no `sleep` or `timeout` command.
