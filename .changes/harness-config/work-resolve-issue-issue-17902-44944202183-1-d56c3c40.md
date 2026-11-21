---
bump: minor
---

### Changed

- **The shared auto-mode drop patterns match the current eight-class list.** Package-runner rules
  now match with a path prefix or an `@<version>` suffix (`Bash(/usr/bin/npm run:*)`,
  `Bash(pnpm@9 dlx *)`), per changelog 2.1.327. New patterns cover a process wrapper followed only
  by a wildcard (`Bash(timeout *)`), shell rules that start with a wildcard (`Bash(* --version)`),
  and the two wildcarded-path forms the permission-modes page names (`$HOME`-led rules and Windows
  backslash programs other than `.\` paths). `audit-permission-grants` check P1 flags all of them,
  and the `audit-permission-state` entry diff names them as `wrapper-wildcard`,
  `leading-wildcard` and `path-wildcard`
  ([#17902](https://github.com/melodic-software/claude-code-plugins/issues/17902)).
