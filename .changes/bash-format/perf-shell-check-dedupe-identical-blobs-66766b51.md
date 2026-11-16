---
bump: patch
---

### Changed

- The pre-commit check runs ShellCheck once per distinct staged script instead of once per path, and reports each finding under every path that holds the same bytes, so each copy's own added lines still decide what blocks. Copies are linted together only when nothing else ShellCheck reads can differ between them: the same extension and the same nearest `.shellcheckrc`, and, for copies in different directories, a probe that finds no `source` statement (a `SCRIPTDIR` search path resolves those from each script's own directory). A commit that changes 21 identical copies of a 5,174-line script lints that script once.
