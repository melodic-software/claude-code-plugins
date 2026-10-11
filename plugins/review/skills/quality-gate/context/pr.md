# PR review mode

Reviews an existing GitHub PR with git-history context.

## Boundary, three overlapping review surfaces

Three Claude Code review surfaces overlap this mode's job on an open PR: one installable
marketplace plugin, plus two that ship with Claude Code itself. They share a name and are
routinely conflated; they are distinct:

- **`code-review` marketplace plugin**: `/code-review:code-review`, installed from the
  `claude-plugins-official` marketplace like any other plugin. A PR is its only target: it runs
  parallel review agents with confidence scoring against that PR, then posts the surviving findings
  back as a PR comment as its final step. It has no mode that returns them to the session instead.
- **Bundled `/code-review` command**: invoked with no plugin namespace, and never assumed present
  (settings, the host, and the environment decide whether it resolves). Passing a PR as its target
  reviews that PR locally and reports into the session. Some of its arguments edit the working
  tree or post to the PR; those make it a mutating surface.
- **Managed Code Review GitHub App service**: a separate org-level service, enabled once by an
  admin, that reviews PRs and posts its results as inline PR comments, triggered by the repository's
  configured behavior or by a comment on the PR. Its availability (plans, preview status, and the
  organization configurations it excludes) and its check run's conclusion are upstream-owned: never
  tell a person it is available, or that it does or does not block a merge, without reading them
  live.

**Pointer record for the three surfaces above.** Pointer: the managed service's enablement at
[code-review: set up Code Review](https://code.claude.com/docs/en/code-review#set-up-code-review),
and its availability (plans, preview status, excluded configurations) in the note that opens the
same page, above its first section, which carries no anchor of its own; its triggers at
[code-review: manually trigger reviews](https://code.claude.com/docs/en/code-review#manually-trigger-reviews),
its check-run behavior at
[code-review: check run output](https://code.claude.com/docs/en/code-review#check-run-output); the
bundled command's arguments and what each mutates at
[code-review: review a diff locally](https://code.claude.com/docs/en/code-review#review-a-diff-locally);
its status as a bundled skill at
[skills: bundled skills](https://code.claude.com/docs/en/skills#bundled-skills). As of: 2026-10-11.
Recheck trigger: the code-review page changes its availability note, the check-run section, or the
argument list, or the bundled command leaves the bundled-skill list.

**Mutation gate.** The gate is by effect, not by flag name. It covers the plugin unconditionally,
the managed service, and any bundled `/code-review` invocation whose arguments, as read live at the
pointer above, edit the working tree or post to the PR. Every
`/code-review:code-review` run ends by posting its findings as a PR comment, and triggering the
managed service posts a full review; both violate the review modes' report-only contract, as does
any bundled invocation that posts or edits. Dispatch any gated surface only on explicit user opt-in
("post the review comment", "apply the fixes"), otherwise skip and name the skip in the review
report.

A bundled `/code-review <target>` whose arguments only report into the session is **not** gated:
it writes nothing to the PR or the working tree, so it stays available as a read-only option
alongside the manual path below.

## Manual PR review (default read-only path)

Used by default, or alongside a bare `/code-review <target>` pass:

1. `/source-control:pull-request view <n> --diff` for the change set, invoked via the Skill tool when the `source-control` plugin is installed; otherwise the forge's own diff read (page it, since large PRs flood context)
2. Apply the project's review criteria (or `<plugin-root>/context/severity.md` baseline) manually, or dispatch this plugin's `code-reviewer` agent against the PR's merge-base diff
3. When the repository runs its own CI review bot (e.g. the managed Code Review service) on PR open/sync, note that its coverage still arrives independently
4. Lead the report with the findings you would block the merge for. Each gives the file and line, why it is wrong, and how to show it fails (the concrete input or command the CRITICAL test names). Lower tiers follow

## Prerequisites

- A PR exists for the current branch (`/source-control:pull-request view` with no number returns it)
- The forge is reachable from this session and the PR diff is readable

## When to use

- A PR exists and deeper analysis is wanted before merge
- Reviewing someone else's PR (ad-hoc review request)
- Drilling into findings a CI review bot produced

## After the review

1. **Triage findings**: confidence filters help, but false positives still occur; verify against the diff
2. **Fix valid findings**: push fixes to the branch, scoped by the review-fix rule in SKILL.md Step 4
3. **Respond to PR comments** individually rather than in bulk
