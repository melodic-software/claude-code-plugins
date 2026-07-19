# PR review mode

Reviews an existing GitHub PR with git-history context.

## `code-review` orchestrator plugin (when installed)

When the `code-review` plugin (from the `claude-plugins-official` marketplace) is available, `/code-review:code-review` detects the current branch's PR and runs parallel review agents with confidence scoring against it.

**PR-mutation gate:** its PR mode posts findings as a PR comment, which violates the review modes' report-only contract; when the branch has an open PR, dispatch it only on explicit user opt-in ("post the review comment"), otherwise skip it and name the skip in the review report — fall to the read-only manual path below.

## Manual PR review (default read-only path)

Used when the plugin is absent, or when the opt-in above is withheld:

1. `gh pr diff` for the change set (page it — large PRs flood context)
2. Apply the project's review criteria (or `${CLAUDE_PLUGIN_ROOT}/context/severity.md` baseline) manually, or dispatch this plugin's `code-reviewer` agent against the PR's merge-base diff
3. When the repository runs its own CI review bot on PR open/sync, note that its coverage still arrives independently

## Prerequisites

- A PR exists for the current branch (`gh pr list --head <branch>`)
- `gh` CLI authenticated; PR diff accessible

## When to use

- A PR exists and deeper analysis is wanted before merge
- Reviewing someone else's PR (ad-hoc review request)
- Drilling into findings a CI review bot produced

## After the review

1. **Triage findings** — confidence filters help, but false positives still occur; verify against the diff
2. **Fix valid findings** — push fixes to the branch
3. **Respond to PR comments** individually rather than in bulk
