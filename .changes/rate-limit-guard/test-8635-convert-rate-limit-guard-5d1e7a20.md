---
bump: patch
---

### Changed

- The eval suite moved from `skills/*/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md` ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
- `/rate-limit-guard:setup check` labels every row PASS, FAIL, INFO or UNKNOWN (UNKNOWN for a check that cannot run here), gives each FAIL one remediation line, keeps every option its own row even when all are UNKNOWN, says the module writes `rate_limits` only when its session sees subscription windows, and reads the hook source only for a finding no check step covers.
