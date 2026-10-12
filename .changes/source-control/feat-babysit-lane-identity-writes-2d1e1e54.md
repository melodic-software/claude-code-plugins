---
bump: minor
---

### Added

- babysit-prs: `babysit-postmerge.sh --preflight` runs the merge gate's identity and credential rules alone (the session acts as `merge.agent-identity` and holds no other account) plus a push-path check (every push URL is https to `github.com` with no embedded credential, gh is the only credential helper for it, no `http.extraHeader` applies), and exits 0 or 2.
- babysit-loop: where the target names a `merge.agent-identity`, the lane launches with that identity's token as its only GitHub credential, and an identity gate at the start of every cycle reads `pr-pipeline.yaml` from the target's default branch and stops the lane before any write when the preflight refuses or the config is unreadable. The durable state block carries a `demotion_events` total.

### Changed

- babysit-loop: a merge-eligible pull request merges only through the gate's `--unattended --merge`, never `--auto`; the post-merge check always passes `--remediate`, since that cycle's identity gate established the identity.
- babysit-prs: "Merge-lane auto-merge" becomes "Merge lane: no auto-merge". A lane-pinned invocation merges only through `--unattended --merge`; otherwise it reports the PR merge-ready for a human. No guidance arms or re-arms auto-merge, and the GitHub arm command is gone.
