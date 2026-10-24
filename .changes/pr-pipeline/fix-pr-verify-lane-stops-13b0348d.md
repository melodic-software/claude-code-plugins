---
bump: minor
---

### Changed

- A trusted spec edit after a pass no longer strands the head at `verify:spec-changed`. `resolve-pr.mjs` judges a head again, with reason `spec-changed`, when every counted pass there started before the spec's last change (an issue body edit, a spec comment added or edited, or a body edit of a pull request that is its own spec), and the lost-run reconciler re-runs, once and with a record, the passed `pr-require-checks` run of such a head so pr-verify starts. The gate decides on the passes of the pr-verify run that started last, so the new verdict replaces the stale one. Each passed checks run is re-run once; a changed closing set and a removed spec comment still wait for a person.
- The verifier prompt no longer fails a pull request for touching workflows, CI, hooks, scripts, agent instructions, package manifests, lockfiles, path or file-type refusals, a `merge: human` setting, deploys, cloud, releases or other repositories; those are judged as ordinary code. It fails a change to the takeover set (the trusted-actor list, the `check-trusted-trigger`, `check-kill-switch`, `request-lane-token` and `resolve-config` actions, `CODEOWNERS`, submodules) whatever the spec says, unrequested work that loosens a hold the owner keeps (outside-organization work, cost and billing, rate, capacity, work-in-progress and round caps), and unrequested work on secret values or organization or repository settings.
- Spec trust is unchanged: text the lanes App wrote, an issue it filed or intake triage's refinement comment included, is still not spec. Trusting it is held for an owner decision.
