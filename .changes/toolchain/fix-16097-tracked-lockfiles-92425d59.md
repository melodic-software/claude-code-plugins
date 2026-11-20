---
bump: patch
---

### Changed

- Resolution ladder: an unattended run picks the package manager for a `package.json` script only from lockfiles `git ls-files` lists, so a lockfile left untracked in the working tree no longer names a package manager or ties two of them. Outside a git repository, or when git cannot list the files, every lockfile present still counts.
