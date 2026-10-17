# Merge Dependabot pull requests in the pr-merge lane

- Status: accepted
- Date: 2026-10-16
- Related: [ADR 0048](0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md)
  (changelog fragments for Dependabot updates),
  [ADR 0049](0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)
  (lane hardening), ADR 0074 (the pr-unblock lane's review-dependency activity, #7698). The
  rules are in
  [`docs/conventions/pr-pipeline/README.md`](../conventions/pr-pipeline/README.md#dependabot-pull-requests).
  Supersedes, for this repository, the human merge lane the `melodic-software/standards`
  dependabot-policy component gives every Dependabot pull request outside the `vendor-actions`
  group; a standards pull request follows.

## Context

The owner decided that no Dependabot pull request may wait on a human: "AI is smart enough to know
if a dependabot PR should be auto-merged or not. If there's any that you're like, 'Oh, we should
hold this back and make a human do it,' then have an AI do it." Asked whether the merge lane may
merge a risky Dependabot pull request (major version, unlisted publisher, or red CI) once the AI
review lane leaves a merge verdict, written by the automation-lanes App at the current head and
only after CI passes, the owner answered "Yes, merge on AI verdict".

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
merge in flight. Its eligibility refused every dependency-manager pull request. The pr-unblock lane
may not merge (one merge authority per repository).

## Decision

1. **The pr-merge lane is the one merge authority for Dependabot pull requests.** It lists them
   beside its own and runs the same gate on them, with Dependabot's own class in place of the
   closing-issue class.
2. **Two tiers, the same in both lanes.**
   - `auto`: every update is non-major (the first numeric version component does not change, and
     below 1.0 the second does not either); every `github_actions` update comes from the
     `actions`, `github` or `anthropics` publisher; and `ci-status` is not red. The updates come
     from the verified commit's `updated-dependencies` metadata when present, else the title or
     a group's body `Updates` lines; when both read they must agree.
   - `review`: anything else, including anything unreadable. The pr-unblock lane's
     review-dependency activity reviews it and posts a round marker; the pr-merge lane merges it
     only when the newest marker the lanes App authored names the current head with
     `verdict=merge`.
3. **CI is the gate.** Either tier merges only on a green `ci-status` at its head, with every
   commit a verified Dependabot commit, the repository's `[dependabot skip]` version-bump commit,
   or, after a review, the lanes App's verified `[dependabot skip]` fix commit. Because a commit's
   author is text anyone with write access can set, the repository activity API must show every
   push to the head branch by Dependabot (or the github-actions or lanes App push of its own
   commit), and the diff may touch only the manifests and lock files `.github/dependabot.yml`
   covers and `uses:`-only action repins. The class is C2,
   so the rung and its cap bind it, but no closing issue, denied-path rule or diff risk score
   applies: a workflow pin bump sits on `.github/**` by definition.
4. **Its own switch.** `merge.dependabot.mode` (`off`, `report`, `enforce`; absent is `off`)
   decides whether a Dependabot pull request writes, so it can merge while `merge.report-only`
   still holds the lane's own pull requests. This repository sets `enforce`.
5. **`pr-automerge-dependabot.yml` is removed.**

## Alternatives considered

- **Keep the `GITHUB_TOKEN` arm and add a dispatch.** The arm cannot start the queue's checks, and
  a second merge path beside the lane would break the one-authority rule.
- **Flip `merge.report-only` to false.** That would also start unattended merges of lane-authored
  pull requests, a separate decision the owner has not made.
- **Let the review activity merge its own verdicts.** pr-unblock may not merge; keeping one
  authority keeps one kill switch, one in-flight rule and one post-merge check over every merge.
- **Hand review-tier pull requests to a human.** The owner rejected it.

## Consequences

- Non-major Dependabot bumps land without a human, one at a time, each verified by the post-merge
  full run like any lane merge. Major and unlisted-publisher bumps land on an AI review verdict.
- A compromised upstream release that passes `ci-status` (and, for a review-tier one, the review)
  can merge without a person reading it. The cooldown in `.github/dependabot.yml`, the signature,
  pusher and content checks, the head-bound marker and the post-merge demotion bound that risk.
  The content check does not read inside a manifest: a `package.json` script or a requirements
  index option rides along, which CI and the review tier must catch.
- The two lanes' classifiers must change together; a mismatch leaves a pull request with no owner.
- `.github/standards/runner-policy/policy.json` still admits the removed caller's reusable
  workflow; that file is synced from standards and changes there.
