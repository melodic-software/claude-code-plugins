# GitHub: pull-request create

The GitHub commands behind the pull-request skill's
[create phase](../../../../skills/pull-request/reference/create.md). The phase owns every step,
gate and prompt; this file holds the commands and the GitHub and `gh` facts behind them.

## Default branch over REST

`gh repo view --json` sends the same `RepositoryInfo` GraphQL query `gh pr create` does, so in a
sandboxed session it fails with `HTTP 403`. Substitute:

```bash
DEFAULT_BRANCH=$(gh api "repos/{owner}/{repo}" --jq '.default_branch')
```

## Read the open state at the base branch

The repository level of `pr_open_state` comes from the PR's base branch in the base repository,
never from the working tree or the branch being opened. A 404 means the level is unset.

```bash
gh api "repos/<base-owner>/<repo>/contents/docs/conventions/source-control.yaml?ref=<base-branch>" \
  -H "Accept: application/vnd.github.raw"
```

## Closes line without a tracker

```bash
CLOSES_LINE=""
REFS_LINES=""  # newline-separated `Refs #Y — <why>` bullets for the ## Related section, populated
                # by the multi-issue or orphan-PR prompts below; never a closing keyword and
                # not a linkage line — see §2.4.1 for routing.
if [[ "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then   # the GitHub default needs an issue number
  # Validate issue exists in current repo BEFORE shipping `Closes #N`.
  # GitHub auto-close only fires when the issue exists, lives in this repo,
  # and is open at merge time. A typo'd branch like
  # `feat/99999-foo` would otherwise ship a misleading `Closes #99999` line.
  ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null || true)
  if [[ "$ISSUE_STATE" == "OPEN" ]]; then
    CLOSES_LINE="Closes #${ISSUE_NUM}"
  else
    echo "⚠ Branch suggests Closes #${ISSUE_NUM}, but that issue is missing or not open in this repo. Falling back to interactive prompt." >&2
    ISSUE_NUM=""   # fall through to orphan-PR 2-option prompt below
  fi
fi
# If still empty, the orphan-PR prompt populates CLOSES_LINE below.
```

## Issue state over REST

`gh issue view --json` routes through GitHub's GraphQL API, and a cloud session behind the GitHub
proxy is served no GraphQL operation at all, so the call fails with `HTTP 403` whatever token is
set. Pointer:
[Configure cloud environments § GitHub proxy](https://code.claude.com/docs/en/cloud-environments#github-proxy),
which names the refusal and the REST fallback. As-of: 2026-10-11. Recheck trigger: that section
changes its GraphQL entry, or a release note names the GitHub proxy. The `2>/dev/null || true` in the block above swallows that 403. Substitute the REST
issues endpoint, which reports `state` in lower case:

```bash
ISSUE_STATE=$(gh api "repos/{owner}/{repo}/issues/${ISSUE_NUM}" --jq '.state' 2>/dev/null || true)
if [[ "$ISSUE_STATE" == "open" ]]; then   # REST returns `open`/`closed`, not `OPEN`/`CLOSED`
```

## Placeholder anchoring

`gh api` has no `--repo` flag. `{owner}` and `{repo}` expand from the repository of the **current
directory**, or from `GH_REPO`. Out of tree, run the call from the worktree
(`( cd "$WT" && gh api … )`) or prefix `GH_REPO=<owner>/<repo>`.

## Body overrides the template

A body passed with `gh pr create --body-file` (or `--body`) fully overrides
`.github/PULL_REQUEST_TEMPLATE.md` (cli/cli #10751). `gh pr create` has no option that uploads a
file.

## Open the draft PR

```bash
# Identity: plain `gh` (the human PR author) by default.
# No reviewers are auto-requested by default — `gh pr create` runs without
# `--reviewer`.
# DRAFT_FLAG comes from the phase's resolved pr_open_state: (--draft) by
# default, empty only when the state is `ready` and a person drives the run.
PR_URL=$(gh pr create "${DRAFT_FLAG[@]}" --head "$BRANCH" --title "<type>: <description>" --body-file "$BODY_FILE")

# Extract PR number from URL (gh pr create outputs the URL on success).
# This number is the source of truth for the rest of this phase — pass it
# explicitly to every subsequent gh call.
PR_NUMBER=$(basename "$PR_URL")
```

## Open the PR over REST

`gh pr create` sends a `RepositoryInfo` GraphQL query as its repo-info preamble, before it touches
the pull-request API at all, so under the GraphQL restriction it returns `HTTP 403` having
created nothing. `POST /repos/{owner}/{repo}/pulls` is REST and works. It requires `head` and
`base`, and `title` unless an existing `issue` is being converted; `body`, `draft`, and
`maintainer_can_modify` are optional. Five differences from `gh pr create` matter:

- **`base` is required.** `gh pr create` defaults it to the repository's default branch; REST does not. Resolve it over REST as well, since §2.2's `gh repo view --json defaultBranchRef` reads the same GraphQL surface and 403s alongside the rest.
- **`head` is bare `<branch>` only for a same-repo PR.** From a fork (the triangular flow §2.7's remote resolver allows), it must be namespaced `<fork-owner>:<branch>`, and when both repositories belong to the same organization, REST additionally requires `head_repo=<fork-repo-name>`.
- **Send the body from its file with `-F body=@"$BODY_FILE"`.** `-F`/`--field` reads a value that starts with `@` from the named file. `-f`/`--raw-field` would send the path itself as the body.
- **The response carries the PR identity.** Read `.number` and `.html_url` from it rather than parsing the number back out of the URL.
- **`draft` is a boolean, so it goes with `-F`.** `-f draft=true` sends the string `"true"`, which the API rejects; `-F` is the flag that type-converts it. The other literal fields (`title`, `head`, `base`) stay on `-f`, so a title that reads `true` or a number is still sent as a string.

```bash
BASE=$(gh api "repos/{owner}/{repo}" --jq '.default_branch')
PR_JSON=$(gh api --method POST "repos/{owner}/{repo}/pulls" \
  -f title="<type>: <description>" \
  -f head="$BRANCH" \
  -f base="$BASE" \
  -F body=@"$BODY_FILE" \
  -F draft="$DRAFT_JSON")
PR_URL=$(printf '%s' "$PR_JSON" | jq -r '.html_url')
PR_NUMBER=$(printf '%s' "$PR_JSON" | jq -r '.number')
```

`--method POST` and `-X POST` are the same flag. Section numbers (§2.2, §2.7) are the create
phase's.

The REST form has no hook backstop: `pr-body-linkage-gate.sh` matches `gh pr create` /
`gh pr edit` and names `gh api …/pulls` among the invocations it deliberately does not see.

## PR identity

```bash
gh pr view --json number,url
```

In a sandboxed session, take identity from the create response, or re-read it with
`gh api "repos/{owner}/{repo}/pulls/<n>" --jq '{number, html_url}'`.

## Open the PR from an out-of-tree orchestrator

`gh pr create` MUST pass `--head "$BRANCH"` explicitly, since the invoker is not on the branch:

```bash
PR_URL=$(gh pr create "${DRAFT_FLAG[@]}" --head "$BRANCH" --title "<type>: <description>" --body-file "$BODY_FILE")
```

In a sandboxed session that 403s, the REST form, run from the worktree:

```bash
PR_JSON=$( cd "$WT" && gh api --method POST "repos/{owner}/{repo}/pulls" \
  -f title="<type>: <description>" -f head="$BRANCH" -f base="$BASE" -F body=@"$BODY_FILE" -F draft="$DRAFT_JSON" )
```

Resolve the base branch the same anchored way:
`BASE=$( cd "$WT" && gh api "repos/{owner}/{repo}" --jq '.default_branch' )`.

On a triangular flow, name the base repository explicitly and namespace `head`:

```bash
BASE_REPO="<base-owner>/<repo>"                # the PR's target, not the push destination
PR_JSON=$(GH_REPO="$BASE_REPO" gh api --method POST "repos/{owner}/{repo}/pulls" \
  -f title="<type>: <description>" -f head="<fork-owner>:$BRANCH" \
  -f base="$BASE" -F body=@"$BODY_FILE" -F draft="$DRAFT_JSON")
```

`GH_REPO` overrides the cwd-derived placeholders outright, so this form needs no `cd` at all. On a
triangular flow resolve `$BASE` through `GH_REPO` too, as
`BASE=$(GH_REPO="$BASE_REPO" gh api "repos/{owner}/{repo}" --jq '.default_branch')`, not through the
`cd "$WT"` form above, which would read the fork's default branch.
