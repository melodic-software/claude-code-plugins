---
bump: major
---

### Removed

- The tracker seam no longer reads a repo-root `.work-item-tracker.json`. The binding is only the `tracker` mapping of `<home>/work-items.yaml` (or a file `WORK_ITEM_TRACKER_BINDING` names). A repository bound only by the JSON file now gets exit `3` from every seam verb. **Fix: run `/work-items:setup apply`**, which copies the JSON binding and its `.work-item-tracker.local.json` personal override under `tracker:` in `<home>/work-items.yaml` and `<home>/work-items.local.yaml`, and leaves the JSON files in place.
- The one-line `notice:` the seam printed when it read the JSON file is gone.

### Changed

- With no binding, the seam's exit `3` message (`wit_no_binding_reason` in `lib/binding.sh`) says why and names `/work-items:setup apply`: a repo-root `.work-item-tracker.json` that no longer binds, a `work-items.yaml` with no `tracker` mapping, a root where no convention home applies, or a missing `WORK_ITEM_TRACKER_BINDING` file. The jira, gitea and linear seeds and the onboard-adapter template print the same message.
- `/work-items:setup check` reports a binding that exists only in `.work-item-tracker.json` as FAIL, remediation `/work-items:setup apply`, instead of INFO.
- The seam contract, setup skill, README, schema and the skill bodies that resolve role labels no longer describe a JSON fallback.
