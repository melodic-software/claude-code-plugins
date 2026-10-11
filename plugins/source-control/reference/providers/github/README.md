# GitHub provider reference

The `source-control` skill bodies name operations (open a draft change request, read its checks,
reply on a review thread). This file is how GitHub, the one forge the plugin supports today, does
each of them, with the `gh` CLI. Read it before the first forge operation a skill performs. The
decision that skill bodies stay forge-neutral and the provider detail lives here is
[ADR 0060](../../../../../docs/adr/0060-abstract-provider-details-in-skills-behind-consumer-conventions-and-adapters.md).

The per-phase spokes under each skill's `reference/` directory (for example the pull-request
skill's `create.md`, `monitor.md`, `merge.md` and `readiness.md`, and the babysit-prs skill's
`loop.md` and `safety.md`) still carry their full GitHub procedures. This table is the index from
an operation to its command; a spoke is the authority on the full step around it.

A pull request is GitHub's change request; this file uses its terms.

## Identity and repository

| Operation | GitHub command |
|---|---|
| The current login | `gh api user --jq .login` |
| The current repository as `owner/repo` | `gh repo view --json nameWithOwner -q .nameWithOwner` |
| Read a tracked file from a repository's default branch | `gh api repos/<owner>/<repo>/contents/<path>` (the `content` field is base64) |

## Resolve a pull request

| Operation | GitHub command |
|---|---|
| The current branch's PR number | `gh pr view --json number -q .number` |
| The same, with the branch named (ambiguous or stale checkout) | `gh pr view "$(git branch --show-current)" --json number -q .number` |
| State for the smart default | `gh pr view --json state,number,isDraft` (non-zero exit: no PR) |
| Number, URL and state for `status` | `gh pr view <N> --json number,url,state` |
| Head commit | `gh pr view <N> --json headRefOid -q .headRefOid` |
| Mergeability | `gh pr view <N> --json mergeable`; `CONFLICTING` means GitHub runs no workflows until the base is integrated |
| The PR for a branch | `gh pr list --head <branch> --json number,title,state` |
| Every PR, one batched read for worktree cross-reference | `gh pr list --state all --json number,title,state,headRefName` |
| Your own open PRs here | `gh pr list --state open --author "@me" --json number` |
| Your own open PRs across an owner | `gh search prs --state open --author @me --owner <owner> --json repository` |

`gh pr view` with no number resolves by the checked-out branch. Resolve the number once at phase
entry and pass it to every later `gh` call in that phase.

## Change the pull request

| Operation | GitHub command |
|---|---|
| Open a draft PR | `gh pr create --draft` (with `--head <branch>` on the PR-only entry), never `--reviewer` |
| Check out the PR head | `gh pr checkout <N>`, or `gh pr checkout <N> --detach` when the branch is locked in another worktree. It is fork-safe: a fork's head branch is not fetchable from `origin` by name |
| Merge the base into the head | `gh pr update-branch <N>` (pull-request `ready-for-review.md`) |
| Flip a draft ready | `gh pr ready <N>`, run only inside `/source-control:pull-request ready`, never bare |
| Merge pinned to the reviewed head | `gh pr merge <N> --squash --match-head-commit <sha>`, never `--admin` or `--auto` (pull-request `merge.md` §4.2.1 owns the merge-queue form) |
| Open a tracking issue | `gh issue create` |

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
| Reply on an inline thread | `gh api repos/<owner>/<repo>/pulls/<N>/comments/<id>/replies -f body=…` |
| Reply on the conversation | `gh pr comment <N>` |
| Verify an inline reply | the inline surface filtered with `--jq '.[] \| select(.in_reply_to_id == <original-id>)'` |
| Verify a conversation reply | the conversation surface filtered with `--jq '.[] \| select((.body \| contains("<sha>")) and .user.login == "<posting-identity>") \| .body'`, never `.[-1]` |
| Tell a bot from a person | REST `user.type == "Bot"`; GraphQL `author.__typename == "Bot"` |
| Resolve a review thread | the GraphQL `resolveReviewThread` mutation, then confirm `isResolved == true` over GraphQL |

## Branch rules

| Operation | GitHub command |
|---|---|
| Effective rules on a branch | `gh api repos/<owner>/<repo>/rules/branches/<branch>` |
| Classic protection fallback | `gh api repos/<owner>/<repo>/branches/<branch>/protection` |
| Whether head branches are deleted on merge | the repository's `delete_branch_on_merge` field |

## Sandboxed sessions: GraphQL is restricted

Claude Code on the web and remote execution serve only a pinned set of GraphQL operations and refuse
the rest with `HTTP 403`. `gh pr view --json`, `gh repo view --json`, `gh pr create`, `gh pr ready`
and `gh pr merge` all run over GraphQL. The 403 reads like an expired token or a missing scope and
is neither: switch to the REST route the spoke names rather than re-authenticating. Probe it
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
([changing the stage of a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/changing-the-stage-of-a-pull-request),
read 2026-10-11; recheck when GitHub changes the draft-stage rules).
