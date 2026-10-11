# Advanced (Sections 34–45)

Power features and automation: Parts 7–8 (Mar 13, Mar 23–26, 2026).

---

## 34. /effort: Max Reasoning Mode

Set effort to 'max'. Claude reasons longer, uses as many tokens as needed. Burns usage limits faster; activate per session.

```
> /effort max
```

Use 'max' for hard debugging, architecture decisions, tricky code where Claude needs to think it through.

> **Amended:** the levels a model offers and its default level vary by model. For the current
> levels and defaults, see
> [Claude Code model config, "Choose an effort level"](https://code.claude.com/docs/en/model-config#choose-an-effort-level).
> **As of:** 2026-09-30. **Recheck trigger:** that section is renamed or removed, or stops stating
> each model's default level.

Source: https://x.com/trq212/status/2032632596572811575

## 35. Remote Control: Spawn New Sessions

Run `claude remote-control` and spawn a new local session from the mobile app. Which plans and versions it needs is in the amendment below.

```bash
$ claude remote-control
# Open Claude mobile app → tap "Code" → start new session
```

Walk away from desk, think of something, kick off task from mobile. Claude runs on your machine.

> **Amended:** the plan list in this tip is out of date, and the feature now has conditions the tip
> predates. Read the current requirements rather than this tip.
>
> - **Pointer**: before relying on Remote Control for a plan or account type, fetch
>   [Remote Control requirements](https://code.claude.com/docs/en/remote-control#requirements) live.
> - **As of**: 2026-10-11
> - **Recheck trigger**: that section changes which plans, versions or account settings it
>   requires.

Source: https://x.com/trq212/status/2032632597843779861

## 36. Voice Mode

Voice mode rolled out to 100% of users, including Claude Code Desktop and Cowork. Click microphone icon and talk naturally.

Useful for hands-free coding, dictating complex requirements, or when thinking faster than typing.

Source: https://x.com/trq212/status/2032632599429136753

## 37. Setup Scripts for Cloud Environments

Add a setup script in Claude Code on web and desktop. Runs before Claude Code launches on cloud: install dependencies, configure settings, set env vars.

```bash
# Setup script (runs on new session start, skipped on resume):
#!/bin/bash
yarn install
```

Particularly useful for installing dependencies, settings, configs before Claude starts working.

Source: https://x.com/trq212/status/2032632601064907037

## 38. claude --name: Name Your Sessions

Name your session at launch via `--name`.

```bash
claude --name "auth-refactor"
```

Especially useful juggling multiple worktrees or sessions. Tells at a glance which session is doing what.

Source: https://x.com/trq212/status/2032632602629386348

## 39. Auto Session Naming After Plan Mode

After plan mode, Claude automatically names your session based on what you're working on. No manual naming needed.

Pairs with `claude --name`. Use `--name` when you know upfront, and let auto-naming handle it when you start by planning.

Source: https://x.com/trq212/status/2032632602629386348

## 40. /color: Customize Prompt Color

Change prompt input color via `/color`. With 3-5 sessions open in different terminals, color-coding makes it instantly clear which is which.

```
> /color
```

Source: https://x.com/trq212/status/2032632602629386348

## 41. PostCompact Hook

Hook event firing after Claude compresses conversation context. Re-inject critical instructions that might get lost during compaction, log compaction events, or trigger automation.

```json
"hooks": {
  "PostCompact": [{
    "matcher": "",
    "hooks": [{ "type": "command", "command": "echo 'Context was compacted'" }]
  }]
}
```

Source: https://x.com/trq212/status/2032632602629386348

## 42. Auto Mode: Safer Permission Skipping

Instead of approving every file write and bash command, or skipping permissions entirely, auto mode lets Claude decide on your behalf. Classifiers evaluate each action before it runs. Safe operations are auto-approved, risky ones still flagged.

```bash
# Start in auto mode: see the amendment below for the current flag.

# Or cycle with shift+tab during a session:
# plan mode → auto mode → normal mode
```

> **Amended:** the launch flag in this tip no longer starts auto mode. Start a session in auto mode
> the way the CLI reference currently documents.
>
> - **Pointer**: when starting a session in auto mode from the command line, fetch
>   [CLI flags](https://code.claude.com/docs/en/cli-reference#cli-flags) live.
> - **As of**: 2026-10-11
> - **Recheck trigger**: that table changes the flag that starts a session in auto mode.

Boris's take: "no 👏 more 👏 permission prompts 👏"

Source: https://x.com/bcherny/status/2036555259997462541

## 43. /schedule: Cloud Jobs from Your Terminal

`/schedule` creates recurring cloud-based jobs from the terminal. Unlike `/loop` (session-scoped on your machine), scheduled jobs run in the cloud and work even when your laptop is closed.

```
> /schedule a daily job that looks at all PRs shipped since yesterday
  and update our docs based on the changes. Use the Slack MCP to
  message #docs-update with the changes
```

Anthropic team uses these internally to auto-resolve CI failures, push doc updates, power automations needing to exist beyond a closed laptop.

Source: https://x.com/noahzweben/status/2036129220959805859

## 44. iMessage Plugin: Text Claude from Your Phone

iMessage is available as a Claude Code channel. Install the plugin and text Claude like a friend, from any Apple device.

```bash
/plugin install imessage@claude-plugins-official
```

Claude Code becomes a contact in Messages. Send tasks, get responses as iMessages. Works from iPhone, iPad, Mac, no terminal needed. Pairs with remote control sessions for kicking off work from anywhere.

Source: https://x.com/trq212/status/2036959638646866021

## 45. Auto-Memory & Auto-Dream: Persistent, Self-Cleaning Memory

Claude Code has a built-in memory system. Run `/memory` to configure it.

**Auto-memory:** When enabled, Claude auto-saves preferences, corrections, patterns between sessions. User memory → `~/.claude/CLAUDE.md`, project memory → `./CLAUDE.md`.

**Auto-dream:** As memory accumulates, it gets messy: outdated assumptions, overlapping notes, low-signal entries. Auto-dream runs a subagent that periodically reviews past sessions, keeps what matters, removes what doesn't, merges insights into cleaner structured memory. Run `/dream` to trigger manually, or enable auto-dream in `/memory` settings.

Naming maps to how REM sleep consolidates short-term memory into long-term storage.
