---
bump: minor
---

### Changed

- **The config cascade's personal layer is called the personal override.** `/testing:check-visual-parity`'s `visual-compare.sh config` prints `source=personal-override` where it printed `source=overlay` for `.claude/testing.local.yaml`. `scripts/resolve-config.sh` comments, the run-e2e configuration contexts and the evals use the same name. Which file is read and which value wins are unchanged ([#13190](https://github.com/melodic-software/claude-code-plugins/issues/13190)).
