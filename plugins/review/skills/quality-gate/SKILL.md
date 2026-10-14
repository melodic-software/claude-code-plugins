---
description: "Single-lens review checkpoint between 'code works' and 'code is ready': self, code, architecture, security, spec, close-out, downstream, pr, criteria, slice or restatement mode, each delegated to the matching reviewer. Use when the user asks to 'review this', for a 'self-review' or 'quality gate', a code, architecture or security review, whether the change 'matches the spec/issue/plan', a 'close-out review' of a shipped spec container, 'what could this break' or the 'blast radius' of a written change, or after implementation completes."
argument-hint: "[self|code|architecture|security|spec|close-out|downstream|pr|criteria|slice|restatement]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(git branch --show-current)", "Bash(git status --porcelain | head -20)", "Bash(git rev-parse:*)", "Bash(git merge-base:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)", "Bash(git ls-files --others --exclude-standard)", "Bash(git ls-remote --symref origin)", "Bash(git ls-remote --symref origin:*)", "Bash(git fetch origin)", "Bash(git fetch origin:*)", "Bash(git remote get-url:*)", "Bash(node \"${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup-apply.mjs\" --check:*)", "Bash(node ${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup-apply.mjs --check:*)"]
shell: bash
metadata:
  workflow-stage: review
  summary: Single-lens review checkpoint routed to the matching reviewer
---

**Arguments.** `[self|code|architecture|security|spec|close-out|downstream|pr|criteria|slice|restatement]`. `spec` takes `[--spec <path|id>]`, `close-out` takes `[--container <id>] [--dry-run]`, and `slice` takes `<name>`.

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`

Keep the pipe in the command; it is the bound. Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as separate body Bash calls, not pre-compute lines. Pointer: the worktree skill's [reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md), "The pre-compute block runs as one shell invocation", which holds the dated record and its recheck trigger.

## Purpose

Inspect a change for consistency, correctness and alignment with the project's conventions before verification or PR creation, through ONE lens per invocation. A multi-surface fan-out with ranked combined findings is this plugin's `fanout` skill.

## Shared inputs

- **Review diff base.** `close-out` derives its own container-scoped basis ([context/close-out.md](context/close-out.md) "Why it needs its own diff basis"); every other mode uses this one. When an open PR exists for the branch, its `baseRefName` is the base: dispatched reviewers diff `git merge-base origin/<baseRefName> HEAD`. Find it with `/source-control:pull-request list --head <current-branch>` via the Skill tool when the `source-control` plugin is installed, else the forge's list of open PRs by head branch. One row gives the base; an empty array means no open PR. A failed read is not "no PR": the base is unresolved, so stop and report it rather than substitute another base. With no PR, `git merge-base origin/HEAD HEAD` (falling back to the remote's resolved default branch via `git ls-remote --symref`, then `origin/main`; when none yields a merge-base the base is unresolved, never `HEAD`). Untracked files come from `git ls-files --others --exclude-standard`.
- **Severity vocabulary**, the project's own review docs when present; else `${CLAUDE_PLUGIN_ROOT}/context/severity.md`.
- **Criteria resolution.** Review criteria resolve through the standards index per [`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md) "Resolution ladder", detailed in [context/criteria.md](context/criteria.md).
- **Findings location.** `<memory_dir>/reviews/<branch-slug>/`, never committed. `<memory_dir>` is `.work/` unless the project's instructions declare another memory root. `<branch-slug>` is the branch name lowercased, with `/` and every other non-`[a-z0-9._-]` character replaced by `-`. `<UTC-timestamp>` is `date -u +%Y%m%dT%H%M%SZ`. The session's first write verifies the memory root contains a `.gitignore` with `*`, creating it (announced) when absent; never edit the consumer's root `.gitignore`. Durable findings are `<UTC-timestamp>-<mode>.md` in that directory. Write repo-relative paths only, never absolute machine paths.

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

**Downstream probe setting.** `downstream` mode reads `downstream_probe` (`run` or `report`, default `run`). The user's option is `${user_config.downstream_probe}`; a literal, unexpanded placeholder means unset. It is a policy floor: `report` from the user option or from the repository's `docs/conventions/review.yaml`, read from the default branch, wins. Resolution steps and the probe: [context/downstream.md](context/downstream.md) ("Resolve `downstream_probe`" and Step 2); keys and level rule: [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md).

## Step 0.5: Pre-flight gate (diff-consuming modes only)

`criteria` loads criteria rather than reviewing a change, so it is exempt and runs on a clean tree. `close-out` runs the two checks below against its own container-scoped basis, plus a rollup check that the container is finished ([context/close-out.md](context/close-out.md) "Step 4"). Every other mode resolves the review diff base and confirms a non-empty change set BEFORE dispatching any reviewer:

- **Unresolvable base:** an open PR's `origin/<baseRefName>` fails `git rev-parse --verify` even after a fetch, or no ladder ref resolves → report which ref failed and STOP. Never substitute a different base; that reviews the wrong diff.
- **Nothing to review:** no tracked diff against the base AND no untracked files → say so and STOP; never stage files to manufacture a diff.

Untracked-only changes are reviewable here (unlike `fanout`, whose surfaces see only the merge-base diff): this skill hands untracked files to the reviewer directly, so review them in place and never `git add` them.

Either STOP dispatches ZERO reviewers. Two modes add their own gate: an explicit `--spec` ref that does not resolve is a STOP ([context/spec.md](context/spec.md) "Rung 1"), and so is an explicit `--container` ref that does not resolve ([context/close-out.md](context/close-out.md) "Step 1").

## Step 1: Gather context

1. **What changed?** The repository context above plus the review diff base.
2. **What was the goal?** The original task, approved plan, or user intent from the conversation. Outside `spec` and `close-out` it is background for judging the change; `spec` makes the goal the thing under judgment (it owns the spec-source discovery ladder and the fidelity finding classes), and `close-out` applies that lens at container scale, resolving its spec from the container.
3. **What conventions apply?** Resolve the project's standards for the changed surfaces through the standards index (Shared inputs, criteria resolution).

## Step 2: Execute the review

Follow the selected context file. Two hard rules:

- **Self mode never runs the checklist on the producing thread.** Dispatch a fresh-context read-only subagent; the thread that wrote the code rubber-stamps its own recap.
- **Delegated modes synthesize, never substitute.** Verify each returned finding against the actual diff before presenting it; a subagent's report is synthesis, not evidence.

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

- **All clear.** Suggest the project's next verification step (build/test, outcome verification, PR creation).
- **Fixes needed.** List specific actions; after fixes, suggest a `self` re-run. In a review-fix round, change exactly the lines each finding names; any other edit needs its own finding first.
- **Design fundamentally flawed.** Suggest revisiting the plan or design before more code lands.

## What this skill does NOT do

- **Run builds or tests.** Use the project's tooling (or this plugin's `ecosystem-specialist` agent). Exception: `downstream` mode under `downstream_probe: run` runs the single probe it writes for its safety fact ([context/downstream.md](context/downstream.md) Step 2).
- **Write or fix code.** It identifies issues; the implementer fixes them.
- **Fan out across many surfaces.** That is `fanout`.

## Spoke paths

The `context/` files write the plugin root as `<plugin-root>`, which is `${CLAUDE_PLUGIN_ROOT}`. Substitute it before running a command or writing it into a brief: a spoke arrives as plain bytes, so a `${…}` token in it would reach Bash unexpanded. Pointer: <https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>. As of: 2026-10-07. Recheck trigger: that table adds supporting files to where a `${…}` reference resolves.

## Next

`/verification:confirm`, when it is among the available skills, after an all-clear verdict, then PR creation; after fixes, a `self` re-run of this skill (Step 4).

## Gotchas

- **Small changes still get self-review.** They carry the highest ratio of "obviously fine" to "actually had a bug."
- **`criteria` mode is a reference, not an action.** It loads the criteria; pair it with `self` mode for an informed review.
