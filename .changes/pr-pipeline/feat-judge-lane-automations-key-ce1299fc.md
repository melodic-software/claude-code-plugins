---
bump: minor
---

### Changed

- The lane sweep's judge (`maintenance-audit-lane-runs.yml`) runs on ci-workflows' `run-claude-cli` as the `automations` role and spends its own API key, `AUTOMATIONS_CLAUDE_API_KEY`, in place of claude-code-action on the role's subscription token; claude-code-action never takes a key. A unit whose key leg hands off (a credit stop, a 401 or 402, or an empty key) with no permission denial is judged by the new `judge-subscription` job on `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN`, and with `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN` set, a unit that leg hands off by `judge-fallback` on that token. A matrix job's outputs are not per unit, so a handed-off leg uploads a marker artifact and the secret-free `judge-handoffs` and `judge-subscription-handoffs` jobs build the next leg's matrix from markers checked against a closed set (`handoff.mjs`). Each unit now leaves one `lane-sweep` lane record. `write-findings.mjs` reads the launcher's `structured-output-file`. The lane-funding catalog marks `automations` keyed and lists the three legs.
