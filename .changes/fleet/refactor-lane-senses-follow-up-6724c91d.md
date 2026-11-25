---
bump: patch
---

### Changed

- **`/fleet:reach` calls one Claude Code install with its own sign-in an install.** "Lane" now
  means only a worker that serves one pipeline stage. The skill, its relay reference, the README,
  the manifest description and the eval cases say install; the eval cases
  `reach-peer-tools-stay-in-install`, `reach-same-machine-windows-install` and
  `reach-same-repo-session-picks-install` are renamed to match. `fleet-converge <lane>` keeps the
  argument name dotfiles gives it.
