---
description: "Single-lens review checkpoint between 'code works' and 'code is ready'. Routes to self, code, architecture, security, spec, close-out, downstream, pr, criteria, slice, or restatement mode and delegates to the matching reviewer. Use when the user says 'review this', 'self-review', 'quality gate', 'code review', 'architecture review', 'security review', 'does this match the spec/issue/plan', or 'close-out review' / 'review the container' for a shipped spec container, or after implementation completes. Downstream mode covers 'what could this break', 'blast radius', 'what else does this touch', 'who calls this'. Breakage outside the diff on a change already written; assessing a plan's reach before implementation is '/planning:plan' and '/planning:devils-advocate', and a rename sweep is '/docs-hygiene:rename-references audit blast'."
argument-hint: "[self|code|architecture|security|spec|close-out|downstream|pr|criteria|slice|restatement]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(git branch --show-current)", "Bash(git status --porcelain | head -20)", "Bash(gh pr list --json number,title,headRefName,baseRefName --limit 10 2>/dev/null || echo \"unknown\")", "Bash(gh pr list:*)", "Bash(git rev-parse:*)", "Bash(git merge-base:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)", "Bash(gh api graphql:*)", "Bash(git ls-files --others --exclude-standard)", "Bash(git ls-remote --symref origin)", "Bash(git ls-remote --symref origin:*)", "Bash(git fetch origin)", "Bash(git fetch origin:*)", "Bash(git remote get-url:*)", "Bash(gh pr view:*)", "Bash(gh issue view:*)", "Bash(node \"${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup-apply.mjs\" --check:*)", "Bash(node ${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup-apply.mjs --check:*)"]
shell: bash
metadata:
  workflow-stage: review
  summary: Single-lens review checkpoint routed to the matching reviewer
---

**Arguments.** `[self|code|architecture|security|spec|close-out|downstream|pr|criteria|slice|restatement]`. `spec` takes `[--spec <path|id>]`, `close-out` takes `[--container <id>] [--dry-run]`, and `slice` takes `<name>`.

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 20 entries")
bounds nothing: the Bash tool returns the command's complete output into context before there is
anything to decide about.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git. The dated record for that composition claim is the worktree skill's
[reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

## Pre-computed context

Open PRs (match headRefName to current branch above; baseRefName is the PR's real base): !`gh pr list --json number,title,headRefName,baseRefName --limit 10 2>/dev/null || echo "unknown"`

## Purpose

Review is the quality checkpoint between "code works" and "code is ready." This skill structures that step so changes are inspected for consistency, correctness, and alignment with the project's conventions before verification or PR creation. Self-review catches errors tests miss. Inconsistencies, loose ends, convention drift, design shortcuts. Delegated reviews (code, architecture, security) bring specialized scrutiny the implementer's tunnel vision would miss.

**Depth, not breadth.** This skill picks ONE lens per invocation. For a multi-surface fan-out that runs many reviewers at once and ranks their combined findings, use this plugin's `fanout` skill instead.

## Shared inputs

- **Review diff base**. **mode-scoped override first:** `close-out` does not use this base at all.
  A spec container is not a branch, so that mode derives a container-scoped basis of its own, per
  execution shape ([context/close-out.md](context/close-out.md) "Why it needs its own diff basis").
  Every other mode uses the base below. When an open PR exists for the branch, its `baseRefName` is the base: dispatched reviewers diff `git merge-base origin/<baseRefName> HEAD`. The pre-computed PR list above is capped; when the current branch is absent from it, run `gh pr list --head <current-branch> --json number,baseRefName` before concluding no PR exists. Otherwise `git merge-base origin/HEAD HEAD` (falling back to the remote's resolved default branch via `git ls-remote --symref`, then `origin/main`; when none yields a merge-base the base is unresolved, never `HEAD`) so committed-clean branches still show their changes; untracked files come from `git ls-files --others --exclude-standard`.
- **Severity vocabulary**, the project's own review docs when present; else `${CLAUDE_PLUGIN_ROOT}/context/severity.md`.
- **Criteria resolution**. Review criteria resolve through the standards index per the plugin binding [`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md) (its "Resolution ladder" section owns the procedure), detailed in [context/criteria.md](context/criteria.md).
- **Findings location**. `<memory_dir>/reviews/<branch-slug>/`, never committed. `<memory_dir>` is `.work/` unless the project's instructions declare another memory root. `<branch-slug>` is the branch name lowercased, with `/` and every other non-`[a-z0-9._-]` character replaced by `-`. `<UTC-timestamp>` is `date -u +%Y%m%dT%H%M%SZ`. The session's first write verifies the memory root contains a `.gitignore` with `*`, creating it (announced) when absent; never edit the consumer's root `.gitignore`. Durable findings are `<UTC-timestamp>-<mode>.md` in that directory. Write repo-relative paths only, never absolute machine paths.

## Step 0: Detect review mode

`$ARGUMENTS`, optional mode selector. When given, use it directly; otherwise infer:

| Signal | Mode | Context file |
|--------|------|-------------|
| Just finished implementing, "review my work", bare invocation with uncommitted changes | **self** | [context/self.md](context/self.md) |
| "review the code", "code review" | **code** | [context/code.md](context/code.md) |
| "architecture review", new modules, cross-cutting structure | **architecture** | [context/architecture.md](context/architecture.md) |
| "security review", auth/input handling, API endpoints | **security** | [context/security.md](context/security.md) |
| "does this match the spec/issue/plan", "did we build what was asked", scope-creep check, `spec [--spec <path\|id>]` | **spec** | [context/spec.md](context/spec.md) |
| "close-out review", "review the container", "did the whole spec ship", a spec container whose last sub-item just closed, `close-out [--container <id>] [--dry-run]` | **close-out** | [context/close-out.md](context/close-out.md) |
| "what could this break", "blast radius", "what else does this touch", "who calls this", a contract/signature/serialization change | **downstream** | [context/downstream.md](context/downstream.md) |
| "review the PR", a PR exists for the branch | **pr** | [context/pr.md](context/pr.md) |
| "review criteria", "what should I check" | **criteria** | [context/criteria.md](context/criteria.md) |
| `slice <name>`, "review testing", "review concurrency" | **slice** | [context/per-slice.md](context/per-slice.md) |
| "restatement review", "SSOT drift", markdown-heavy diff | **restatement** | [context/restatement.md](context/restatement.md) |

Ambiguous → present the modes and ask. **Read the matching context file before proceeding.**

**Downstream probe setting.** `downstream` mode reads one setting, `downstream_probe` (`run` or
`report`, default `run`). The user's option is `${user_config.downstream_probe}`; a literal,
unexpanded placeholder means unset. It is a policy floor: `report` from the user option or from
the repository's `docs/conventions/review.yaml`, read from the default branch, wins. The resolution
steps and the probe are in [context/downstream.md](context/downstream.md) ("Resolve
`downstream_probe`" and Step 2); keys and level rule:
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md).

## Step 0.5: Pre-flight gate (diff-consuming modes only)

**Mode-scoped by design.** `criteria` is a reference mode. It loads criteria rather than reviewing
a change, and legitimately runs against a clean tree, so it is **exempt** and never gated.
`close-out` is gated, but **on its own basis, not this one**: it runs the same two checks below
against the container-scoped basis it derives, plus a rollup check that the container is actually
finished ([context/close-out.md](context/close-out.md) "Step 4"). Every remaining mode consumes the
branch review diff, so for those: resolve the review diff base ("Shared inputs") and confirm it
yields a non-empty diff BEFORE dispatching any reviewer.

- **Unresolvable base**, an open PR's `origin/<baseRefName>` fails `git rev-parse --verify` even
  after a fetch (do NOT silently substitute a different base. That reviews the wrong diff), or no
  ladder ref resolves at all → report which ref failed and STOP.
- **Nothing to review**. No tracked diff against the base AND no untracked files → say so and
  STOP; never stage files to manufacture a diff.

**Untracked-only is reviewable here, and this is a deliberate divergence from `fanout`.** This
skill's Shared inputs hand untracked files to the dispatched reviewer directly ("Shared inputs";
the `self` and `slice` worker templates both read them), so a branch whose whole change is new
files has a real change set. Stopping on it would make a new-module or new-test review report
"nothing to review" about work that is plainly there. `fanout` stops on that case because its
surfaces receive only the merge-base diff, which cannot show an unstaged file. Review the untracked
files in place; still never `git add` them.

Either outcome dispatches ZERO reviewers: a lens run against an empty or wrong change set produces
noise, not a verdict. Two modes add a gate of their own on top of this one: an explicitly passed
`--spec` ref that does not resolve is a STOP ([context/spec.md](context/spec.md) "Rung 1"), and so
is an explicitly passed `--container` ref that does not resolve
([context/close-out.md](context/close-out.md) "Step 1").

## Step 1: Gather context

1. **What changed?**. Pre-computed facts above + the review diff base
2. **What was the goal?**, the original task, approved plan, or user intent from conversation. In every mode but `spec` and `close-out` this is background for judging the change; making the goal the thing under judgment is `spec` mode, which owns the spec-source discovery ladder and the fidelity finding classes. `close-out` is that same lens at container scale, reusing both and resolving its spec from the container instead of the branch
3. **What conventions apply?**. Resolve the project's standards for the changed surfaces through the standards index per the Shared-inputs criteria-resolution binding, so every review mode grounds in the same rows plan formulation loaded

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

- **All clear**. Suggest the project's next verification step (build/test, outcome verification, PR creation)
- **Fixes needed**. List specific actions; after fixes, suggest a quick re-run of `self` mode. In a review-fix round, change exactly the lines each finding names; any other edit needs its own finding first. Unscoped edits made while fixing are where later rounds' defects come from, so the round stays bounded by its findings
- **Design fundamentally flawed**. Suggest revisiting the plan/design before more code lands

## What this skill does NOT do

- **Does not run builds or tests**. Use the project's build/test tooling (or this plugin's `ecosystem-specialist` agent) separately. One exception: `downstream` mode, under `downstream_probe: run`, runs the single probe it writes for its safety fact ([context/downstream.md](context/downstream.md) Step 2)
- **Does not write or fix code**. It identifies issues; the implementer fixes them
- **Does not fan out across many surfaces**. That is this plugin's `fanout` skill

## Spoke paths

The `context/` files write the plugin's root directory as `<plugin-root>`, which is
`${CLAUDE_PLUGIN_ROOT}`. Put that path in place of the placeholder before running a command or
writing it into a brief. Those files arrive through the Read tool as plain bytes, so a `${…}` token
in them would reach the Bash tool unsubstituted, and the Bash tool's environment has no
`CLAUDE_PLUGIN_ROOT` to expand it from. Basis: the plugins reference,
<https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>, verified
2026-10-07; recheck when that table adds supporting files to where a `${…}` reference resolves.

## Next

`/verification:confirm`, when it is among the available skills, after an all-clear verdict, then
PR creation; after fixes, a `self` re-run of this skill (Step 4).

## Gotchas

- **Don't skip self-review for "small" changes**. Small changes have the highest ratio of "obviously fine" to "actually had a bug."
- **`criteria` mode is a reference, not an action**. It loads review criteria so you can see what to check; combine with `self` mode for an informed review.
