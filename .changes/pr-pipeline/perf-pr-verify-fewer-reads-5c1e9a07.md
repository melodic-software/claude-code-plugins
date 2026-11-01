---
bump: patch
---

### Changed

- pr-verify's check-intent job reads less of the `GITHUB_TOKEN` budget, and judges every head the same. The resolver's spec read now also carries the relink fields (body edits, issue connects and disconnects) and, for a pull request whose body may be its spec, the first page of its title renames, so neither is a read of its own. A missing or malformed folded field fails closed as the separate read did, and a spec read that fails still falls back to the relink read. heldOnly and draftRun share one read of the upstream run's jobs, and the resolver keeps that list in `RUNNER_TEMP`, which `upstream-jobs.mjs` takes instead of reading it again (it reads as before when the file is missing, for another run, or malformed). Across the resolver and `upstream-jobs.mjs`, an unjudged head takes 8 API calls instead of 10, a run red only on a hold 9 instead of 11, a trusted person's pull request whose body is its spec 7 instead of 10, and a head its FAIL already judged one fewer.
