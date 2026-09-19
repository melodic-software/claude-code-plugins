---
description: "CI security-review lane for a GitHub pull request. Logic, trust-boundary, and Actions security findings static analysis misses. Use when: 'CI security review', 'claude-security-review lane', '/review:security-review', or a reusable workflow invokes the org security-review plugin command."
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(gh pr diff:*)", "Bash(gh pr view:*)", "Bash(gh pr comment:*)", "Bash(gh pr review:*)", "Read", "Glob", "Grep"]
metadata:
  workflow-stage: review
  summary: Org CI security-review lane command for a GitHub pull request
---

# CI security review (`/review:security-review`)

Org-owned security review logic for the `claude-security-review` reusable
workflow. Built-in `/security-review` is unusable in CI
(origin/HEAD unresolvable under the Actions checkout action; cannot post). The vendor's error
reference carries the mechanism: that command builds its review context by diffing the branch
against `origin/HEAD`, and when the ref does not exist the git commands that gather the diff fail
and the review stops before it starts. The same entry names CI checkouts as a case that fetches
too narrow a refspec for git to create the ref. Verified 2026-09-06 against Claude Code 2.1.263
and <https://code.claude.com/docs/en/errors> as fetched that day; recheck when that entry stops
naming CI checkouts, when the command gains a diff base that does not need `origin/HEAD`, or when
a release note names `/security-review`. This org-authored skill is the CI path. The lane wrapper supplies `REPO` /
`PR NUMBER` / `HEAD SHA` and installs the inline-comment MCP server via
`claude_args`; this skill owns **what to hunt for**.

## Boundary, the native `security-review` command

One native Claude Code surface shares this lane's name, and the two get conflated on any open pull
request:

- **`security-review` (native command).** Ships with Claude Code rather than as a marketplace
  plugin; the installed binary registers it plugin-backed, and the commands table gives it no
  Skill label. A developer runs it in their session for a single security pass over the current
  branch, diffed against `origin`'s default branch; it takes no flags and no target argument. It
  cannot run under the Actions checkout (the opening paragraph carries that record).
- **This skill (marketplace plugin).** The security logic the `claude-security-review` reusable
  workflow runs in CI. The wrapper supplies the target and owns posting; this skill owns what to
  hunt for.

**Routing.** This skill runs in two modes: the CI lane, where the reusable workflow invokes it,
and seat-run mode, where the pull-request skill's ready step or the operator invokes it directly
(the section below). In a session, when the native command resolves, prefer it for an ad-hoc
pass before a pull request exists; the run a repository's mandatory-skill map asks for by name
is this skill, not that command, because the two stamp different names into the skill-usage
ledger a map reads. A deep multi-agent scan or repository monitoring is neither surface: those
are the Claude Security plugin and product.

**Mutation gate.** In the CI lane this skill posts only through its wrapper's mechanics; in
seat-run mode it posts nothing at all. It edits nothing in either mode, so never invoke the
native command on this lane's behalf.

**Availability is never assumed.** Native surfaces are gated by their backing plugin, settings,
environment, and host; this section states what to do when one resolves, never that it is
present. The four-part records live in
[reference/bundled-security-review.md](reference/bundled-security-review.md).

## Seat-run mode

The same criteria run outside CI, on the operator's own session: invoked by the pull-request
skill's ready step, or by hand against an open pull request. No wrapper supplies the inputs
there, so read them:

- `gh pr view <n> --json number,headRefOid` for the number and the head SHA. REST serves both,
  so no checkout with history is needed.
- `gh pr diff <n>` for the diff, or `gh api repos/{owner}/{repo}/pulls/<n>/files --paginate`
  when per-file entries are wanted instead of one patch.

Return the findings in the conversation, in the same severity vocabulary
(CRITICAL / IMPORTANT / SUGGESTION) and against the same high-signal bar. Post nothing to
GitHub: no review, no comment, no label. The inline-comment MCP server is a wrapper grant the
CI lane alone gets, so it is not used here; on the seat the transcript is the report.

## Gotchas

- Skill frontmatter cannot install the inline-comment MCP server. Only the
  action's `claude_args` can. Rely on the wrapper grant.
- Report **security issues only**. No style, naming, test-coverage, or general
  code-quality commentary (that is `/review:code-review`).

## Skip gate (cheap)

Before deep review, stop early when any of these hold (say so plainly and post
nothing else):

1. PR is closed or not open
2. Change has no security-relevant surface after reading the diff
3. This head already has a successful security review that still applies

## Criteria

Perform a security review of THIS pull request. Review ONLY the files changed
in this PR: use `gh pr diff` to see what changed, then read those files. Do not
audit unrelated parts of the codebase.

Hunt for vulnerabilities that static analysis misses: logic flaws, authorization
and access-control gaps, injection surfaces (command, SQL, path, template), and
unsafe handling of tokens / secrets / credentials. Tag each finding with a
severity (CRITICAL / IMPORTANT / SUGGESTION).

GitHub Actions hardening is zizmor's advisory lane: dangerous triggers such as
`pull_request_target` or `workflow_run` running untrusted code with secrets,
expression injection through the `github` context inside `run:` blocks,
permission-widening changes to a workflow's `permissions:` or to settings /
config, and supply-chain risk from loosened or unpinned action / dependency
pins. Defer to it and do not re-report those findings here. This lane's value
is the logic, architecture, data-flow, and trust-boundary security reasoning
static analysis cannot reach, so report an Actions finding only when it needs
that reasoning. If you find no security issues, say so plainly.

## High-signal bar

Exclude pre-existing issues, linter-catchable noise, and generic security advice
without a concrete exploitable path in this diff. Committable suggestion fences
(GitHub `suggestion` code blocks) only when the suggestion alone fully fixes the
anchored finding.

## Adversarial validation

When fanning out hunters, validate each surviving candidate with a separate
verifier subagent (producer ≠ verifier). Drop rejected candidates.

## Reporting

Use the inline-comment tool the wrapper granted to anchor each finding to the
changed line it concerns. Cross-file / whole-PR findings go in the summary with
commit-blob permalinks using the supplied HEAD SHA.
