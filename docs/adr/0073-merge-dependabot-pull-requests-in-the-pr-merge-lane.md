# Merge Dependabot pull requests in the pr-merge lane

- Status: accepted
- Date: 2026-10-16
- Related: [ADR 0048](0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md)
  (changelog fragments for Dependabot updates),
  [ADR 0049](0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)
  (lane hardening). The rules are in
  [`docs/conventions/pr-pipeline/README.md`](../conventions/pr-pipeline/README.md#dependabot-pull-requests).
  Supersedes, for this repository, the human merge lane the `melodic-software/standards`
  dependabot-policy component gives every Dependabot pull request outside the `vendor-actions`
  group; a standards pull request follows.

## Context

The owner decided that no Dependabot pull request may wait on a human.

Until now two paths existed. `pr-automerge-dependabot.yml` armed GitHub auto-merge with
`GITHUB_TOKEN` on non-major `vendor-actions` bumps, and every other Dependabot pull request waited
for a human to merge it once `ci-status` passed. The armed path never landed a pull request
through this repository's merge queue (#6717, #7512): GitHub's
[`GITHUB_TOKEN` page](https://docs.github.com/en/actions/concepts/security/github_token) says
"events triggered by the `GITHUB_TOKEN` will not create a new workflow run", and its exceptions
(`workflow_dispatch`, `repository_dispatch`, some `pull_request` activity) do not include
`merge_group`, so the queue entry the arm made never got its `ci-status` run.

The pr-merge lane already enqueues pull requests with the lanes App token from the broker, which
does start `merge_group` runs, behind the kill switches, the rung cap, the post-merge check and one
merge in flight. Its eligibility refused every dependency-manager pull request.

## Decision

1. **The pr-merge lane owns Dependabot merges.** It lists Dependabot's open pull requests beside its
   own and runs the same gate on them, with Dependabot's own class in place of the closing-issue
   class.
2. **Two tiers.** `babysit_dependabot.py` tiers each pull request from its title and commits:
   - `auto`: every commit is a GitHub-verified Dependabot commit, or the repository's
     `[dependabot skip]` version-bump commit (the shape `scripts/lib/changelog-fragments.sh`
     already accepts), and every update in the commit metadata is `semver-patch` or
     `semver-minor`, in any ecosystem;
   - `review`: anything else, including a major update, an unknown update type, any other commit,
     and a finished `ci-status` that did not succeed.
   A tier `auto` pull request merges once `ci-status` succeeded on its head and no hold applies.
   Tier `review` never merges in this lane; the pr-unblock lane's review activity takes it.
3. **CI is the gate.** The class is C2, so the rung and its cap bind it, but no closing issue,
   denied-path rule or diff risk score applies: a workflow pin bump sits on `.github/**` by
   definition, and Dependabot edits only manifests, lock files and pins.
4. **Its own switch.** `merge.dependabot.mode` (`off`, `report`, `enforce`; absent is `off`)
   decides whether a Dependabot pull request writes, so it can merge while `merge.report-only`
   still holds the lane's own pull requests. This repository sets `enforce`.
5. **`pr-automerge-dependabot.yml` is removed.**

## Alternatives considered

- **Keep the `GITHUB_TOKEN` arm and add a dispatch.** The arm cannot start the queue's checks, and
  a second merge path beside the lane would break the one-authority rule.
- **Flip `merge.report-only` to false.** That would also start unattended merges of lane-authored
  pull requests, a separate decision the owner has not made.
- **Allowlist publishers for tier `auto`.** The owner's decision covers every non-major bump; a
  publisher allowlist would send ordinary bumps to review. A failed `ci-status` and a major update
  still go to review.

## Consequences

- Non-major Dependabot bumps land without a human, one at a time, each verified by the post-merge
  full run like any lane merge.
- A compromised upstream release that passes `ci-status` can now merge without a person reading
  it. The cooldown in `.github/dependabot.yml`, the signature check on every commit, and the
  post-merge demotion bound that risk; the review tier covers majors.
- The class is a seam: the review activity reads the same tier and reason.
- `.github/standards/runner-policy/policy.json` still admits the removed caller's reusable
  workflow; that file is synced from standards and changes there.
