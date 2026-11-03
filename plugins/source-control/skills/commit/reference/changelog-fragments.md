# What the changelog-fragment step writes

Detail behind Task step 7 in [SKILL.md](../SKILL.md), which runs
`write-changelog-fragments.sh` with the drafted message.

For each listed plugin the staged change touches, it writes the fragment in place of the hand
version bump and CHANGELOG entry, through the repository's own `new-changelog-fragment.sh`.
The bump comes from the Conventional Commits type: `feat` minor; `fix` and `perf` patch;
`build`, `chore`, `ci`, `docs`, `refactor`, `style` and `test` none; `!` or a `BREAKING CHANGE`
footer major. The subject and body go under `### Added` (`feat`), `### Fixed` (`fix`) or
`### Changed` (anything else), and a `none` fragment gets one line saying why no release is
needed. A later commit on the branch with a releasing type adds its entry to the branch's fragment and raises the
bump only upward. On exit 2 for a subject it cannot map, rerun with
`--level major|minor|patch|none`. In a repository without the list, and for a plugin the list
does not name, it writes nothing, and the repository's own release record (a version bump plus
CHANGELOG entry) still applies.
