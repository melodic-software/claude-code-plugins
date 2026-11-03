---
bump: patch
---

### Fixed

`/firecrawl:update --apply` no longer records the wrong CLI version or rollback target when something other than npm owns the `firecrawl` command. It exits 2 before installing, writing nothing and naming the command's path, when the command resolves outside npm's global bin, and it exits 2 without writing `upstream.md` when the command does not read npm latest after the install. The skill's rollback line now says to update the owner's pin in that case.

The update flow now runs `--apply`, which records only the CLI version and rollback target. A new `--record-upstream` mode records the upstream SHA after Gate 2 or when there was no content delta, installing nothing, so a declined or abandoned Gate 2 keeps showing as drift in `--check`.
