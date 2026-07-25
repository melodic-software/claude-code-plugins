# PR review mode

Reviews an existing GitHub PR with git-history context.

## Boundary — two built-in/managed surfaces, neither a marketplace plugin

Two Claude Code surfaces overlap this mode's job on an open PR. Neither is an installable
`claude-plugins-official` marketplace plugin — both ship with Claude Code itself:

- **Bundled `/code-review` command** — invoked bare (no plugin namespace), always available,
  no install required. Pass a PR number as its target (`/code-review 123`) to review that PR
  locally; it reports correctness bugs plus reuse/simplification/efficiency cleanups. `--fix`
  applies edits to the working tree and `--comment` posts the findings as inline PR comments —
  both mutate.
- **Managed Code Review GitHub App service** — a separate org-level service (Team/Enterprise,
  enabled once by an Owner in admin settings) that runs multiple review agents in parallel
  against the PR diff, verifies candidates to filter false positives, and posts the results as
  inline PR comments tagged by severity. It triggers automatically on PR open/push per the
  repo's configured behavior, or on demand by commenting `@claude review` on the PR.

**PR-mutation gate:** `/code-review --comment` and triggering the managed service both post to
the PR, which violates the review modes' report-only contract; when the branch has an open PR,
dispatch either only on explicit user opt-in ("post the review comment"), otherwise skip and
name the skip in the review report — fall to the read-only manual path below.

## Manual PR review (default read-only path)

Used by default, or when the opt-in above is withheld:

1. `gh pr diff` for the change set (page it — large PRs flood context)
2. Apply the project's review criteria (or `${CLAUDE_PLUGIN_ROOT}/context/severity.md` baseline) manually, or dispatch this plugin's `code-reviewer` agent against the PR's merge-base diff
3. When the repository runs its own CI review bot (e.g. the managed Code Review service) on PR open/sync, note that its coverage still arrives independently

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
