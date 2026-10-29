---
bump: patch
---

### Changed

- `CHECK_SKILL_SKIP_SCRIPT_TESTS=1` skips check 7, the skill's `scripts/*.test.sh`, with a note

  The repository's `scripts/check-affected.sh` sets it without `--tests`, so the pre-push hook's lint tier no longer runs a changed skill's script suites; the test tier and CI's test lanes still run them. On a babysit-prs change that was `engine.test.sh`, most of the hook's time.
