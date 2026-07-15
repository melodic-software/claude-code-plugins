# Foundations (Sections 1–15)

Core workflow tips — Parts 1–2 (Jan 2, Jan 31, 2026).

---

## 1. Parallel Execution

### Run Multiple Claude Sessions in Parallel

The single biggest productivity unlock. Spin up 3-5 git worktrees at once, each running its own Claude session.

```bash
# Create a worktree
git worktree add .claude/worktrees/my-worktree origin/main

# Start Claude in it
cd .claude/worktrees/my-worktree && claude
```

**Why worktrees over checkouts:** Claude Code team prefers worktrees — why native support was built into Claude Desktop.

**Pro tips:**

- Name worktrees and set shell aliases (za, zb, zc) to hop between them in one keystroke
- Dedicated "analysis" worktree for reading logs and running BigQuery
- iTerm2/terminal notifications to know when any Claude needs attention
- Color-code and name terminal tabs, one per task/worktree

### Web and Mobile Sessions

Beyond the terminal, run additional sessions on claude.ai/code:

- `&` command to background a session
- `--teleport` flag to switch contexts between local and web
- Claude iOS app to start sessions on the go, pick up on desktop later

---

## 2. Model Selection

### Use Opus 4.5 with Thinking for Everything

Boris's reasoning: "It's the best coding model I've ever used, and even though it's bigger & slower than Sonnet, since you have to steer it less and it's better at tool use, it is almost always faster than using a smaller model in the end."

**The math:** Less steering + better tool use = faster overall results, even with a larger model.

---

## 3. Plan Mode

### Start Every Complex Task in Plan Mode

Press `shift+tab` to cycle to plan mode. Pour energy into the plan so Claude can 1-shot the implementation.

**Workflow:** Plan mode → Refine plan → Auto-accept edits → Claude 1-shots it

**Team patterns:**

- One Claude writes the plan, a second Claude reviews it as a staff engineer
- Moment something goes sideways, switch back to plan mode and re-plan
- Explicitly tell Claude to enter plan mode for verification steps, not just the build

"A good plan is really important to avoid issues down the line."

---

## 4. CLAUDE.md Best Practices

### Invest in Your CLAUDE.md

Share a single CLAUDE.md per repo, checked into git. Whole team should contribute.

**Key practice:** "Anytime we see Claude do something incorrectly we add it to the CLAUDE.md, so Claude knows not to do it next time."

**After every correction:** End with "Update your CLAUDE.md so you don't make that mistake again." Claude is eerily good at writing rules for itself.

**Advanced:** One engineer has Claude maintain a notes directory per task/project, updated after every PR. CLAUDE.md points at it.

### @.claude in Code Reviews

Tag @.claude on PRs to add learnings to CLAUDE.md as part of the PR. Use Claude Code GitHub Action (`/install-github-action`).

Example PR comment:

```
nit: use a string literal, not ts enum

@claude add to CLAUDE.md to never use enums,
always prefer literal unions
```

"Compounding Engineering" — Claude auto-updates CLAUDE.md with the learning.

---

## 5. Skills & Slash Commands

### Create Your Own Skills

Create skills, commit to git. Reuse across every project.

**Team tips:**

- Do something more than once a day → turn it into a skill or command
- Build a `/techdebt` slash command, run it at end of every session to find and kill duplicated code
- Slash command syncing 7 days of Slack, GDrive, Asana, GitHub into one context dump
- Analytics-engineer-style agents that write dbt models, review code, test changes in dev

### Slash Commands for Inner Loops

Use slash commands for workflows done many times a day. Commands checked into git under `.claude/commands/`, shared with team.

```
> /commit-push-pr
```

**Power feature:** Slash commands can include inline Bash to pre-compute info (like git status) for quick execution — no extra model calls.

---

## 6. Subagents

### Use Subagents for Common Workflows

Think of subagents as automations for the most common PR workflows:

```
.claude/
  agents/
    build-validator.md
    code-architect.md
    code-simplifier.md
    oncall-guide.md
    verify-app.md
```

**Examples:**

- `code-simplifier` — cleans up code after Claude finishes
- `verify-app` — detailed instructions for end-to-end testing

### Leveraging Subagents

- Append "use subagents" to any request where you want Claude to throw more compute at the problem
- Offload individual tasks to subagents to keep main agent's context window clean and focused
- Route permission requests to Opus 4.5 via a hook — let it scan for attacks and auto-approve the safe ones

---

## 7. Hooks

### PostToolUse Hooks for Formatting

PostToolUse hook auto-formats Claude's code. Claude generates well-formatted code 90% of the time; the hook catches edge cases preventing CI failures.

```json
"PostToolUse": [
  {
    "matcher": "Write|Edit",
    "hooks": [
      {
        "type": "command",
        "command": "bun run format || true"
      }
    ]
  }
]
```

### Stop Hooks for Long-Running Tasks

For very long-running tasks, use an agent Stop hook for deterministic checks — ensures Claude works uninterrupted.

---

## 8. Permissions

### Pre-Allow Safe Permissions

Instead of `--dangerously-skip-permissions`, use `/permissions` to pre-allow common safe commands. Most shared in `.claude/settings.json`.

For sandboxed environments, use `--permission-mode=dontAsk` or `--dangerously-skip-permissions` to avoid blocks.

---

## 9. MCP Integrations

### Tool Integrations

Claude Code uses your tools autonomously:

- Searches and posts to **Slack** (via MCP server)
- Runs **BigQuery** queries with bq CLI
- Grabs error logs from **Sentry**

```json
{
  "mcpServers": {
    "slack": {
      "type": "http",
      "url": "https://slack.mcp.anthropic.com/mcp"
    }
  }
}
```

### Data & Analytics

Ask Claude Code to use the "bq" CLI to pull and analyze metrics on the fly. Have a BigQuery skill checked into the codebase.

Boris's take: "Personally, I haven't written a line of SQL in 6+ months."

Works for any database with a CLI, MCP, or API.

---

## 10. Prompting Tips

### Challenge Claude

- Say "Grill me on these changes and don't make a PR until I pass your test."
- Say "Prove to me this works" and have Claude diff behavior between main and your feature branch

### After a Mediocre Fix

Say: "Knowing everything you know now, scrap this and implement the elegant solution."

### Write Detailed Specs

Reduce ambiguity before handing work off. More specific = better output.

**Key insight:** Don't accept the first solution. Push Claude to do better — it usually can.

---

## 11. Terminal Setup

### Recommended Tools

- **Ghostty** terminal — synchronized rendering, 24-bit color, proper unicode support
- `/statusline` to customize status bar; always show context usage and current git branch

### Voice Dictation

Use voice dictation! You speak 3x faster than you type — prompts get way more detailed. Hit `fn x2` on macOS.

---

## 12. Bug Fixing

### Let Claude Fix Bugs

Enable the Slack MCP, paste a Slack bug thread into Claude, say "fix." Zero context switching.

Or just say "Go fix the failing CI tests." Don't micromanage how.

**Pro tip:** Point Claude at docker logs to troubleshoot distributed systems — surprisingly capable at this.

---

## 13. Long-Running Tasks

### Handle Long-Running Tasks

For very long-running tasks, ensure Claude works uninterrupted:

**Options:**

- **(a)** Prompt Claude to verify with a background agent when done
- **(b)** Agent Stop hook for deterministic checks
- **(c)** "ralph-wiggum" plugin (community idea by @GeoffreyHuntley)

Sandboxed environments: use `--permission-mode=dontAsk` or `--dangerously-skip-permissions` to avoid blocks.

---

## 14. Verification (The #1 Tip)

### Give Claude a Way to Verify Its Work

"Probably the most important thing to get great results out of Claude Code - give Claude a way to verify its work. If Claude has that feedback loop, it will 2-3x the quality of the final result."

**Verification varies by domain:**

- Bash commands
- Test suites
- Simulators
- Browser testing (Claude Chrome extension)

Key: give Claude a way to close the feedback loop. Invest in domain-specific verification for optimal performance.

---

## 15. Learning with Claude

### Use Claude for Learning

- Enable "Explanatory" or "Learning" output style in /config to have Claude explain the *why* behind changes
- Have Claude generate visual HTML presentations explaining unfamiliar code
- Ask Claude to draw ASCII diagrams of new protocols and codebases
- Build a spaced-repetition learning skill: explain your understanding, Claude asks follow-ups to fill gaps

**Key takeaway:** Claude Code isn't just for writing code - it's a powerful learning tool when you configure it to explain and teach.
