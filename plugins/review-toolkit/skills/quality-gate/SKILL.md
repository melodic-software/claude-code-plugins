---
name: quality-gate
description: "Single-lens review checkpoint between 'code works' and 'code is ready' — routes to self, code, architecture, security, pr, criteria, slice, or restatement mode and delegates to the matching reviewer. Use when the user says 'review this', 'self-review', 'quality gate', 'code review', 'architecture review', or 'security review', or after implementation completes."
argument-hint: "[mode] (e.g., /review-toolkit:quality-gate, /review-toolkit:quality-gate self, /review-toolkit:quality-gate security, /review-toolkit:quality-gate slice <name>)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "unavailable"`
Open PRs (match headRefName to current branch above; baseRefName is the PR's real base): !`gh pr list --json number,title,headRefName,baseRefName --limit 10 2>/dev/null || echo "unknown"`

## Purpose

Review is the quality checkpoint between "code works" and "code is ready." This skill structures that step so changes are inspected for consistency, correctness, and alignment with the project's conventions before verification or PR creation. Self-review catches errors tests miss — inconsistencies, loose ends, convention drift, design shortcuts. Delegated reviews (code, architecture, security) bring specialized scrutiny the implementer's tunnel vision would miss.

**Depth, not breadth.** This skill picks ONE lens per invocation. For a multi-surface fan-out that runs many reviewers at once and ranks their combined findings, use this plugin's `code-review-fanout` skill instead.

## Shared inputs

- **Review diff base** — when an open PR exists for the branch, its `baseRefName` is the base: dispatched reviewers diff `git merge-base origin/<baseRefName> HEAD`. The pre-computed PR list above is capped; when the current branch is absent from it, run `gh pr list --head <current-branch> --json number,baseRefName` before concluding no PR exists. Otherwise `git merge-base origin/HEAD HEAD` (falling back to `origin/main`, then `HEAD`) so committed-clean branches still show their changes; untracked files come from `git ls-files --others --exclude-standard`.
- **Severity vocabulary** — the project's own review docs when present; else `${CLAUDE_PLUGIN_ROOT}/context/severity.md`.
- **Findings location** — resolve through the plugin binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)): the `.claude/topic-docs.yaml` concern file's `memory_dir` first (`<memory_dir>/reviews/<branch-slug>/`); else a review-artifacts location declared in the project's `CLAUDE.md` / rules (use it, and offer to persist it into the concern file — prose is an inference source, not the runtime authority); else the default `.work/reviews/<branch-slug>/`. Durable findings are `<UTC-timestamp>-<mode>.md` in that directory, where `<branch-slug>` is the branch name lowercased with `/` and other non-`[a-z0-9._-]` characters replaced by `-`, and `<UTC-timestamp>` is `date -u +%Y%m%dT%H%M%SZ` (ISO-basic UTC, colon-free, Windows-safe). Self-ignore guard: the session's first memory-tier write verifies the resolved memory root contains a `.gitignore` with `*`, creating it (announced) when absent. Legacy grace (the contract's grace algorithm, slice axis = branch, legacy root `.claude/review/`): when the new home holds no reports for this branch and `.claude/review/<branch-slug>/` does, writes stay pinned there with a deprecation note; reads check the new home first, then fall back to legacy — detail in the binding doc. Write repo-relative paths only — never absolute machine paths.

## Step 0: Detect review mode

`$ARGUMENTS` — optional mode selector. When given, use it directly; otherwise infer:

| Signal | Mode | Context file |
|--------|------|-------------|
| Just finished implementing, "review my work", bare invocation with uncommitted changes | **self** | [context/self.md](context/self.md) |
| "review the code", "code review" | **code** | [context/code.md](context/code.md) |
| "architecture review", new modules, cross-cutting structure | **architecture** | [context/architecture.md](context/architecture.md) |
| "security review", auth/input handling, API endpoints | **security** | [context/security.md](context/security.md) |
| "review the PR", a PR exists for the branch | **pr** | [context/pr.md](context/pr.md) |
| "review criteria", "what should I check" | **criteria** | [context/criteria.md](context/criteria.md) |
| `slice <name>`, "review testing", "review concurrency" | **slice** | [context/per-slice.md](context/per-slice.md) |
| "restatement review", "SSOT drift", markdown-heavy diff | **restatement** | [context/restatement.md](context/restatement.md) |

Ambiguous → present the modes and ask. **Read the matching context file before proceeding.**

## Step 1: Gather context

1. **What changed?** — pre-computed facts above + the review diff base
2. **What was the goal?** — the original task, approved plan, or user intent from conversation
3. **What conventions apply?** — the project's own rules for the changed file types

## Step 2: Execute the review

Follow the selected context file. Two hard rules:

- **Self mode never runs the checklist on the producing thread.** Dispatch a fresh-context read-only subagent; the thread that wrote the code rubber-stamps its own recap.
- **Delegated modes synthesize, never substitute.** After the delegated reviewer returns, verify each finding against the actual diff (a subagent's report is synthesis, not evidence) before presenting.

## Step 3: Report findings

```markdown
## Review: [mode] — [branch or task name]

### Findings

| # | Severity | Category | Finding | File:Line | Action |
|---|----------|----------|---------|-----------|--------|

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
- **Does not fan out across many surfaces** — that is this plugin's `code-review-fanout` skill

## Gotchas

- **Don't skip self-review for "small" changes** — small changes have the highest ratio of "obviously fine" to "actually had a bug."
- **`criteria` mode is a reference, not an action** — it loads review criteria so you can see what to check; combine with `self` mode for an informed review.
