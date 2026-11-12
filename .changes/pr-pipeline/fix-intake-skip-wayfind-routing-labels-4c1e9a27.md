---
bump: patch
---

### Fixed

- Intake triage skips an issue that carries the work-items binding's container label (default `work-map`) or a label starting with its wayfind prefix (default `wayfind:`): a `/planning:wayfind` map or decision item, or a decompose container. On an opened or reopened issue and on a dispatch it starts no triage, verdict or refinement run and adds no `needs-triage`, and the gate's notice names the label. `check-born-triaged` reads both labels from `docs/conventions/work-items.yaml` (`tracker.config.container_label`, `tracker.config.wayfind_label_prefix`) and gains a `born-triaged` input (`false` applies only the routing-label rule, as intake-triage.yml passes on a reopen and a dispatch), a `tracker-config` input and a `label` output.
