---
bump: patch
---

### Changed

- The pr-merge gate fetches each verdict.json by the listed artifact's id (`GET .../actions/artifacts/{id}/zip`, one request) instead of `gh run download`, which first lists the run's artifacts (two requests). An artifact listed without an id still goes through `gh run download`. An untied FAIL record a gate process could not read is shared in `BABYSIT_RUN_CACHE` (`unreadable-fail-head-ref`, by artifact id), so the run's later candidates refuse on it without downloading it again; a failure only refuses, and `carry-run-cache.mjs` does not carry it to the next run. Any failure to unpack or parse an archive, a corrupt deflate stream's `zlib.error` included, is now an unreadable record, where before that error escaped the reader and failed the candidate's gate process. `fail_summary` fetches the head FAIL by the id its Reader's listing gives. No gate decision changes otherwise. `babysit_util.run_command` and `babysit_gh.gh_capture` take `binary=True` to keep stdout as bytes, for the zip.
