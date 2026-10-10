---
bump: patch
---

### Fixed

- **`audit` ended before any model turn under `--permission-mode dontAsk`.** The effective-config pre-compute line chained `>/dev/null 2>&1 && { ...; :; } || echo "detector unavailable"`. Claude Code checks every command in a `!` line against the skill's `allowed-tools`, and `:` and `echo` match no grant, so a dontAsk session (the pr-refine fix-docs lane) denied the expansion, printed `Shell command permission check failed` as local-command stderr, and returned a `success` result with `num_turns: 0`. The line is now `detect.sh --show-config 2>&1 | head -40`, which the `detect.sh` and `head` grants cover; a failed detector shows its shell error in place of the config instead of `detector unavailable`.
