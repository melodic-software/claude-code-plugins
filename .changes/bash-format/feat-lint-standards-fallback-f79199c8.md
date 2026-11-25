---
bump: minor
---

### Added

- In a repository whose `docs/conventions/source-control.yaml` names a `standards_repository`, the git-hook lint entry uses that repository's lint config from a local checkout (`STANDARDS_DIR`, else `<ghq root>/github.com/<owner>/<repo>`): typos and markdownlint-cli2 take it as the base the repository's own config merges over; ShellCheck and actionlint use it when the repository has no config of its own.
