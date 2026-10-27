---
bump: patch
---

### Changed

- `babysit_risk` holds `cost-review-required` (HIGH) only for a real new charge:
  - infrastructure as code or a Pulumi project;
  - an unlisted base tree;
  - a file renamed or copied into a workflow or pipeline path;
  - a workflow or pipeline file with no patch;
  - a non-free runner;
  - on a repository not known to be public: a `runs-on:`, `windows`, `macos` or `cron` line, a raised model-leg timeout, or an artifact `retention-days` raised above the one removed or above GitHub's 90-day default.
- Subscription or prepaid spend is the new MED `cost-finding`. It is reported, sits in `MERGEABLE_MED` and never holds a merge. It covers `--model`, `--max-turns`, a `pr-pipeline.yaml` spend line, and on a public repository a schedule, a raised timeout or a raised retention.
- A net-new secrets reference now holds as the HIGH `secret-exposure-review`, and a new model leg or `@anthropic-ai/claude-code` run as the HIGH `agent-surface-review`. Both are in `PERSON_CODES`, and a cost decision does not clear them.
