---
bump: patch
---

### Fixed

- The unattended merge gate's cost check (`babysit_risk.py`) no longer reports changes that cannot bill as cost. A workflow's `--model` or `--max-turns` flag, and on a public repository an added `cron:` key, a raised `timeout-minutes` or `leg-timeout-minutes`, or a raised artifact `retention-days`, no longer raise `cost-finding`. Every check that can bill still holds as `cost-review-required`: infrastructure as code, a larger or non-free runner, and off a public repository a new runner, schedule, raised timeout or raised retention.
