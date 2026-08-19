---
description: "Single-lens review checkpoint between 'code works' and 'code is ready' — routes to self, code, architecture, security, spec, pr, criteria, slice, or restatement mode and delegates to the matching reviewer. Use when the user says 'review this', 'self-review', 'quality gate', 'code review', 'architecture review', 'security review', or 'does this match the spec/issue/plan', or after implementation completes."
argument-hint: "[mode] (e.g., /review:quality-gate, /review:quality-gate self, /review:quality-gate security, /review:quality-gate spec [--spec <path|id>], /review:quality-gate slice <name>)"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(git branch --show-current 2>/dev/null || echo \"unknown\")", "Bash(git status --porcelain 2>/dev/null | head -20 || echo \"unavailable\")", "Bash(gh pr list --json number,title,headRefName,baseRefName --limit 10 2>/dev/null || echo \"unknown\")", "Bash(gh pr list:*)", "Bash(git rev-parse:*)", "Bash(git merge-base:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git ls-files --others --exclude-standard)", "Bash(git ls-remote --symref:*)"]
shell: bash
metadata:
  workflow-stage: review
  summary: Single-lens review checkpoint routed to the matching reviewer
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "unavailable"`
Open PRs (match headRefName to current branch above; baseRefName is the PR's real base): !`gh pr list --json number,title,headRefName,baseRefName --limit 10 2>/dev/null || echo "unknown"`

## Purpose

Review is the quality checkpoint between "code works" and "code is ready." This skill structures that step so changes are inspected for consistency, correctness, and alignment with the project's conventions before verification or PR creation. Self-review catches errors tests miss — inconsistencies, loose ends, convention drift, design shortcuts. Delegated reviews (code, architecture, security) bring specialized scrutiny the implementer's tunnel vision would miss.

**Depth, not breadth.** This skill picks ONE lens per invocation. For a multi-surface fan-out that runs many reviewers at once and ranks their combined findings, use this plugin's `fanout` skill instead.

## Shared inputs

- **Review diff base** — when an open PR exists for the branch, its `baseRefName` is the base: dispatched reviewers diff `git merge-base origin/<baseRefName> HEAD`. The pre-computed PR list above is capped; when the current branch is absent from it, run `gh pr list --head <current-branch> --json number,baseRefName` before concluding no PR exists. Otherwise `git merge-base origin/HEAD HEAD` (falling back to the remote's resolved default branch via `git ls-remote --symref`, then `origin/main`, then `HEAD`) so committed-clean branches still show their changes; untracked files come from `git ls-files --others --exclude-standard`.
- **Severity vocabulary** — the project's own review docs when present; else `${CLAUDE_PLUGIN_ROOT}/context/severity.md`.
- **Criteria resolution** — review criteria resolve through the standards index per the plugin binding [`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md) (its "Resolution ladder" section owns the procedure), detailed in [context/criteria.md](context/criteria.md).
- **Findings location** — resolve through the plugin binding, [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md), which owns the resolution ladder, its non-interactive collapse, the `<branch-slug>` and `<UTC-timestamp>` spec, and the self-ignore guard. **Resolve the home; never assume its shape** — the ladder's rungs do not all compose a `reviews/<branch-slug>` segment. Durable findings are `<UTC-timestamp>-<mode>.md` in the resolved directory. Write repo-relative paths only — never absolute machine paths.

## Step 0: Detect review mode

`$ARGUMENTS` — optional mode selector. When given, use it directly; otherwise infer:

| Signal | Mode | Context file |
|--------|------|-------------|
| Just finished implementing, "review my work", bare invocation with uncommitted changes | **self** | [context/self.md](context/self.md) |
| "review the code", "code review" | **code** | [context/code.md](context/code.md) |
| "architecture review", new modules, cross-cutting structure | **architecture** | [context/architecture.md](context/architecture.md) |
| "security review", auth/input handling, API endpoints | **security** | [context/security.md](context/security.md) |
| "does this match the spec/issue/plan", "did we build what was asked", scope-creep check, `spec [--spec <path\|id>]` | **spec** | [context/spec.md](context/spec.md) |
| "review the PR", a PR exists for the branch | **pr** | [context/pr.md](context/pr.md) |
| "review criteria", "what should I check" | **criteria** | [context/criteria.md](context/criteria.md) |
| `slice <name>`, "review testing", "review concurrency" | **slice** | [context/per-slice.md](context/per-slice.md) |
| "restatement review", "SSOT drift", markdown-heavy diff | **restatement** | [context/restatement.md](context/restatement.md) |

Ambiguous → present the modes and ask. **Read the matching context file before proceeding.**

## Step 0.5: Pre-flight gate (diff-consuming modes only)

**Mode-scoped by design.** `criteria` is a reference mode — it loads criteria rather than reviewing
a change, and legitimately runs against a clean tree — so it is **exempt** and never gated. Every
other mode consumes the review diff, so for those: resolve the review diff base ("Shared inputs")
and confirm it yields a non-empty diff BEFORE dispatching any reviewer.

- **Unresolvable base** — an open PR's `origin/<baseRefName>` fails `git rev-parse --verify` even
  after a fetch (do NOT silently substitute a different base — that reviews the wrong diff), or no
  ladder ref resolves at all → report which ref failed and STOP.
- **Nothing to review** — a truly clean tree, or untracked-only changes → say which, and STOP;
  never stage files to manufacture a diff.

Either outcome dispatches ZERO reviewers: a lens run against an empty or wrong change set produces
noise, not a verdict. `spec` mode adds one gate of its own on top of this one — an explicitly
passed `--spec` ref that does not resolve is also a STOP ([context/spec.md](context/spec.md)
"Rung 1").

## Step 1: Gather context

1. **What changed?** — pre-computed facts above + the review diff base
2. **What was the goal?** — the original task, approved plan, or user intent from conversation. In every mode but `spec` this is background for judging the change; making the goal the thing under judgment is `spec` mode, which owns the spec-source discovery ladder and the fidelity finding classes
3. **What conventions apply?** — resolve the project's standards for the changed surfaces through the standards index per the Shared-inputs criteria-resolution binding, so every review mode grounds in the same rows plan formulation loaded

## Step 2: Execute the review

Follow the selected context file. Two hard rules:

- **Self mode never runs the checklist on the producing thread.** Dispatch a fresh-context read-only subagent; the thread that wrote the code rubber-stamps its own recap.
- **Delegated modes synthesize, never substitute.** After the delegated reviewer returns, verify each finding against the actual diff (a subagent's report is synthesis, not evidence) before presenting.

## Step 3: Report findings

```markdown
## Review: [mode] — [branch or task name]

### Findings

| # | Severity | Confidence | Category | Finding | File:Line | Action |
|---|----------|------------|----------|---------|-----------|--------|

### Strengths

- What is done well — review should validate, not only criticize

### Verdict

- [ ] Ready to proceed — no blocking findings
- [ ] Needs fixes — N findings require attention
```

## Step 4: Handoff

- **All clear** — suggest the project's next verification step (build/test, outcome verification, PR creation)
- **Fixes needed** — list specific actions; after fixes, suggest a quick re-run of `self` mode
- **Design fundamentally flawed** — suggest revisiting the plan/design before more code lands

## What this skill does NOT do

- **Does not run builds or tests** — use the project's build/test tooling (or this plugin's `ecosystem-specialist` agent) separately
- **Does not write or fix code** — it identifies issues; the implementer fixes them
- **Does not fan out across many surfaces** — that is this plugin's `fanout` skill

## Gotchas

- **Don't skip self-review for "small" changes** — small changes have the highest ratio of "obviously fine" to "actually had a bug."
- **`criteria` mode is a reference, not an action** — it loads review criteria so you can see what to check; combine with `self` mode for an informed review.
