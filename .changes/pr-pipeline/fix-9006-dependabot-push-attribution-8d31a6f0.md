---
bump: patch
---

### Fixed

- The pr-unblock verdict job's merge path checks who pushed each commit before it posts a merge marker ([#9006](https://github.com/melodic-software/claude-code-plugins/issues/9006)). `pushRefusal` in `dependency-classify.mjs` (the twin of pr-merge's `push_refusal`, with one-for-one `PUSH_VECTORS` in both test suites) reads the head branch's repository activity back to Dependabot's newest branch creation or force push. Each commit a push brought must be its pusher's own: Dependabot's in a `dependabot[bot]` push, the version-bump commit in a `github-actions[bot]` push, a lanes App commit in a lanes App push. Anything else escalates `dependency-fix-refused`, so a Dependabot-authored commit under a lanes App tip no longer gets a merge marker. The README's **Pushes** check states the rule for both lanes.
