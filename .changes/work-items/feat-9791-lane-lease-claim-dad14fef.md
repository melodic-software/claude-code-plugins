---
bump: minor
---

### Added

- The work-items tracker's GitHub `claim` takes `--lease-only` and `--holder <h>`, and `release` takes `--holder <h>`. A lease-only claim posts the lease comment and assigns no one, and `--holder` names the holder where `gh api user` cannot run, such as on a GitHub App installation token. The default stays the authenticated login with assignment, and arbitration stays by lease-comment order, so a local claim backs off while a lane lease is live.

### Fixed

- A lease comment from outside the repository's owners, members and collaborators (other than `github-actions[bot]`) no longer counts, and a lease renewed more than 300 s ahead or with a TTL over 168 h is not live, so a planted comment cannot block an issue.
