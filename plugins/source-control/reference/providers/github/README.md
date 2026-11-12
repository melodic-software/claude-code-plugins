# GitHub provider reference

The `source-control` skill bodies name operations (open a draft change request, read its checks,
reply on a review thread). This file is how GitHub, the one forge the plugin supports today, does
each with the `gh` CLI. Read it before a skill's first forge operation. Skill bodies stay
forge-neutral and the provider detail lives here per
[ADR 0060](../../../../../docs/adr/0060-abstract-provider-details-in-skills-behind-consumer-conventions-and-adapters.md).

This file indexes operations to commands; a skill's spoke is the authority on the full step around
each. A spoke whose steps need more than a table row has a provider file of the same name under a
directory named for its skill: [`pull-request/`](pull-request/) holds the GitHub commands, scripts
and `gh` facts behind the pull-request skill's `create.md`, `ready-for-review.md`, `monitor.md`,
`readiness.md`, `merge.md` and `review-venue.md`, and each spoke links its steps there. The worktree
skill's spokes need only the rows below. The babysit-prs and babysit-loop skills' spokes link
their commands in [`babysit-prs/`](babysit-prs/) and [`babysit-loop/`](babysit-loop/).

A pull request is GitHub's change request; this file uses its terms.

## Identity and repository

| Operation | GitHub command |
|---|---|
| The current login | `gh api user --jq .login` |
| The current repository as `owner/repo` | `gh repo view --json nameWithOwner -q .nameWithOwner` |
| The repository's default branch | `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`; in a sandboxed session, `gh api "repos/{owner}/{repo}" --jq '.default_branch'` |
| Read a tracked file from a repository's default branch | `gh api repos/<owner>/<repo>/contents/<path>` (the `content` field is base64) |

### Target repository

A `gh` command given no repository does not simply use `origin`. It takes `-R` or `GH_REPO`
first, then the remote `gh repo set-default` recorded, and without either, when it cannot
prompt (an agent's shell, or any `$(...)` capture), the first remote in its own order by remote
name, where `upstream` comes before `origin`. A stock `gh repo clone` of a fork records `upstream`
as the default. So in a fork checkout a bare write can land on the upstream repository.

Each phase that writes resolves the repository once, before its first write (ready and evidence
before their first read too), with `bash "<skill-dir>/scripts/target-repo.sh" [--dir <checkout>]`
(the pull-request skill's script), reports the `target repository:` line it prints, and targets
that repository with every later read and write of the phase. Each write names it:
`-R <owner>/<repo>` on `gh pr` and `gh issue`, `repos/<owner>/<repo>/...` on `gh api`, as
[merge](pull-request/merge.md#merge-command) already does. A phase that runs shell blocks also
exports `GH_REPO` with it, which every other `gh` call follows, the scripts the phase runs
included, and which `{owner}/{repo}` placeholders expand from. `gh repo view` with no argument
ignores `GH_REPO` (gh 2.103.3), so a script that needs the repository reads
`gh api 'repos/{owner}/{repo}' --jq .full_name` instead. The script resolves in this order:

1. `GH_REPO`, when set: the caller's explicit choice, or the repository an earlier block resolved.
2. When the remotes name two or more github.com repositories, the fork among them: a remote's
   repository the caller can push to (`.permissions.push`) whose parent (`.parent.full_name`,
   both from `gh api repos/<owner>/<repo>`) is the recorded default or another remote's
   repository, `origin` checked first. A fork checkout works on the fork, even when a stock fork
   clone recorded upstream as gh's default; a contributor's fork added as a remote does not
   capture a maintainer's writes. A failed read of a repository stops the script with exit 1.
3. The recorded default.
4. The one github.com repository the remotes name.
5. With no github.com remote, gh's own resolution.

It refuses when the remotes cannot decide: two or more github.com repositories, none a fork of
another that the caller can push to, and no default recorded. It then prints the `gh repo set-default <owner>/<repo>` fix,
and the refusal stops the phase: which repository is the target is the user's choice, not the
script's. A pull request meant for upstream from a fork names its base repository explicitly
([out-of-tree create](pull-request/create.md#open-the-pr-from-an-out-of-tree-orchestrator),
triangular flow).

- **Pointer**: [`gh repo set-default`](https://cli.github.com/manual/gh_repo_set-default),
  [`gh repo clone`](https://cli.github.com/manual/gh_repo_clone) and
  [`gh help environment`](https://cli.github.com/manual/gh_help_environment) (`GH_REPO`).
- **As of**: 2026-11-11, gh 2.103.3.
- **Recheck trigger**: a gh release note that changes how commands pick the base repository or
  what `gh repo set-default --view` prints.

## Resolve a pull request

| Operation | GitHub command |
|---|---|
| The current branch's PR number | `gh pr view --json number -q .number` |
| The same, with the branch named (ambiguous or stale checkout) | `gh pr view "$(git branch --show-current)" --json number -q .number` |
| State for the smart default | `gh pr view --json state,number,isDraft` (non-zero exit: no PR) |
| The current branch's PR with author and head branch (babysit-prs single-PR scope) | `gh pr view --json number,url,author,headRefName` |
| Number, URL and state for `status` | `gh pr view <N> --json number,url,state` |
| Head commit | `gh pr view <N> --json headRefOid -q .headRefOid` |
| Mergeability | `gh pr view <N> --json mergeable`; `CONFLICTING` means GitHub runs no workflows until the base is integrated |
| The PR for a branch | `gh pr list --head <branch> --json number,title,state` |
| Whether a branch's PR merged (worktree cleanup) | `gh pr list --state merged --head <branch>`; a non-empty result means merged |
| PRs for worktree cross-reference (one call per worktree branch, all states) | `gh pr list --head <branch> --state all --json number,title,state,headRefName`; a PR whose head is `<branch>` is a match, and a failed call marks that branch's PR lookup incomplete |
| Your own open PRs here | `gh pr list --state open --author "@me" --json number` |
| Your own open PRs across an owner | `gh search prs --state open --author @me --owner <owner> --json repository` |

`gh pr view` with no number resolves by the checked-out branch. Resolve the number once at phase
entry and pass it to every later `gh` call in that phase.

## Change the pull request

| Operation | GitHub command |
|---|---|
| Open a draft PR | `gh pr create -R <owner>/<repo> --draft` (with `--head <branch>` on the PR-only entry), never `--reviewer` |
| Check out the PR head | `gh pr checkout <N>`, or `gh pr checkout <N> --detach` when the branch is locked in another worktree. It is fork-safe: a fork's head branch is not fetchable from `origin` by name |
| Merge the base into the head | `gh api --method PUT repos/<owner>/<repo>/pulls/<N>/update-branch -f expected_head_sha=<sha>`, pinned to the decision's head (pull-request `ready-for-review.md`) |
| Flip a draft ready | `gh pr ready <N> -R <owner>/<repo>`, run only inside `/source-control:pull-request ready`, never bare |
| Merge a PR | `gh pr merge <N> -R <owner>/<repo>` with the PR number and repository written literally, plus the flags the repository needs: `--squash`, `--auto` on a merge-queue or auto-merge base, `--admin` only where a code-owner review or merge queue blocks an otherwise ready merge and the consumer's policy allows it; `--match-head-commit <sha>` is optional for an immediate merge and required with `--auto`. A refused merge is reported, never handed to the user or retried in another shape ([pull-request/merge.md](pull-request/merge.md#merge-command); pull-request `merge.md` §4.2.1 owns when to merge without asking). A babysit lane merges only through its merge-gate wrapper (babysit-prs `safety.md`) |
| Open a tracking issue | `gh issue create -R <owner>/<repo>` |

## Checks and CI logs

| Operation | GitHub command |
|---|---|
| List the PR's checks | `gh pr checks <N>`; never `--watch`, which blocks the foreground |
| CI logs, last resort | `gh run view --log-failed`, which truncates around 4 MB at the CLI display layer ([cli/cli#11059](https://github.com/cli/cli/issues/11059), [#10551](https://github.com/cli/cli/issues/10551), [#7771](https://github.com/cli/cli/issues/7771)); the `fetch-logs` action's annotation and archive paths return complete data |

A workflow that exchanges an OIDC token fails when the PR modifies that workflow file: the file
must match the default branch for the exchange to succeed. Classify that failure as informational.

## Review surfaces

GitHub splits PR feedback across three surfaces, each paginated at 30 items per page, oldest first.
Pass `--paginate` and `per_page=100` on every read, or the newest item (usually your own reply) is
missed.

| Surface | Read |
|---|---|
| Inline review-thread comments | `gh api --paginate "repos/<owner>/<repo>/pulls/<N>/comments?per_page=100"` |
| Conversation (issue-level) comments, where AI-review summaries land | `gh api --paginate "repos/<owner>/<repo>/issues/<N>/comments?per_page=100"` |
| Reviews (bodies of APPROVED, CHANGES_REQUESTED and COMMENTED reviews) | `gh api --paginate "repos/<owner>/<repo>/pulls/<N>/reviews?per_page=100"` |

Round scoping: inline comments carry `original_commit_id`, reviews carry `commit_id`, and
conversation comments carry only `created_at`.

| Operation | GitHub command |
|---|---|
| React to a comment | `POST` to the comment's `/reactions` endpoint (`+1`, `-1`, `eyes`); verify with a `GET` on the same endpoint. Review bodies have no reactions endpoint |
| Reply on an inline thread | `gh api repos/<owner>/<repo>/pulls/<N>/comments/<id>/replies -F body=@<body-file>` |
| Reply on the conversation | `gh pr comment <N> -R <owner>/<repo> --body-file <body-file>` |
| Verify an inline reply | the inline surface filtered with `--jq '.[] \| select(.in_reply_to_id == <original-id>)'` |
| Verify a conversation reply (D5, before any fix) | the conversation surface filtered with `--jq '.[] \| select(.user.login == "<posting-identity>") \| .body'` |
| Verify a follow-up reply citing the fix | the conversation surface filtered with `--jq '.[] \| select((.body \| contains("<sha>")) and .user.login == "<posting-identity>") \| .body'`, never `.[-1]` |
| Tell a bot from a person | REST `user.type == "Bot"`; GraphQL `author.__typename == "Bot"` |
| Resolve a review thread | the GraphQL `resolveReviewThread` mutation, then confirm `isResolved == true` over GraphQL |

Write a reply body to a file with the Write tool and pass the file: a reply often quotes reviewer
text, and a quote, `$(…)` or backtick inside it can break out of an inline shell argument.

## Branch rules

| Operation | GitHub command |
|---|---|
| Effective rules on a branch | `gh api repos/<owner>/<repo>/rules/branches/<branch>` |
| Classic protection fallback | `gh api repos/<owner>/<repo>/branches/<branch>/protection` |
| Whether head branches are deleted on merge | the repository's `delete_branch_on_merge` field: `gh api repos/{owner}/{repo} --jq '.delete_branch_on_merge'` |

## Sandboxed sessions: GraphQL is unavailable

A cloud session behind the GitHub proxy is served no GraphQL operation: every GraphQL request gets
`HTTP 403`, whatever token is set. Pointer:
[Configure cloud environments § GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy).
As-of: 2026-10-11. Recheck trigger: that section changes its GraphQL entry, or a release note names
the GitHub proxy. `gh pr view --json`, `gh repo view --json`, `gh pr create`, `gh pr ready`
and `gh pr merge` all run over GraphQL. The 403 looks like an expired token or a missing scope but
is neither: switch to the REST route the spoke names rather than re-authenticating. Probe
read-only:

```bash
gh api graphql -f query='query{viewer{login}}' --jq '.data.viewer.login'
```

A login means GraphQL is served. Under the restriction, the babysit engine re-sources the
`gh pr view` bundle over REST (`GET …/pulls/{n}` plus the commit check-runs and combined-status
endpoints), so discovery, classification, branch-rule and freshness checks keep working.
Review-thread resolution has no REST equivalent and is not approximated: the merge gate reports
`threadResolutionProven: false` and `unresolvedThreadCount: null` and holds the PR as readiness
UNPROVEN. `reviewDecision` degrades the same way, because REST can prove `CHANGES_REQUESTED` but
not an approval (GitHub folds CODEOWNERS and the required-reviewer count into that field). The same
restriction is handled in the pull-request skill's `create.md` §2.4.0 and the
[work-item-tracker GitHub adapter](../../../../work-items/tools/work-item-tracker/adapters/github/README.md).

## Draft stage

A draft cannot merge until it is marked ready
([changing the stage of a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/changing-the-stage-of-a-pull-request)).

## API budget

Every `gh` call by every agent and session under one user shares that user's hourly budget: 5,000
REST requests and 5,000 GraphQL points. `gh` never retries or backs off. Every unattended loop
follows this cadence:

- **Which bucket.** GraphQL: `gh pr view`, `gh pr list`, `gh pr checks` (`--watch` re-queries every
  10 s), `gh pr create`, `edit`, `ready` and `merge`, `gh issue`, `gh api graphql`. REST: `gh run`,
  `gh api <path>`.
- **Waiting.** One watcher per PR or run, in the background, polling at 60 s or longer:
  `gh run watch <id> --exit-status -i 60` (the default is every 3 s), or REST reads of
  `repos/<owner>/<repo>/pulls/<n>` and `commits/<sha>/check-runs`. Never loop `gh pr view` and
  never run `gh pr checks --watch`. 60 s is a floor per watcher, not a budget: with several
  watchers, poll every 2 s × watchers × requests per poll or slower, which keeps them near a third
  of the hourly REST budget (ten pull-request monitors at about seven requests a poll: 140 s,
  set as the monitor's `INTERVAL`).
- **GraphQL-only fields** (`isInMergeQueue`, `statusCheckRollup`): read once, at the point you
  decide.
- **Writes.** One at a time, at least 1 s apart, never in a retry loop. Secondary limits cap
  content-creating requests at 80 a minute and 500 an hour, and all requests at 100 concurrent.
- **Rate-limit errors.** Stop at the first one; never retry in a loop or probe for recovery. Wait
  until `x-ratelimit-reset`, or `retry-after` when a secondary limit sends it, else at least one
  minute, then back off exponentially and give up after a few tries. `gh api rate_limit` does not
  show secondary limits and can count against them.

Pointer: [best practices for using the REST API](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api),
[REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api),
[GraphQL rate limits](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api).
As-of: 2026-10-17. Recheck trigger: either rate-limits page changes a figure, or a `gh` release
changes the `run watch` or `pr checks --watch` interval or adds retries.
