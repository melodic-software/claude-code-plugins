---
bump: patch
---

### Changed

- `babysit-prs` merge gate: `--postmerge-result <path>` (with `--authority pr-merge`) takes the demotion record, floor and post-merge verdict from the run's one `babysit_postmerge.py` report instead of reading them again for each pull request. The report now carries a `shared` block naming the default-branch head, its newest pipeline-config commit and the demotion record it was read from. The gate uses it only while the head is unchanged, the pull request's base shares that config commit, the identity, self logins and lane match, and it is under 30 minutes old; otherwise, or when the file is missing or malformed, it reads them itself as before. Without the flag nothing changes. The pr-merge workflow now runs the post-merge check before the gate loop and passes its report to each candidate.
