---
bump: patch
---

### Changed

- `babysit_risk` holds `cost-review-required` (HIGH) only for a real new charge: infrastructure as code or a Pulumi project, an unlisted base tree, a file renamed or copied into a workflow or pipeline path, a workflow or pipeline file with no patch, a non-free runner, and, on a repository not known to be public, a `runs-on:`, `windows` or `macos` line or a raised model-leg timeout. Subscription or prepaid spend (a schedule, `--model`, `--max-turns`, a new model leg or package run, a new secrets reference, a `pr-pipeline.yaml` spend line, a raised timeout on a public repository) is the new MED `cost-finding`, reported and in `MERGEABLE_MED`, so it never holds a merge.
