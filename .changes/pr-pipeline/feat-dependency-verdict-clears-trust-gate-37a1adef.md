---
bump: minor
---

### Added

- `CI Status`'s trust-gate hold clears for a Dependabot pull request whose every change swaps an action's pinned SHA for a commit a tag of that action's repository points to, whatever the owner, once the lanes App's newest review-dependency round marker names the current head with `verdict=merge` (owner decision 2026-11-23, [#18492](https://github.com/melodic-software/claude-code-plugins/issues/18492)). The owner-list exception and this one share one shape and tag check. Until the verdict, the hold reads `#<n> by Dependabot swaps only action refs, each to a tagged commit, on trust-gate paths`; `review-dependency-select` sends that hold to the model instead of skipping it `gate-hold`, with `merge_clears_gate_hold: true` in `dependency.json`, and the pr-unblock dispatcher re-runs the head's `CI Status` job once a merge marker newer than it stands.
