---
bump: minor
---

### Added

- babysit-prs: `babysit-postmerge.sh --preflight` runs the merge gate's identity and credential rules alone (the session acts as `merge.agent-identity` and holds no other account), and exits 0 or 2.
- `scripts/lane-push.sh`, the only way a lane pushes: it builds `https://github.com/<owner>/<repo>.git` from its arguments or a pull request's head (forks included), drops every `GIT_*` variable, ignores global and system git config, forces gh as the only credential helper and https as the only transport, refuses on local `url.*`, `include*`, `credential.*`, `http.*` and unsafe `remote.*` keys and on any acting login but the one named, and pushes `HEAD:refs/heads/<branch>` fast-forward only. `--check` runs every refusal but the push.
- babysit-loop: where the target names a `merge.agent-identity`, the lane launches with that identity's token as its only GitHub credential, and an identity gate at the start of every cycle reads `pr-pipeline.yaml` from the target's default branch and stops the lane before any write when the preflight refuses or the config is unreadable. The durable state block carries a `demotion_events` total.

### Changed

- babysit-prs: `lane_push`, the fix worker and the conflict-resolution push all push through `lane-push.sh --pr <N>`, never a bare `git push`; the checkout no longer resolves a push remote, so a remote or `pushRemote` that `gh pr checkout` wrote is never pushed to. The watched-owners trust boundary for fork heads is unchanged.

- babysit-loop: a merge-eligible pull request merges only through the gate's `--unattended --merge`, never `--auto`; the post-merge check always passes `--remediate`, since that cycle's identity gate established the identity.
- babysit-prs: "Merge-lane auto-merge" becomes "Merge lane: no auto-merge". A lane-pinned invocation merges only through `--unattended --merge`; otherwise it reports the PR merge-ready for a human. No guidance arms or re-arms auto-merge, and the GitHub arm command is gone.
