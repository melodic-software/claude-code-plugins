---
bump: minor
---

### Added

- **The `audit` and `realign` headers say when the loading-mechanics record is older than the installed CLI ([#6100](https://github.com/melodic-software/claude-code-plugins/issues/6100)).** `scripts/precompute.sh` compares `claude --version` with the newest version named in a `*(measured ...)*` marker of `context/verified-mechanics.md` and prints `Mechanics record: STALE` when the CLI is newer, `not stale` when it is the same or older, and `unchecked` when either version is unreadable. Both skills put a `STALE` or `unchecked` line in front of what they report, so a proposal priced on mechanics measured on an older CLI says so. Versions from changelog-only markers never count as measurements. The `delta` and `setup` headers share the audit mode, so the line appears there as well, with no instruction to act on it. On Claude Code 2.1.296 the shipped record (newest measurement 2.1.278) reads `STALE`, which is the trigger the record's re-verification section names.

### Changed

- **One version comparator.** `cutover-check.sh` and `remove-shims.sh` each carried their own copy of the dotted-version comparison; both now source `scripts/lib/version.sh`, which `precompute.sh` uses too. A copy missing the lib exits 2, and a version component that is not a number now fails the comparison instead of being evaluated as bash arithmetic.
