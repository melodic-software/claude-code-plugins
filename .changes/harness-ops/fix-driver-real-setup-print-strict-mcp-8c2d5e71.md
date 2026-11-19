---
bump: patch
---

### Fixed

- `control-claude-code`: under `--real-setup`, the print-mode turns of the driver's `ready` and `log` keep `--strict-mcp-config` (why: <https://code.claude.com/docs/en/permissions#what-runs-before-you-trust-a-folder>). The interactive `launch --real-setup` session still drops both isolating flags.
