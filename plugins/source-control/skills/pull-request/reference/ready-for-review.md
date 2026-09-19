# Phase 2.5: Ready for review

The draft-to-ready flip is the run that produces a pull request's evidence: it refreshes the base,
runs every mandatory skill that has no fresh row for the head, renders that evidence into the body,
and only then marks the PR ready. Entry action: `/source-control:pull-request ready`.

This is not [readiness.md](readiness.md), which holds the gates that decide whether a PR may
**merge**. This file covers the flip alone.

**The order the skill runs follow is the fleet's pre-PR order**, owned by
[`docs/conventions/pre-pr-ordering/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/pre-pr-ordering/README.md).
Read the order there. This phase cites it and never states a different one.

## 2.5.1 Refuse without a pull request

```bash
BRANCH=$(git branch --show-current)
PR_NUMBER=$(gh pr view "$BRANCH" --json number -q '.number' 2>/dev/null)
```

Empty: stop and report. There is nothing to flip, nothing to render into, and no head a reviewer
can reach. Route to `/source-control:pull-request create`, which opens the draft this phase flips,
rather than opening one here.

Already out of draft (`gh pr view "$PR_NUMBER" --json isDraft -q '.isDraft'` prints `false`): the
flip is done but the evidence may still be stale, so run 2.5.2 through 2.5.5 and skip 2.5.6.

## 2.5.2 Refresh the base with a merge

```bash
BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q '.baseRefName')
REMOTE=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/resolve-remote.sh") || exit 1

gh pr update-branch "$PR_NUMBER"                     # merges the base into the head branch
git fetch "$REMOTE" "$BRANCH" && git merge --ff-only FETCH_HEAD
```

Push any local commits first: `git merge --ff-only FETCH_HEAD` refuses when the local branch
carries commits the remote lacks, and the local-merge fallback below handles that case too.

Where `gh pr update-branch` is unavailable or refuses (a fork head, a session that cannot reach the
endpoint), do the same thing locally:

```bash
git fetch "$REMOTE" "$BASE" && git merge "$REMOTE/$BASE"
```

Refresh the base with a merge, never a rebase: a rebase rewrites the branch's commit SHAs, and
every evidence row is keyed to the SHA it was stamped at. Conflicts route to
`/source-control:resolve-conflicts`, the sibling skill in this plugin.

What the merge costs: it moves HEAD, so the terminal skill's row is stale by construction and runs
again in 2.5.4, while every other row stays fresh because its commit is still on the new HEAD's
history. That is the price of refreshing, and it is why this step comes before the check rather
than after it.

Completion criterion: `git rev-parse HEAD` equals
`gh pr view "$PR_NUMBER" --json headRefOid -q '.headRefOid'`. After `gh pr update-branch` the merge
commit exists on the remote only, so the fetch above is what makes the two agree.

## 2.5.3 Read what the head owes

```bash
HEAD_SHA=$(git rev-parse HEAD)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skill-evidence.sh" check \
  --head "$HEAD_SHA" --ledger "$LEDGER" --base "$REMOTE/$BASE"
```

`$LEDGER` is the store the `skill_evidence_store` plugin option names: `repo` (the default) is
`.claude/observability/skill-usage.jsonl` under the checkout this skill runs in, `user` is the same
subpath under `$HOME`, and any other value is a path to a JSONL file. A store that is not there
reads as no rows, never as a pass, so every skill the map names comes back `missing=` and runs.

The output lines:

| Line | Meaning |
|---|---|
| `class=<name>` | a class of the repository's `pr_skill_evidence` map that this diff touches |
| `fresh=<skill> sha=<sha> commits-since=<n>` | evidence stands; `<n>` says how far back it sits |
| `stale=<skill> sha=<sha>` | a row exists but not where this skill's tier needs it |
| `missing=<skill>` | no row at all; a printed `a,b` is an any-of group, satisfied by either |
| `verdict=clean\|gap\|inert` | the last line, always |

`verdict=inert` means the repository declares no map (or `none`) and nothing is owed: skip to
2.5.6. `verdict=clean` still goes through 2.5.5, because the body may carry an older block.
`verdict=gap` continues below.

## 2.5.4 Run what is missing or stale

Run each skill the check named, in the pre-PR order cited at the top of this file, under two rules:

- **The terminal skill runs last.** The map marks it with a trailing `!` (`verification:confirm!`
  in a repository following that order). Its row has to land on the commit that ships, so nothing
  that changes the tree may run after it.
- **Commit what a mutating skill changes before the next skill runs.** A row is stamped when a
  skill is invoked, not when its edits land, so the terminal row is the only one held at HEAD
  exactly, and it can only be true if the edits before it are already committed.

Which skill each class owes, how to invoke it when its plugin is installed, and what to do instead
when it is not, is the class routing table in [prep.md](prep.md) §1.1. One class behaves
differently here: **`security`** runs in this phase rather than in prep, because it reviews the
pull request's own diff (`gh pr diff "$PR_NUMBER"`), which needs a PR to exist. Run
`/review:security-review` over that diff when the `review` plugin is installed. Without it, run
a security-reviewer agent when your environment ships one, and otherwise review the diff inline
for the security scope the repository's `REVIEW.md` names (trust boundaries, injection, credential
exposure, authorization gaps, Actions and hook permissions); that inline pass covers the class but
writes no row, so report it as the fallback paragraph below says.

**A fallback is not a row.** The ledger records a Skill tool call, so an inline fallback (the
plugin is absent) leaves that row missing and the rendered block short. Report the gap and what
covered it instead of writing a row by hand.

Completion criterion: re-run 2.5.3 against the new `git rev-parse HEAD`. Every skill the map names
reads `fresh=`, or the remaining `missing=` lines are exactly the ones a fallback covered and the
report names each one.

## 2.5.5 Render the block into the body

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/skill-evidence.sh" render \
  --ledger "$LEDGER" --head "$(git rev-parse HEAD)" > block.md
```

`render` prints one fenced block whose info string is `skill-evidence`, carrying a
`<skill> <sha> <utc-timestamp>` row per skill, latest row per skill, sorted by skill name. No
qualifying row means no output, and the body keeps the Verification prose it already had.

The block goes under the body's `## Verification` heading, or under whichever heading the resolved
`pr_body_required_sections` gives that role when a repository names it differently.

1. **Read the current body first**: `gh pr view "$PR_NUMBER" --json body -q '.body' > body.md`.
   Every write below replaces the whole body, so anything not read back is lost.
2. **Replace an earlier block in place**, never append a second one. A reader takes the first
   `skill-evidence` block in a body and reports a second as a warning, so two blocks means the
   newer evidence is the one ignored.
3. **Write it back**: `gh pr edit "$PR_NUMBER" --body-file body.md` locally, the GitHub MCP
   `update_pull_request` call in a cloud session, or
   `gh api --method PATCH "repos/{owner}/{repo}/pulls/$PR_NUMBER" -F body=@body.md` where
   `gh pr edit` is not available (`-F` with a leading `@` reads the file; `-f` would send the
   literal path as the body).

Completion criterion: `gh pr view "$PR_NUMBER" --json body -q '.body'` carries exactly one
`skill-evidence` block and its rows match what `render` just printed.

## 2.5.6 Flip to ready

```bash
gh pr ready "$PR_NUMBER"
```

In a cloud session `gh pr ready` fails, because the flip is a GraphQL mutation. Two routes work
there. The proxy's REST route:

```bash
gh api --method POST "repos/{owner}/{repo}/pulls/$PR_NUMBER/ccr/ready_for_review"
```

Or the GitHub MCP `update_pull_request` call with `draft: false`. The body patch of 2.5.5 edits
the body alone and cannot perform the flip.

Completion criterion: `gh pr view "$PR_NUMBER" --json isDraft -q '.isDraft'` prints `false`.

## 2.5.7 Report

Report, in this order: the classes the diff touched, which skills ran here and which were already
fresh, any skill an inline fallback covered and what that fallback did, the block's terminal row
with the head it carries, and the flip. Then hand monitoring off to
`/source-control:pull-request monitor`.
