---
bump: minor
---

### Added

- `/architecture:map-deployment` lists a Kubernetes `CronJob` and `Job` under `## Unmapped resources` instead of dropping them. Their containers and parameters are not placed, and a repository of only those kinds is refused as `no-mapped-container`.
- `--diff` compares compute nodes (clusters, service plans, node pools) of the Terraform, Bicep, ARM, CloudFormation and Pulumi readers: a node in one environment only (`compute-added`, `compute-removed`) or of a different resource type (`compute`). Nodes are matched by resource address, so a per-environment name alone is not a difference.
