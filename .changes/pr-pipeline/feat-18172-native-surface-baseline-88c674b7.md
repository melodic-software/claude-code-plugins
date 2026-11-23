---
bump: minor
---

### Added

- The upstream changelog workflow checks the release's npm native build against `docs/upstream/claude-code-native-surfaces.min.json`. A changed passing summary opens a baseline-only pull request, ready for review, in two jobs, `push-native-baseline-branch` and `publish-native-baseline-pr`, each with its own broker token. A lanes App pull request whose changed files are exactly that baseline merges unattended with no linked issue and no pr-verify verdict (owner decision Q152 (B)): pr-verify skips it, and enable-auto-merge and ci-status's merge-queue step take it without one. Its risk score, the clean security review that clears the `docs/upstream/**` review path, and every other hold still apply. The host fallback is changelog apply Phase 5 in the harness-ops plugin.
