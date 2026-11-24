---
bump: minor
---

### Changed

- The babysit merge gate reads the Dependabot policy (`components/dependabot-policy/policy.json`) from the repository `standards_repository` names in `docs/conventions/source-control.yaml` whenever that key is set, whatever `trusted_actors_source` says; the trusted-actors list still moves there only with `trusted_actors_source: standards`. A repository with neither key reads its `.github/standards/` copies as before, and a `standards_repository` that is not an `owner/repo` pair fails the policy read, so the lane merges no Dependabot update.
- `config-resolution.md` and the `trusted_actors_source` schema description state that setting `standards` widens which pull requests the babysit lane adopts and merges unattended, so a repository beyond claude-code-plugins and pr-pipeline-sandbox sets it only with an owner-decisions row approving it.
