---
bump: patch
---

### Changed

- The post-merge check (`babysit_postmerge.py`) answers a lane dispatch or re-run record from the file pr-merge.yml names in `BABYSIT_POSTMERGE_LANE_RECORDS` before listing it: a record an earlier check proved is present with no request once it is unexpired and the run that uploaded it passes the check's sender rule again (pr-merge.yml on the branch, an event of the job that writes the record, a head commit on the branch tip). The check writes back, to the same file, the records it read in and each it proves whose uploading run completed and whose artifact was listed unexpired, keeping those created at or after its floor and unexpired. A record it holds decides as the reads would; any other record is read as before, and a missing, unreadable or malformed file (another version or repository, a name that is no lane record, an entry missing its dates, artifact id or completed sender) is no file. Without the variable nothing changes.
