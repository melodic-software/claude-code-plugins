---
bump: major
---

### Added

- Seven trust and cost settings, read only from the source-control `userConfig` in user or managed settings (managed-settings.d drop-ins included) by the new `babysit_merge_settings.py`, never from a repository or the environment: `unattended_merge_owners`, `review_lane_workflows`, `review_lane_checks`, `owner_decisions_record`, `free_runner_labels`, `model_leg_actions` and `issue_status_app_login`.

### Changed

- **Breaking:** the merge phase's unattended merge, `review-venue.sh`, the merge gate's AI review checks and review lanes, the cost-decision row link, the free runner labels, the model-leg actions and the trusted Work status App come from those settings instead of one organization's values fixed in the plugin. Every one fails closed when unset: nothing merges without the user, no CI run or check counts as AI review, no decision clears a cost hold, only GitHub's standard runner labels are free, only the built-in `claude-code*` names start a model leg, and only a person's Work status values count. An operator who relied on the old values sets them in `userConfig`.

### Removed

- **Breaking:** the verdict reader no longer reads a legacy FAILs file beside itself; it reads only the file `BABYSIT_VERIFY_LEGACY_FAILS` names, and reads the whole artifact listing when that is unset.
