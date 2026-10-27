---
bump: patch
---

### Changed

- The cost hold stops a pull request only for a real new charge. Subscription or prepaid spend, including a `pr-pipeline.yaml` spend line, is reported as the non-holding `cost-finding`. A new secrets reference or model leg in a workflow holds for a person as `secret-exposure-review` or `agent-surface-review`.
