---
bump: patch
---

### Changed

- `babysit_postmerge.py` lists only open issues when it reads quarantine issues (the check's quarantine read and `file_quarantines`), which keep only open ones anyway, instead of every issue the filers ever opened. Remediation's demotion-record lookup still lists closed records, since a new sighting reopens one.
- `babysit_postmerge.py` shares each compare answer between two full SHAs through the run cache file (`BABYSIT_RUN_CACHE`, section `postmerge-compare`), so a run's later gate processes answer the same ancestry question with no compare call. A shared answer still counts against the settle and anchor compare budgets, so no gate decision changes. Branch tips are still read once per process.
