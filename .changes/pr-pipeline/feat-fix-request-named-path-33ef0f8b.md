---
bump: minor
---

### Added

- address-feedback: a fix request by a trusted person with write access may name files to add to
  its thread's scope. The select step reads each file-shaped word of the request outside fenced
  code and quoted lines, from the repository root when it holds a `/` and from the thread path's
  directory when it does not, and records it in the thread's `named_paths` when it is in the same
  `plugins/<p>/` directory as the thread's path, in normal form, not under `.github/`, not an
  instruction path, and a regular file at the gated head (ten per thread at most). The promote
  step and the reply job accept changes to those files.

### Fixed

- A plugin's `.mcp.json`, `.gitmodules` or `CODEOWNERS` is no longer in the plugin-wide part of a
  kept thread's scope.
- The instruction paths `apply-ci-fix` and address-feedback refuse now also cover a `hooks`,
  `.claude` or `.claude-plugin` segment with nothing after it, a plugin's `monitors/` and `bin/`,
  and `.lsp.json`; a thread's plugin-wide scope also refuses `.bash`, `.zsh`, `.ps1`, `.cjs`,
  `.mts` and `.cts` files and any path with a character outside ASCII letters, digits and `_@+.-`.
- The address-feedback promote step moves the PR branch only when every path the lane branch
  adds or changes is a regular file at its tip, not a symbolic link or gitlink.
