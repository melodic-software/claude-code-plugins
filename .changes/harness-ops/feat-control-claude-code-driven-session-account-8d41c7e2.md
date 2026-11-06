---
bump: minor
---

### Changed

- `control-claude-code`'s `cli/account.mjs` reports the driven session's account, not the caller's: the session holder runs `claude auth status --json` in that session's own launch environment, the one its masks already read, so the mask post-check resolves in CI, where the outer leg and the driven session run in separate sandboxes. It asks the one session running, or the one `--session <name>` names, and exits 1 with nothing on stdout when no session or several run. The `none:` line now needs the session to run on the `ANTHROPIC_API_KEY` its launch kept.
