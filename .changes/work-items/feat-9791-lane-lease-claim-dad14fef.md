---
bump: minor
---

### Added

- The work-items tracker's GitHub `claim` takes `--lease-only` and `--holder <h>`, and `release` takes `--holder <h>`. A lease-only claim posts the lease comment and assigns no one, and `--holder` names the holder where `gh api user` cannot run, such as on a GitHub App installation token. The default stays the authenticated login with assignment, and arbitration stays by lease-comment order, so a local claim backs off while a lane lease is live.
