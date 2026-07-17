---
name: thariq-skills
description: >
  Guide for designing and authoring Claude Code skills. Covers 9 skill categories,
  authoring best practices, progressive disclosure, and distribution strategies.
  Trigger on "create a skill", "new skill", "skill structure", "skill best practices",
  "skill design", "what kind of skill", "skill types", "how to write a skill".
version: 1.0.0
date: 2026-03-17
user-invocable: true
---

# How To Use Skills — from Anthropic's internal playbook

Based on [Thariq's March 17, 2026 post](https://x.com/trq212/status/2033949937936085378).
Anthropic runs hundreds of skills in production. These are the lessons learned.

---

## 9 Types of Skills

The best skills fit cleanly into one category. Straddling several = confused skill.

| Category | What it does | Examples |
|---|---|---|
| **Library & API Reference** | Gotchas, edge cases, usage for internal/external libs | billing-lib, platform-cli, frontend-design |
| **Product Verification** | Drive UI flows with playwright/tmux, assert state at each step | signup-flow-driver, checkout-verifier |
| **Data Fetching & Analysis** | Connect to monitoring/data stacks with credentials and query patterns | funnel-query, cohort-compare, grafana |
| **Business Automation** | Multi-tool workflows into one command | standup-post, create-ticket, weekly-recap |
| **Scaffolding & Templates** | Framework boilerplate with natural-language requirements | new-workflow, new-migration, create-app |
| **Code Quality & Review** | Enforce code quality, adversarial review, testing practices | adversarial-review, code-style, testing-practices |
| **CI/CD & Deployment** | Fetch, push, deploy code with safety checks | babysit-pr, deploy-service, cherry-pick-prod |
| **Runbooks** | Symptom → multi-tool investigation → structured report | service-debugging, oncall-runner, log-correlator |
| **Infrastructure Ops** | Routine maintenance with guardrails for destructive actions | orphan-cleanup, dependency-management, cost-investigation |

---

## 9 Tips for Authoring Skills

### 1. Don't State the Obvious
Claude already knows a lot about coding. Focus on information that pushes Claude out of its normal way of thinking. The frontend-design skill works because it corrects Claude's default aesthetic (Inter font, purple gradients), not because it explains what CSS is.

### 2. Build a Gotchas Section
The highest-signal content in any skill. Build it up iteratively from common failure points Claude runs into. Add a line every time Claude trips on something. Day 1 your gotchas section has 1 entry. By month 3 it has 10. That's the most valuable part of the skill.

### 3. Use the File System & Progressive Disclosure
A skill is a folder, not just a markdown file. Think of the entire file system as context engineering. SKILL.md is the hub (~30 lines); spoke files do the work.

Example structure:
```
queue-debugging/
  SKILL.md          ← hub: symptom → file lookup table
  stuck-jobs.md
  dead-letters.md
  retry-storms.md
  consumer-lag.md
```

Tell Claude what files are in your skill and it will read them at appropriate times.

### 4. Avoid Railroading Claude
Don't write step-by-step scripts. Give Claude the information it needs with flexibility to adapt.

Too prescriptive:
> Step 1: Run git log to find the commit.
> Step 2: Run git cherry-pick <hash>.
> Step 3: If there are conflicts, run git status to list them...

Better:
> Cherry-pick the commit onto a clean branch. Resolve conflicts preserving intent. If it can't land cleanly, explain why.

### 5. The Description Field Is For the Model
When Claude Code starts a session, it builds a listing of every available skill with its description. This is what Claude scans to decide "is there a skill for this request?" The description is not a summary — it's a trigger condition.

Bad: `description: A comprehensive tool for monitoring pull request status across the development lifecycle.`

Good: `description: Monitors a PR until it merges. Trigger on 'babysit', 'watch CI', 'make sure this lands'.`

### 6. Think Through the Setup
Some skills need user context on first run. Store setup info in a config.json in the skill directory. If the config is missing, ask the user.

Example pattern: use an inline bash block to cat a config.json from the skill directory. If the file doesn't exist, output "NOT_CONFIGURED". Then in the instructions section, if NOT_CONFIGURED, prompt the user for setup values (e.g. Slack channel, sample standup) and write them to config.json in the skill directory.

### 7. Memory & Storing Data
Skills can store data for continuity between runs. Use `${CLAUDE_PLUGIN_DATA}` as a stable folder — data in the skill directory may be deleted on upgrade.

Options: append-only text logs, JSON files, or even SQLite databases. A standup-post skill might keep a standups.log so Claude can diff against yesterday.

### 8. Store Scripts & Generate Code
Give Claude code, not just instructions. Include helper libraries so Claude spends its turns on composition rather than reconstructing boilerplate.

Example: a data science skill with `lib/signups.py` containing `fetch(day)`, `by_referrer(df)`, `by_landing_page(df)`. Claude then generates investigation scripts that compose these functions.

### 9. On-Demand Hooks
Skills can include hooks that activate only when the skill is called and last for the session duration. Use for opinionated guardrails you don't want running all the time.

Examples:
- `/careful` — blocks rm -rf, DROP TABLE, force-push, kubectl delete via PreToolUse matcher on Bash
- `/freeze` — blocks any Edit/Write outside a specific directory

---

## Distribution

Two approaches:
1. **Check into repo** (`.claude/skills/`) — good for smaller teams, few repos
2. **Plugin marketplace** — scales better, lets teams decide what to install

For marketplaces: let skills start in a sandbox folder on GitHub. Once they get traction (determined by the skill owner), promote to the marketplace via PR. Curate before release — bad or redundant skills are easy to create.

### Measuring Skills
Use a PreToolUse hook to log skill usage. Find skills that are popular or undertriggering compared to expectations.

### Composing Skills
Reference other skills by name in your skill. Claude will invoke them if installed. Native dependency management isn't built in yet.

---

## Quick Reference

| Principle | One-liner |
|---|---|
| Skip the obvious | Claude has defaults — push it off the beaten path |
| Gotchas section | Highest signal. Add a line every failure |
| Progressive disclosure | Folder, not file. Hub dispatches, spokes do work |
| Don't railroad | Info + flexibility > step-by-step scripts |
| Description = trigger | Write it for the model, include trigger phrases |
| Setup pattern | config.json + first-run prompting |
| Store data | ${CLAUDE_PLUGIN_DATA} persists across upgrades |
| Give it code | Helper scripts > prose instructions |
| On-demand hooks | Session-scoped guardrails for risky contexts |

---

Source: [@trq212's March 17, 2026 post](https://x.com/trq212/status/2033949937936085378)
