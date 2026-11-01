---
bump: minor
---

### Added

- work-item-tracker: the github and local-markdown `claim` take an optional `--phase <kind>` (`triage`, `discovery` or `implementation`) and write it into the lease as `phase` (#11871). A lease without the field is an implementation claim. `renew-lease`, and the github `reclaim`, keep it, so a triage or discovery claim can be told apart from an implementation claim and timed per phase. Arbitration and liveness ignore the field. Any other value is refused with exit 2 before anything is written.
