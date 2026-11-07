---
bump: patch
---

### Changed

- The setup skill's `evals.json` is retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Seven new cases cover `check` and every `apply` refusal and write path on a scaffolded repository: `setup-check-memory-root` (the memory root as INFO, a file-path ignore probe, nothing written), `setup-check-absent-guard-info` (an absent ignore guard is INFO, not FAIL), `setup-apply-placement-not-configurable` (artifact placement has nothing to persist), `setup-apply-strict-shows-diff` (a change to an existing file shows its diff and waits for a yes), `setup-apply-refuses-thorough` and `setup-apply-refuses-zero-workers` (an unlisted value is refused and nothing is written), and `setup-apply-writes-live-workers` (a new file holds only the named key, read back after the write). The repository comes from the new `evals/fixtures/settings-repo.sh` behind `evals/fixtures/workspace-guard.sh`.
