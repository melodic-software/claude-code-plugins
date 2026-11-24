---
bump: patch
---

### Changed

- The synced copies `.github/standards/trusted-actors/` and `.github/standards/github-actions-conventions/` are gone: standards no longer syncs them (melodic-software/standards#1127), and every reader takes both lists from the standards checkout. `resolve-config` without `standards-path` (`STANDARDS_DIR`) now loads no vocabulary, so it rejects the config instead of reading the base copy; `pr-verify`'s probe replay needs `STANDARDS_DIR`. Tests read a captured standards checkout under `.github/scripts/lib/fixtures/standards/`.
- ci-status no longer holds a lanes App pull request that widens `.github/standards/trusted-actors/trusted-actors.json`, and the review callers' `hold-paths` drop `.github/standards/trusted-actors/**`: the list lives in melodic-software/standards, whose `CODEOWNERS` owns `components/trusted-actors/`.
