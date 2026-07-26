# PR review mode

Reviews an existing GitHub PR with git-history context.

## Boundary — three overlapping review surfaces

Three Claude Code review surfaces overlap this mode's job on an open PR — one installable
marketplace plugin, plus two that ship with Claude Code itself. They share a name and are
routinely conflated; they are distinct:

- **`code-review` marketplace plugin** — `/code-review:code-review`, installed from the
  `claude-plugins-official` marketplace like any other plugin. A PR is its only target: it runs
  parallel review agents with confidence scoring against that PR, then posts the surviving findings
  back as a PR comment as its final step. It has no mode that returns them to the session instead.
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

**Mutation gate — the plugin unconditionally, the bundled command's flags, and the managed service;
not the bare command:** every `/code-review:code-review` run ends by posting its findings as a PR
comment, `/code-review --comment` posts inline comments to the PR, and triggering the managed
service posts a full review; all three violate the review modes' report-only contract. `--fix`
mutates the working tree. Dispatch any of those four only on explicit user opt-in ("post the review
comment", "apply the fixes"), otherwise skip and name the skip in the review report.

Bare `/code-review <target>` is **not** gated: it reports into the session and writes nothing to
the PR or the working tree, so it stays available as a read-only option alongside the manual path
below.

## Manual PR review (default read-only path)

Used by default, or alongside a bare `/code-review <target>` pass:

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
