---
description: "CI security-review lane for a GitHub pull request. Logic, trust-boundary, and Actions security findings static analysis misses. Use when: 'CI security review', 'claude-security-review lane', '/review:security-review', or a reusable workflow invokes the org security-review plugin command."
argument-hint: ""
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(gh pr diff:*)", "Bash(gh pr view:*)", "Bash(gh pr comment:*)", "Bash(gh pr review:*)", "Read", "Glob", "Grep"]
metadata:
  workflow-stage: review
  summary: Org CI security-review command for claude-security-review.yml
---

# CI security review (`/review:security-review`)

Org-owned security review logic for the `claude-security-review` reusable
workflow (ci-workflows#258). Built-in `/security-review` is unusable in CI
(origin/HEAD unresolvable under the Actions checkout action; cannot post). This org-authored skill is the CI path. The lane wrapper supplies `REPO` /
`PR NUMBER` / `HEAD SHA` and installs the inline-comment MCP server via
`claude_args`; this skill owns **what to hunt for**.

## Gotchas

- Skill frontmatter cannot install the inline-comment MCP server. Only the
  action's `claude_args` can. Rely on the wrapper grant.
- Do not use a stale 0–100 confidence-score tuning line. Prefer adversarial
  validation (producer ≠ verifier) for candidate findings.
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
and access-control gaps, injection surfaces (command, SQL, path, template),
unsafe handling of tokens / secrets / credentials, and dangerous GitHub Actions
patterns. `pull_request_target` or `workflow_run` used with secrets over
untrusted code, script injection through the `github` context inside `run:`
blocks, permission-widening changes to a workflow's `permissions:` or to
settings / config, and supply-chain risk from loosened or unpinned action /
dependency pins.

Tag each finding with a severity (CRITICAL / IMPORTANT / SUGGESTION). Defer to
zizmor's advisory lane for what it already covers statically. Supply-chain /
unpinned-action risk, dangerous trigger patterns, excessive permissions, and
template injection: do not re-report those findings here. This lane's value is
the logic, architecture, data-flow, and trust-boundary security reasoning static
analysis cannot reach. If you find no security issues, say so plainly.

## High-signal bar

Exclude pre-existing issues, linter-catchable noise, and generic security advice
without a concrete exploitable path in this diff. Committable suggestion fences
(GitHub `suggestion` code blocks) only when the suggestion alone fully fixes the
anchored finding.

## Adversarial validation (V2 target)

When fanning out hunters, validate each surviving candidate with a separate
verifier subagent (producer ≠ verifier). Drop rejected candidates.

## Reporting

Use the inline-comment tool the wrapper granted to anchor each finding to the
changed line it concerns. Cross-file / whole-PR findings go in the summary with
commit-blob permalinks using the supplied HEAD SHA.
