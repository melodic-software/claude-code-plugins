---
bump: minor
---

### Changed

- `/review:council` Codex members and `/review:fanout`'s Codex surface now run `external-agents review codex`, the command the `external-agents` plugin puts on the Bash `PATH`, instead of locating the OpenAI Codex plugin's install path. With that plugin not enabled, the member or surface reports `skipped (external-agents not enabled)`. Fanout runs one Codex review per sweep; a briefed (adversarial) Codex review is a council member with a brief.
- `council-plan.mjs member` reads a script member's captured output and exit code as its council status (`ran`, `skipped (<reason>)` or `failed (<reason>)`) and its findings, finding the status line after any notices.

### Removed

- `scripts/codex-review.sh` and its test.
