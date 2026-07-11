# Boris's Favorite Hidden Features (Sections 46–60)

Boris's personal top 15 hidden and under-utilized features — March 29, 2026 thread.

Source: https://x.com/bcherny/status/2038454336355999749

---

## 46. Mobile App for Coding

Claude Code has a mobile app. Boris writes lots of code from the iOS app — convenient way to make changes without opening a laptop.

**How to use:** Download Claude app for iOS/Android, tap the Code tab on left.

Source: https://x.com/bcherny/status/2038454337811386436

---

## 47. Teleport & Remote Control — Session Mobility

Move sessions back and forth between mobile/web/desktop and terminal.

- **`claude --teleport`** or **`/teleport`** — continue a cloud session on local machine
- **`/remote-control`** — control a locally running session from phone/web

Boris has "Enable Remote Control for all sessions" set in `/config`.

See also: [Section 35 — Remote Control](advanced.md#35-remote-control--spawn-new-sessions)

Source: https://x.com/bcherny/status/2038454339933548804

---

## 48. /loop and /schedule Power Usage

Boris's running loops:

- `/loop 5m /babysit` — auto-address code review, auto-rebase, shepherd PRs to production
- `/loop 30m /slack-feedback` — auto-put up PRs for Slack feedback every 30 mins
- `/loop /post-merge-sweeper` — put up PRs to address missed code review comments
- `/loop 1h /pr-pruner` — close out stale and no longer necessary PRs

**Key insight:** Turn workflows into skills, then loop the skills.

See also: [Section 31 — /loop](workflows.md#31-loop--schedule-recurring-tasks), [Section 43 — /schedule](advanced.md#43-schedule--cloud-jobs-from-your-terminal)

Source: https://x.com/bcherny/status/2038454341884154269

---

## 49. Hooks — Deterministic Agent Lifecycle Logic

Hooks run logic at specific points in the agent lifecycle:

- **SessionStart** — dynamically load context each time Claude starts
- **PreToolUse** — log every bash command the model runs
- **PermissionRequest** — route permission prompts to WhatsApp for mobile approve/deny
- **Stop** — poke Claude to keep going whenever it stops

Docs: https://code.claude.com/docs/en/hooks

See also: [Section 6 — Hooks](foundations.md)

Source: https://x.com/bcherny/status/2038454343519932844

---

## 50. Cowork Dispatch

Boris uses Dispatch daily to catch up on Slack and emails, manage files, do things on his laptop when not at a computer.

Dispatch is a secure remote control for Claude Desktop. Uses your MCPs, browser, computer, with your permission.

Source: https://x.com/bcherny/status/2038454345419936040

---

## 51. Chrome Extension for Frontend Work

The most important tip for using Claude Code: **give Claude a way to verify its output.** Then Claude iterates until the result is great.

Think of it like any engineer: ask someone to build a website without a browser — will the result look good? Probably not. Give them a browser, they write code and iterate until it looks good.

Boris uses the Chrome extension every time he works on web code. Works more reliably than other similar MCPs.

Download: Chrome/Edge extension from Claude Code docs.

See also: [Section 14 — Verification](foundations.md)

Source: https://x.com/bcherny/status/2038454347156398333

---

## 52. Desktop App — Built-in Web Server Testing

Desktop app bundles the ability for Claude to auto-start and test web servers in a built-in browser. You can set up similar in CLI or VSCode via Chrome extension, or just use Desktop app.

Source: https://x.com/bcherny/status/2038454348804714642

---

## 53. Fork Sessions — /branch and --fork-session

Two ways to fork an existing session:

1. **`/branch`** from your session
2. From CLI: **`claude --resume <session-id> --fork-session`**

Source: https://x.com/bcherny/status/2038454350214041740

---

## 54. /btw for Side Queries

Boris uses `/btw` constantly to answer quick questions while the agent works.

See also: [Section 33 — /btw](workflows.md#33-btw--ask-questions-while-claude-works)

Source: https://x.com/bcherny/status/2038454351849787485

---

## 55. Git Worktrees — Essential for Parallel Work

Claude Code ships deep support for git worktrees. Worktrees are essential for parallel work in the same repository. Boris has dozens of Claudes running at all times.

- **`claude -w`** — start new session in a worktree
- **Desktop app** — hit "worktree" checkbox
- **Non-git VCS** — use `WorktreeCreate` hook to add your own logic

See also: [Section 28 — Worktrees](worktrees.md)

Source: https://x.com/bcherny/status/2038454353787519164

---

## 56. /batch — Fan Out Massive Changesets

`/batch` interviews you, then fans out work to as many worktree agents as it takes — dozens, hundreds, even thousands.

Use for large code migrations and other parallelizable work.

See also: [Section 30 — /batch](workflows.md#30-batch--parallel-code-migrations)

Source: https://x.com/bcherny/status/2038454355469484142

---

## 57. --bare — 10x Faster SDK Startup

By default, `claude -p` (and the TypeScript/Python SDKs) searches for local CLAUDE.md files, settings, MCPs. For non-interactive usage, most of the time you want to explicitly specify what to load via `--system-prompt`, `--mcp-config`, `--settings`, etc.

```bash
claude -p --bare --system-prompt "..." --mcp-config ./my-config.json
```

**Boris's note:** Design oversight when SDK was first built. In a future version, `--bare` becomes the default. Opt in now with the flag.

Source: https://x.com/bcherny/status/2038454357088457168

---

## 58. --add-dir — Multi-Repository Access

Working across multiple repos? Start Claude in one repo, use `--add-dir` (or `/add-dir`) to let Claude see other repos. Both tells Claude about the repo AND grants permissions to work in it.

```bash
claude --add-dir /path/to/other-repo
```

Or add `"additionalDirectories"` to team's `settings.json` to always load additional folders when Claude Code starts.

Source: https://x.com/bcherny/status/2038454359047156203

---

## 59. --agent — Custom System Prompt & Tools

Custom agents are a powerful primitive often overlooked. Define a new agent in `.claude/agents`, then run it:

```bash
claude --agent=<your-agent-name>
```

Docs: https://code.claude.com/docs/en/sub-agents

See also: [Section 22 — Agents](customization.md)

Source: https://x.com/bcherny/status/2038454360418787764

---

## 60. /voice — Voice Input

Fun fact: Boris does most of his coding by speaking to Claude, not typing.

- **CLI:** `/voice` then hold space bar
- **Desktop:** press the voice button
- **iOS:** enable dictation in iOS settings

See also: [Section 36 — Voice Mode](advanced.md#36-voice-mode)

Source: https://x.com/bcherny/status/2038454362226467112
