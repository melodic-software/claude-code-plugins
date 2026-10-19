---
bump: minor
---

### Added

- `setup wsl-profile`: prints an opt-in WSL hardening settings block (`Read` deny rules for Linux secret stores, `Edit` deny rules for the Windows host's Claude config using `//` paths, a pinned `env.TMPDIR`) with the running user's paths filled in, and writes nothing. `reference/wsl-profile.md` documents the detection rule, the limits of deny rules and the host steps; `wsl-profile.sh lint` fails on any `Write(path)` rule or non-`//` path rule.
