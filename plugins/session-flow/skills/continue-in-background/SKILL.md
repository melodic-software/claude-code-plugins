---
name: continue-in-background
description: "Delegate the task to a fresh background agent that continues it NOW — produce a save-point, then launch a detached claude --bg session seeded with the resume prompt. Use when: 'continue in the background', 'continue this in the background', 'keep working in the background', 'delegate to a background agent', or the user is going AFK and explicitly wants the work to keep moving. Launches only on the user's explicit request — never self-elected."
argument-hint: "[file|prompt] [topic] (e.g., /continue-in-background, /continue-in-background prompt, /continue-in-background file phase-3)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Claude session: !`echo "${CLAUDE_CODE_SESSION_ID:-unknown}" || echo "unknown"`
Uncommitted changes: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`

## Purpose

The user is stepping away but the work should keep moving. This skill produces the same save-point
the sibling `/session-flow:handoff` skill produces, then — instead of asking the user to
`/clear`-and-paste — launches a fresh background agent seeded with the resume prompt, so the task
continues now, detached from this session and from the user's presence.

Same save-point engine as `handoff`, different delivery: `handoff` delivers a manual
`/clear`-then-paste resume for later; this skill delivers a background continuation for now.

## Hard gate — launch only on explicit user intent

Launching a detached session is a side effect the user must have asked for. Launch ONLY when the
user explicitly requested background delegation — invoked this skill by name, or asked in words
("continue this in the background", "keep it moving while I'm away"). NEVER self-elected: the user
merely going AFK, context being heavy, or this skill being model-invoked on a description match is
NOT authorization. When invoked without that explicit request, produce the save-point, emit the
rails resume prompt with the standard `/clear`-then-paste instruction, state that no agent was
launched because background delegation was not explicitly requested, and STOP — the user can ask
for the launch or run `/session-flow:continue-in-background` themselves.

## Arguments

`$ARGUMENTS` carries `[file|prompt] [topic]` — both optional and positional, with the same
semantics as `handoff`: method (`file` | `prompt`) recognized only as the first token, otherwise
auto-detect; topic is the kebab slug for the save-point filename, inferred when omitted. Before the
resolved topic is embedded anywhere (filename, `--name` flag), sanitize it to `[a-z0-9-]` only —
strip or replace every other character — so a crafted slug cannot smuggle quotes or extra flags
into the launch command.

## Produce the save-point

The save-point machinery — destination resolution, locating the position, full-vs-prompt-only
choice, the mandatory redaction pass, the handoff-file write, and the rails resume prompt — lives
in the shared engine doc
[`${CLAUDE_PLUGIN_ROOT}/reference/save-point.md`](${CLAUDE_PLUGIN_ROOT}/reference/save-point.md).
Walk it top to bottom; do not restate or improvise any of its steps. The launched agent receives
exactly the resume prompt that sits between the rails (full path: it follows the prompt's Read
directive to the handoff file; prompt-only: the remaining-work bullets travel inline).

## Delivery: background-agent launch

The rails prompt from the engine doc is still emitted FIRST (transparency + manual fallback),
then:

1. **Dirty-tree gate.** Run `git status --porcelain -uall` in the consuming project (`-uall`
   lists files inside untracked directories individually; the default collapses a brand-new
   handoff directory into one directory entry, which both defeats the exemption below and can
   hide other dirt behind it) and IGNORE save-point files under the handoff location — the
   just-written one AND any prior sessions' (this skill never commits them; they are
   session-chain artifacts, part of the launch rather than disqualifying dirty state; the
   background session starts in this working directory, so it reads the handoff file before any
   edit moves it into a worktree). Background sessions move into an isolated git worktree (a
   fresh checkout) before editing files (<https://code.claude.com/docs/en/agent-view>), so OTHER
   uncommitted changes in this checkout would NOT carry into the launched agent's edits. Any
   such changes → do NOT launch: report why and fall back to the standard `/clear`-then-paste
   instruction (same checkout, dirty state intact), noting the user can commit or stash and
   re-run `/continue-in-background`. Exception: launch anyway when the current session already
   runs inside a linked git worktree — isolation is skipped there per the same page.
2. Launch from the consuming project's root, passing the rails prompt verbatim as one argument.
   First write the prompt — exactly as emitted between the rails — to a temporary file with the
   Write tool (never inline it in the command: prompt content is untrusted session text, and any
   inline embedding — a heredoc, an escaped string — hands crafted content a path out of the
   quoting and into the shell). `<topic>` = the resolved, sanitized topic slug (argument or
   inferred); when none resolves, use `resume`:

   ```bash
   cd "${CLAUDE_PROJECT_DIR}" && CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1 claude --bg --name "continue-<topic>" "$(cat "<prompt-file>")" && rm -f "<prompt-file>"
   ```

   `claude --bg` starts the session as a background agent and returns immediately; the user
   manages it with `claude agents`. `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` is required
   because this launch runs from a Bash-tool subprocess, which carries
   `CLAUDE_CODE_CHILD_SESSION=1` — nested sessions are otherwise excluded from the
   `claude agents` list (<https://code.claude.com/docs/en/env-vars>). Awareness note: the prompt
   travels in the process argument list, so it is briefly visible to other local processes
   (`ps`) — inherent to `claude --bg "<prompt>"`. The mandatory redaction pass has already
   scrubbed the prompt by this point; this exposure is one more reason secrets never belong in
   save-point output on ANY path.
3. Report the launch result: the command's output, the agent name, the `claude agents`
   management hint, and any launched-session behavior the resumed work depends on (next
   section). Verify the agent actually appeared — a zero-exit launch can still be invisible if
   the persistence override is ever unrecognized — by listing sessions non-interactively this
   turn when the CLI offers a way, and otherwise telling the user explicitly: "confirm it
   appears in `claude agents`". The `/clear`-then-paste instruction is replaced by this report —
   the user no longer needs to paste anything.
4. **Launch failure → fall back, never block.** Non-zero exit (e.g. the installed Claude Code
   predates `--bg`) → report the error and fall back to the standard `/clear`-then-paste
   instruction. The save-point already exists; nothing is lost.
5. **STOP.** The background agent is the continuation; this session terminates the task. Do not
   monitor, poll, or babysit the launched agent, and do not start new work items.

## What the launched session inherits (and what it does not)

The launched agent is a NEW session, not a fork of this one
(<https://code.claude.com/docs/en/agent-view>):

- **CLI configuration is NOT inherited.** It carries none of the current session's CLI flags
  (e.g. `--mcp-config`, `--settings`, `--add-dir`, `--plugin-dir`) — mirror onto the launch
  command any such flags the resumed work depends on, and say so in the launch report.
- **Model and effort are NOT inherited** from the current session's in-conversation choices.
  They resolve from the launch command's own `--model` / `--effort` flags and, absent those,
  from the settings of the directory it starts in (project/user settings, including `env`
  values such as `ANTHROPIC_MODEL`). When the resumed work depends on a specific model or
  effort, pass the flags explicitly and note them in the launch report.
- **Directory settings ARE read normally** — the session reads its settings from the directory
  it runs in, the same as a fresh `claude` started there.

## Post-launch enforcement checklist

Tick each item in the response so the user can verify the exit shape (in addition to the engine
doc's save-point items, which the sibling `handoff` skill's checklists mirror):

- [ ] Explicit user intent for background delegation verified (hard gate) — absent intent →
  save-point + `/clear`-then-paste exit, no launch, reason stated
- [ ] Dirty-tree gate evaluated (`git status --porcelain -uall` this turn, ignoring save-point
  files under the handoff location); other uncommitted changes without the linked-worktree
  exception → no launch, reason reported, fallback to `/clear`-then-paste
- [ ] Background agent launched with the rails prompt (`claude --bg --name …`) and the launch
  result reported (including any non-inherited flags mirrored or worth flagging) — OR the
  non-zero exit reported with fallback to `/clear`-then-paste
- [ ] **EXECUTION STOPS HERE** — no monitoring, no babysitting, no new work items

## Gotchas

Failure patterns are documented inline at the step that owns them: the `-uall` untracked-directory
collapse (dirty-tree gate, step 1), the no-inline-prompt rule and the session-persistence env
requirement (launch command, step 2), slug sanitization ("Arguments"), and non-inheritance
surprises — model, effort, CLI flags ("What the launched session inherits").

## What this skill does NOT do

- **Does not launch without explicit user intent** — the hard gate above; the fallback exit is
  the sibling `handoff` skill's `/clear`-then-paste shape
- **Does not commit** — save-points are durable task state, not source code; the dirty-tree gate
  reports other uncommitted work rather than committing or stashing it
- **Does not monitor the launched agent** — the user manages it with `claude agents`
- **Does not continue executing the underlying task in this session** — the background agent is
  the continuation
- **Does not restate the save-point engine** — production lives in the shared engine doc
