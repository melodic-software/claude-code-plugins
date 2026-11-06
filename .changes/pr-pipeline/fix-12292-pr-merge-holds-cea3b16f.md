---
bump: patch
---

### Fixed

- pr-merge's candidate listing holds green when `gh pr list` returns its limit of 1000 pull
  requests, as it holds on a failed listing: the `Merge lane hold` notice, `held` with the reason
  `listing full`, and no gate, arm or merge that run (#12292). Before, the job ended red and wrote
  no held summary, so the monitor never counted it; signal 12 now counts these sweeps.
