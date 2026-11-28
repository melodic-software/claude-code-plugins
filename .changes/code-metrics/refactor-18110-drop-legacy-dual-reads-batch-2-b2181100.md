---
bump: major
---

### Removed

- **Dropped legacy `~/.claude/code-metrics.yaml` and `.claude/code-metrics.local.yaml` dual-reads and `setup apply --copy-old`.** `resolve-config.py`, `setup-check.sh`, and `setup-apply.py` now read only the canonical config-cascade layers (`config_file` `userConfig` option via `--user-file`, `docs/conventions/code-metrics.yaml`, and `docs/conventions/code-metrics.local.yaml`).
