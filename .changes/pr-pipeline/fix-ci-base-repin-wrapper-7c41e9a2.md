---
bump: minor
---

### Changed

- `verify-scripts` may be set on a `prepare: ci-context` skill. The read runner stages each listed script's base copy behind its wrapper under `.lane/verify`, read-only and denied to the file tools, and the preamble tells the skill to run those scripts only through the wrappers. `fix-ci` lists `plugins/planning/scripts/repin-digests.sh`, so the instructed route for re-pinning a digest pin the pull request's own diff moved is the base's script. That is an instruction, not a rule: `ci-context` keeps Bash, Edit and Write unrestricted, so the controls on a re-pin are review of the patch and apply-patch's `ci-context` patch rules.
