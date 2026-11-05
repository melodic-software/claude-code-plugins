---
bump: patch
---

### Changed

- The narrate and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Seven of the eight legacy cases become the new cases `na-text-writes-script-then-narrates`, `na-british-male-slower`, `na-elevenlabs-quota-waits`, `na-egress-floor-no-workaround`, `su-check-bare-read-only`, `su-apply-install-model-fetch-then-check` and `su-apply-refuses-espeak`. The narrate missing-espeak case was already covered by `ck-notice-runs-own-report`. Since a run cannot render audio, the narrate cases grade the commands the skill composes. Both `evals.json` files are deleted.
