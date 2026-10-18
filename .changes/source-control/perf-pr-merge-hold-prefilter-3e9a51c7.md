---
bump: patch
---

### Changed

- The pr-merge lane drops a candidate whose listed labels or body carry a hold the gate refuses on (the `do-not-merge` label or a body hold) before running the gate on it, so a held pull request costs no lane-token calls. `babysit_merge_prefilter.py` reads the candidate list on stdin, prints the kept and held candidates, and makes no API call; it judges with the gate's own `MERGE_HOLD_LABEL` and `BODY_MERGE_HOLD_RE`, and the gate still checks every hold itself. When every candidate is held one stays, so a gate process still sweeps held entries out of the merge queue. The run summary reports each dropped candidate as `prefilter:<hold>`.
