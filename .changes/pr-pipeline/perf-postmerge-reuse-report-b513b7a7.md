---
bump: patch
---

### Changed

- The pr-merge merge job reuses this run's post-merge report by the lane room's reuse rule (`babysit_verify_evidence.py settle`, `babysit_merge_policy.settle_shared`) in place of its 6-minute age and same-main test (`REUSE_MINUTES`), which never passed because the report's age counts from before its 6-8 minute check. A report whose check judged (exit 0, 1 or 5) is reused when `settle` keeps it, including at a moved main with no new lane merge; any refusal or failed read runs the check as before (`.github/workflows/pr-merge.yml`). post-merge-dispatch keeps the commit whose code ran its check beside the report, and both the merge job's reuse and enable-auto-merge's lane room (`POSTMERGE_CODE_SHA`) refuse or read the report again when the babysit-prs scripts or `docs/conventions/pr-pipeline.yaml` differ at their own commit, or that commit is missing. The merge job reads the agent identity with yq only for a fresh check.
