---
bump: minor
---

### Added

- `/work-items:measure-delivery`: a read-only report of the five DORA delivery metrics (deployment frequency, change lead time, change fail rate, failed deployment recovery time, deployment rework rate) as a weekly or monthly team trend, read from the default branch's git history and never broken down by person (#11874). The repository setting `delivery_deploy_signal` in `docs/conventions/work-items.yaml` sets what counts as a deployment; its one value and default, `merge-to-default-branch`, counts each commit landing on the default branch, and one a later commit reverts counts as a failed deployment.
