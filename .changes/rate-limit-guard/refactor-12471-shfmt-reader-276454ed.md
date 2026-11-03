---
bump: patch
---

### Changed

- The shared `hook-utils.sh` reads Bash commands from `shfmt --to-json` (`hook::bash_parse_segments`
  keeps its callback and `HOOK_SEG_*` contract), and the hand-written segmenter is removed. It
  refuses the call when shfmt or jq is missing,
  fails or runs past 5 seconds, and the refusal names which of those happened, quoting shfmt's
  syntax error. It uses a shfmt in `~/.local/bin` when PATH has none.
