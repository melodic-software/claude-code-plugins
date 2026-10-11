---
bump: minor
---

### Security

- `babysit-loop`'s promotion-evidence helper reads its four bootstrap values itself (#7008). `resolve-promotion-evidence.mjs` no longer takes `--binding`, `--probe-evidence-root`, `--evidence` or `--checker`; it reads `promotion_evidence_binding`, `promotion_evidence_root`, `promotion_evidence_source` and `promotion_evidence_checker` from the operator's managed settings files and the user `settings.json` located from its own install path (channel F of `docs/conventions/hook-config-delivery`), managed winning per option. A stub checker or forged binding the lane keeps outside the checkout no longer yields `promoted`: a path argument is a usage error, and the `CLAUDE_PLUGIN_OPTION_*` mirror, `CLAUDE_CONFIG_DIR`, `HOME`, a checkout `.claude/settings.json` and `.claude/source-control.md` are never read for these values. A value supplied only through `--settings`, a server-managed policy or an MDM policy is invisible to the helper and fails closed, so configure the options in managed or user settings. The output gains `options`, naming the settings file each value came from. Operators still keep `--merge human-only` on launch lines; lifting it stays the owner's call.
