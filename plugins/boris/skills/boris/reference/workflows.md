# Workflows (Sections 29–33)

Built-in workflow tools — Parts 5–6 (Feb 27, Mar 7–10, 2026).

---

## 29. /simplify — Improve Code Quality

Parallel agents improve code quality, tune efficiency, ensure CLAUDE.md compliance. Append `/simplify` to any prompt after changes.

```
> hey claude make this code change then run /simplify
```

Boris uses daily to shepherd PRs to production. Skill runs parallel agents reviewing changed code for reuse, quality, efficiency — one pass.

---

## 30. /batch — Parallel Code Migrations

Plan code migrations interactively, then execute in parallel via dozens of agents. Each runs isolated in a git worktree, tests its work, opens a PR.

```
> /batch migrate src/ from Solid to React
```

Plan migration interactively; `/batch` fans work to parallel agents — each in its own worktree, testing and creating a PR independently.

---

## 31. /loop — Schedule Recurring Tasks

`/loop` schedules recurring tasks in the current session; recurring jobs expire 7 days after creation. Claude runs your prompt on interval, handling long-running workflows autonomously.

```
> /loop babysit all my PRs. Auto-fix build issues and when comments come in, use a worktree agent to fix them
```

```
> /loop every morning use the Slack MCP to give me a summary of top posts I was tagged in
```

Uses: PR babysitting, Slack summaries, deploy monitoring, any repeating workflow.

Learn more: https://code.claude.com/docs/en/scheduled-tasks

## 32. Code Review — Agents Hunt for Bugs

When a PR opens, Claude dispatches a team of agents to hunt bugs. Anthropic built for themselves first — engineer code output up 200% this year, reviews were the bottleneck.

Each agent focuses on one concern — logic errors, security issues, performance regressions — then posts inline comments on the PR. Boris used for weeks pre-launch; catches real bugs he'd have missed.

Source: https://x.com/bcherny/status/2031089411820228645

## 33. /btw — Ask Questions While Claude Works

Slash command for side-chain conversations while Claude is working. Single-turn, no tool calls, full conversation context.

```
> /btw what does the retry logic do?
```

Claude responds inline without stopping work. Built by @ErikSchluntz as side project — 1.5M views on launch tweet.

Source: https://x.com/trq212/status/2031506296697131352
