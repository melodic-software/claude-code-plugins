---
bump: minor
---

### Changed

- The babysit merge gate trusts a vendored-copy upstream-drift issue as it trusts a hex-pin one: github-actions[bot] wrote it, nobody else last edited it, its title is `Upstream drift: <id>` and its first body line is the filer's vendored-copy lead for that id. It counts only for a pull request whose changed files, renames' old paths included, all sit under the plugin that id's row in the default branch's `scripts/upstream-drift-vendored-report.sh` names, or under that plugin's `.changes/` fragments, matching pr-verify's `driftSpec`. An id no row names, that two plugins claim, or with a row lacking the `files-only` mark (its update may install a package) is not trusted.
