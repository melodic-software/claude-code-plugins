---
bump: patch
---

### Fixed

- The merge gate, the review evidence and the cost-decision reads accept the review lanes' status jobs as ci-workflows' pr-review-cli.yml names them (`pr-review / review-status` and `pr-review-security / review-status`) beside the earlier names, and match each by its whole caller-qualified name, so a security job is never read as the code lane's.
