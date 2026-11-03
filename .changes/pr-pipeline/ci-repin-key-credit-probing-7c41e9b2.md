---
bump: patch
---

### Changed

- pr-verify and pr-review-main pin ci-workflows check-key-credit at `09cf6f2`, which adds the
  probing marker: once a credit stop is past its window but still kept, the first gate names
  itself the probe and later gates skip the key while its marker is fresh, so one run tries the
  key after the window ends instead of every run that reads before the next credit stop lands.
  Each gate job writes, scans and uploads `key-credit-probing-<workflow>-<key-job>` right after
  the gate step, kept one day, with the runner's token and no added job permission.
  pr-review-main's gate job checks nothing out, so it scans with ci-workflows' `scan-upload`.
  The gate makes a second artifact-list call in recovery. pr-verify's other ci-workflows actions
  move to the same pin, which brings in run-claude-cli's limit-stop handoff for a token leg that
  timed out under a rejected rate limit.
