---
bump: minor
---

### Added

- `/performance:go-faster` reads delivery metrics from `/work-items:measure-delivery` (#11883). When the work-items plugin is installed and enabled, the `pr-review` area records change lead time and failed deployment recovery time from the default branch's history, with the change fail rate and the deployment rework rate in each title. Without the plugin, the area marks those metrics not checked (`owner-unavailable`), names the plugin to enable, and the sweep goes on.
