---
bump: minor
---

### Changed

- The babysit merge gate reads the Dependabot policy only from the repository `standards_repository` names in `docs/conventions/source-control.yaml`, never from the repository's `.github/standards/dependabot-policy/policy.json` copy. A repository that sets no `standards_repository` gets `dependabot-policy-unreadable`, so the lane merges no Dependabot update there until it names its standards repository.
