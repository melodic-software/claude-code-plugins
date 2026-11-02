---
bump: patch
---

### Fixed

- `/review:fanout` now runs its Codex surface. The Codex plugin's `/codex:review` and `/codex:adversarial-review` commands set `disable-model-invocation: true`, so fanout listed Codex but never ran it. The new `skills/fanout/scripts/codex-review.sh` finds `codex@openai-codex` through `claude plugin list --json`, checks the Codex CLI and its login with the plugin's `setup --json`, and runs the plugin's `codex-companion.mjs` review in the foreground with the review base passed as `--base`. Its first line reports `codex: ran`, `codex: skipped (<reason>)` or `codex: failed (<reason>)`, so a run with no Codex CLI or login reports the surface as skipped, never as ran. The fanout-diversity X-arm eval prompts no longer name `/codex:review`.
