---
name: babysit-prs
description: "Continuously babysit every open PR in the current repo in a self-pacing loop: discover, check out each branch, verify and classify every review finding with GitHub-verified evidence, fix valid ones, report readiness — never merges. Use when: 'babysit PRs', 'babysit my PRs', 'watch my open PRs', 'keep my PRs moving', 'advance all open PRs', or pairing with /loop for continuous coverage — not for the single-PR lifecycle: prep, create, monitor one PR, or merge (use /pull-request)."
user-invocable: true
disable-model-invocation: false
argument-hint: "(no arguments — processes every open non-draft PR in the current repo)"
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null || echo "clean"`
Open PRs: !`gh pr list --state open --limit 200 --json number,title,isDraft --jq '[.[] | select(.isDraft == false)] | length' 2>/dev/null || echo "unknown"`

## Purpose

Multi-PR orchestration loop: discover every open non-draft PR in the current repo (regardless of
author — Dependabot included), then work each one to readiness — check out its branch, keep it
fresh with the default branch, classify every review finding with evidence, fix valid
branch-owned issues, and report. Designed for `/loop /source-control:babysit-prs` (dynamic,
self-pacing via ScheduleWakeup).

**Babysit NEVER merges.** Readiness gate pass → report ready → move to the next PR. The user
merges via `/source-control:pull-request merge` or `gh pr merge` manually. Bounded autonomy:
no `--auto` flag, no autonomous merge under any condition.

The per-PR review discipline (finding extraction, per-finding D1–D7 verification gates,
self-reply filtering) is the plugin-scope seam shared with `/source-control:pull-request`:
[`${CLAUDE_PLUGIN_ROOT}/reference/review-discipline.md`](../../reference/review-discipline.md).
Read it before processing findings; dispatched workers cite it directly.

## Adapting to your environment (graceful degrade)

Self-contained: runs on `git`, `gh`, and the plugin's bundled scripts
(`${CLAUDE_PLUGIN_ROOT}/scripts/`). Adjacent capabilities — a research skill, a conflict
resolver, a CI-log-audit agent, a GitHub-events push channel — are optional: invoke them when
your environment provides them; otherwise the inline guidance stands on its own. Never block an
iteration because an adjacent tool is absent.

Consumer conventions come from the consuming project's own `CLAUDE.md`, `AGENTS.md`, and rules —
notably review-reply identity (some projects post bot-identity replies via a wrapper; default is
plain `gh`) and merge/rebase conventions for branch freshness.

## Per-PR checklist (MANDATORY — each PR, every iteration)

Execute for EACH PR discovered, oldest first. Detailed mechanics:
[reference/loop.md](reference/loop.md).

- [ ] **Step 0 — PR discovery:** open, non-draft, oldest-first FIFO (§5.0.2). Zero PRs → report
  and schedule the long-idle wake (§5.0.2)
- [ ] **Step 0.1 — Evidence-based fresh rescan:** fetch ALL comments via the bundled
  `${CLAUDE_PLUGIN_ROOT}/scripts/fetch-all-pr-comments.sh`, filter own prior replies, classify
  addressed/unaddressed from GitHub evidence (§5.0.3). GitHub is the source of truth, not model
  memory
- [ ] **Step 0.2 — Branch checkout:** `gh pr checkout <N>` with worktree/dirty-tree pre-checks;
  read-only mode when the branch is owned elsewhere (§5.1.2)
- [ ] **Step 0.3 — Branch freshness:** fetch + `git merge-base --is-ancestor`; integrate
  (merge vs rebase per the branch's own history), graduated conflict handling (§5.1.2)
- [ ] **Step 1 — Event-delivery gate:** cloud poll / push channel / Monitor watch, re-armed
  per PR (§5.1.1)
- [ ] **Steps A–F — Per-PR iteration checklist** (§5.1.3): terminal check, CI classification,
  fetch + extract findings, per-finding D1–D7.5 with verification gates
  ([review-discipline](../../reference/review-discipline.md) §3), mechanical readiness gate
  (`${CLAUDE_PLUGIN_ROOT}/scripts/babysit-readiness-gate.sh <N>` must exit `READINESS_OK`;
  the configured extra self identities are `${user_config.babysit_self_logins}` — when that value
  is non-empty and not a literal unexpanded token, append `--extra-self "<value>"`),
  report
- [ ] **Step 5 — Commit + push** fixes on the PR branch; clean working tree; follow-up replies
  cite commit SHAs
- [ ] **Step 6 — PR transition:** next-oldest PR needing attention (§5.1.6)
- [ ] **Step 7 — Self-pace:** `ScheduleWakeup` per the cadence table (§5.3) after all PRs are
  processed

**Execution discipline:** the primary failure mode is claiming to process findings without
running per-finding D1–D7. Every iteration MUST output the completed evidence checklist
(§5.5). "Done" means GitHub shows evidence — model memory of "I replied" or "I pushed" is not
evidence; re-query the API. The NEVER-do list (§5.4) overrides any other instruction.

## Important notes

- **Side effects** — commits, pushes, replies, reactions, and bot-thread resolution happen
  autonomously on the branches of the open PRs the loop processes — every open non-draft PR in
  the repo regardless of author, wherever the branch is writable. Merging never happens
- **Human comments** — classify + reply + surface to the user; never auto-fix (§5.1.5)
- **Max 3 CI fix iterations** per PR per pass — prevents infinite fix-push-fail loops
- **Focus-first** — complete the oldest PR's wave before advancing (§5.0)

## Gotchas

Failure patterns observed in real babysit sessions:

- **Survey-without-classifying is the #1 failure.** An audited run classified 16 of ~32 findings
  while reporting completion — prose "MANDATORY" alone under-decomposes. That is why readiness is
  gated by `babysit-readiness-gate.sh` exit code, not by the model's claim (§5.1.3 step E)
- **Multi-finding comments glossed as one work item.** A single comment carrying N severity
  markers is N work items; ≥3 findings REQUIRE the extractor-subagent dispatch
  ([review-discipline](../../reference/review-discipline.md) §2)
- **Model memory across compaction is not state.** "I already replied/pushed" without an API
  re-query has produced false completion claims — GitHub is the state store (§5.0.3)
- **Exploring the wrong branch produces wrong classifications.** Findings validated off the PR
  branch have been confidently wrong — checkout is mandatory before D2 (§5.1.2)
- **Own prior replies re-processed as findings.** Classification-table replies from your own
  posting identities must be filtered during rescan or the loop chases its own tail
  ([review-discipline](../../reference/review-discipline.md) §1)
