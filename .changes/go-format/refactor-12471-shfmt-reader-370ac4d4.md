---
bump: patch
---

### Added

- The shared `hook-utils.sh` gains `hook::bash_parse_segments_shfmt`, a Bash command reader on
  `shfmt --to-json` with the same callback and `HOOK_SEG_*` contract. `HOOK_BASH_READER=shfmt`
  selects it; the default reader is unchanged. It refuses the call when shfmt or jq is missing,
  fails or runs past 5 seconds, and the refusal names which of those happened, quoting shfmt's
  syntax error. It uses a shfmt in `~/.local/bin` when PATH has none.
