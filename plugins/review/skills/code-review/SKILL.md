---
description: "CI code-review lane for a GitHub pull request — high-signal correctness and maintainability findings only, scoped out of security when a security lane exists. Use when: 'CI code review', 'claude-review lane', '/review:code-review', or a reusable workflow invokes the org code-review plugin command."
argument-hint: ""
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(gh pr diff:*)", "Bash(gh pr view:*)", "Bash(gh pr comment:*)", "Bash(gh pr review:*)", "Read", "Glob", "Grep"]
metadata:
  workflow-stage: review
  summary: Org CI code-review command for claude-review.yml
---

# CI code review (`/review:code-review`)

Org-owned review logic for the `claude-review` reusable workflow
(ci-workflows#258). The lane's workflow wrapper supplies `REPO` / `PR NUMBER` /
`HEAD SHA` and the event-class reporting mechanics (inline-comment MCP on
`pull_request`, `gh pr review`/`gh pr comment` on `workflow_dispatch`). This
skill owns **what to look for**; the wrapper owns **how to post**.

## Gotchas

- Command/skill frontmatter `allowed-tools` grants permission but does **not**
  install the inline-comment MCP server. That server only installs when named
  in the action's `claude_args` (`--allowedTools
  mcp__github_inline_comment__create_inline_comment`). Rely on the lane
  wrapper's grant; do not assume this frontmatter installed it.
- Do not invent a 0–100 confidence-score gate. Prefer adversarial validation
  (producer ≠ verifier) when spawning subagents.
- Scope security findings **out** of this lane wherever the consumer carries a
  `claude-security-review` workflow file — leave those to `/review:security-review`.

## Skip gate (cheap)

Before deep review, stop early when any of these hold (say so in the summary and
post nothing else):

1. PR is closed or not open
2. PR is a draft
3. Change is trivial/automated with no meaningful review surface
4. This head already has a successful review from this lane that still applies

## Criteria

This is the CODE-REVIEW lane. Review the pull request for correctness and
alignment with the project's `CLAUDE.md` guidelines (and `REVIEW.md` criteria
when present). Focus on architecture decisions, error handling, test coverage,
and maintainability. Where `REVIEW.md` splits review scope across lanes — it
scopes security review to the dedicated security lane wherever a
`claude-security-review` workflow exists — follow that split.

Scope the review to files changed in this PR. Use `gh pr diff` to identify what
changed, then review those files. Do not explore unrelated parts of the
codebase.

Never restate the PR author's own claimed verification (e.g. a Test plan's
described commands or output) as evidence you independently confirmed. Only
claim to have verified something you yourself ran with a tool available to you;
label anything else as author-claimed and unverified.

## High-signal bar

Report only findings a careful senior reviewer would block or flag. Exclude:

- Anything a linter, formatter, typechecker, or trivial static check catches
- Pre-existing issues on untouched lines
- Generic advice, style nits, and "consider adding tests" without a concrete gap
- Security findings that belong on the security lane (see skip above)

## Adversarial validation (V2 target)

When you fan out subagents for candidate findings, the producer of a finding
must not be the verifier. Drop candidates the verifier rejects. Committable
suggestion fences (GitHub `suggestion` code blocks) are allowed only when the
suggestion alone fully fixes the finding on the anchored lines.

## Reporting

Follow the reporting mechanics the workflow wrapper appended to the prompt
(inline MCP tool vs `gh`). Keep the summary comment for overview and
cross-file / whole-PR findings; use commit-blob permalinks with the supplied
HEAD SHA for locations no changed line can carry.
