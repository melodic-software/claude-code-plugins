---
bump: patch
---

### Changed

- pr-unblock's dispatch reads the Dependabot policy only from the standards checkout (`STANDARDS_DIR`) or `DEPENDABOT_POLICY`; with neither it reads no policy, so every Dependabot pull request is tier `review` with `dependabot-policy-unreadable`, instead of falling back to the base's `.github/standards/` copy.
