---
name: handoff
description: "Write a mid-session save-point for /clear-and-resume — a durable handoff file (default) or a copy-paste resume prompt when follow-ups are small. Pass --bg to hand the resume prompt to a fresh background agent instead of pasting it yourself. Use when: 'handoff', 'save state', 'checkpoint this', 'pause', 'come back later', 'continue in the background', context is heavy, or quality is degrading."
argument-hint: "[file|prompt] [topic] [--bg] (e.g., /handoff, /handoff prompt, /handoff file phase-3, /handoff --bg)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Claude session: !`echo "${CLAUDE_CODE_SESSION_ID:-unknown}"`
Uncommitted changes: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`

## Purpose

Context bloat is expensive and quality degrades as context rots. When a task has room left but
context is heavy, capture a save-point — a handoff document, or just a copy-paste resume prompt when
follow-ups are small — and `/clear`.

Based on the canonical pattern Anthropic recommends for the `/clear` workflow: put the rest of the
plan in a handoff file; explain what you tried, what worked, and what didn't, so the next agent with
fresh context can load that file and nothing else. The save-point captures a *snapshot* of in-flight
state — including what was tried and ruled out — so the next session doesn't waste effort
rediscovering dead ends.

## Where handoffs live

Handoffs are memory-tier save-points, concern-scoped by session — resolve the destination through
the plugin binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).
A consumer-declared `memory_dir` (the `.claude/topic-docs.yaml` concern file, or a working-docs
convention in `CLAUDE.md` / `.claude/rules/`) wins as the memory-tier ROOT; handoffs always live at
**`<memory_dir>/handoffs/`** (default `.work/handoffs/`) — files named `<TS>-handoff-<topic>.md`
with `TS = date -u +%Y%m%dT%H%M%SZ` (ISO basic, Windows-safe, sortable). On the session's first
memory-tier write, verify the resolved memory root's `.gitignore` exists and contains `*` — create
it (announced) when absent; never edit the consumer's root `.gitignore`.

## Arguments

`$ARGUMENTS` carries `[file|prompt] [topic] [--bg]` — all optional; method and topic positional:

- **Method** (`file` | `prompt`) — recognized ONLY as the first token. `file` forces the full
  durable handoff; `prompt` forces prompt-only. Omitted → auto-detect (see "Choosing the path").
- **Topic** — short kebab slug for the filename. When the first token is not a method keyword it IS
  the topic (`/handoff phase-3`); with a method present it is the second token. Omitted → inferred
  from context.
- **`--bg`** — flag, recognized anywhere in the argument string; strip it before reading the
  positionals. After the save-point is produced, launch a fresh background agent seeded with the
  resume prompt instead of relying on the user to `/clear`-and-paste. See "Background-agent launch
  (`--bg`)".

## Hard rule — handoff ALWAYS terminates current execution

**The whole point of `/handoff` is `/clear` + fresh-session resume.** The skill produces the
save-point, THEN STOPS. It does NOT keep executing the underlying task in the current session; that
defeats the purpose. STOP is the default and near-universal outcome — NEVER unlocked by the user
having listed multiple steps, nor by the remaining work being "small".

**Mandatory STOP gate (walk every box):**

- [ ] Path chosen (full vs prompt-only) per "Choosing the path"
- [ ] Copy/paste resume prompt emitted between two dashed rails (see "Final step")
- [ ] `/clear`-then-paste instruction surfaced to the user — with `--bg`, replaced by the launch
  report per "Background-agent launch (`--bg`)"
- [ ] **STOP.** No further work items, no next phase, no follow-on skill, no commit/push. The
  session ends as far as the task is concerned — `--bg` does not relax this: the background agent
  is the continuation, and this session neither monitors nor babysits it

**NOT authorization to continue (these all STOP):**

- A multi-step pipeline naming `/handoff` (e.g. "handoff, then verify, then PR") → the listed steps
  run in the FRESH session AFTER `/clear`. Naming `/handoff` names a `/clear` boundary, not a waiver
- "do all of it" → authorizes executing the phases across the session chain, but each `/handoff`
  between them still enforces its `/clear` boundary (that is WHY the handoffs get written)
- A standalone user-invoked `/handoff` → always STOP, regardless of surrounding instructions

The only exception: the user's prior turn used explicit stay-in-session language about handoffs
specifically (e.g. "don't `/clear` between phases, keep going").

## When to invoke

- Mid-task, context heavy (check `/context` output or user report)
- Quality degrading (context rot) — responses drifting, repeating, or looping
- About to pause for hours/overnight; want a clean resume
- Going AFK but the work should keep moving — pass `--bg` so a background agent resumes it
- About to switch to a different task; this one isn't done
- Last turn had an unexpected compaction
- Sharing state with another session or machine

## Fork beats compaction when the window is deep

Two ways to keep going past a heavy context: fork (handoff file + `/clear` + fresh session) or
continue in place over a compacted history. Compaction suits an intentional break between phases
while the window is still mostly fresh — the summarized turns were genuinely disposable. Once the
session has consumed enough of its context window that reasoning quality degrades — roughly beyond
the final third of the window — fork instead: a handoff file carries forward exactly the state that
matters, chosen deliberately, while a compaction summary carries forward whatever the summarizer
happened to keep, and the degradation that prompted the move rides along into the continued
session. Judge the threshold by window position and response quality, never by a fixed token count
— it shifts with model and configuration.

## Locate the position first

Before emitting anything, establish where the work stands: if a plan or checklist artifact backs
the work (see the sibling `workflow` skill), read it THIS turn and name the next unfinished stage —
the resume prompt points at the next stage, not just "continue here". Ground every status claim in
a fresh read, never a prior session's assertion. With no plan artifact, name the next concrete
action from the conversation.

## Choosing the path: full handoff vs prompt-only

**A resume prompt is ALWAYS emitted.** The only decision is whether to ALSO write a durable handoff
file. Full handoff = prompt + file (prompt `@`-references the file); prompt-only = the same prompt
carrying its detail inline, no file.

**Default: write the file.** Skip it only when NO plan artifact backs the work AND all of these
clearly hold:

- Remaining follow-ups fit as a short bullet list in the prompt
- The work is straightforward, not exploratory
- No "tried and ruled out" dead-ends worth preserving
- No load-bearing decision + rationale a future session must not rediscover
- No non-trivial task list to reconstitute

ANY doubt → full handoff. A wrongly-skipped file loses state the fresh session must rediscover; a
wrongly-written one costs nothing. The explicit method argument overrides auto-detect — but note
`prompt` leaves a gap in the session-id chain that `/retro` walks (no file, no chain pointer).

## Redaction pass — mandatory on BOTH paths

Before writing the handoff file or emitting the resume prompt, sweep everything outbound — body
sections, TaskList snapshot, frontmatter, and the prompt between the rails — for secrets, API keys,
tokens, credentials, connection strings, and PII, and redact each hit with a shape marker
(`<REDACTED: API key>`), never the value. Handoff output outlives the session: it sits on disk
uncommitted-but-readable, travels to other sessions and machines, and gets read in contexts the
current conversation never anticipated. A value acceptable to see in-session is not acceptable to
persist. This pass gates the write — no artifact or prompt is emitted before it runs.

## Writing the handoff (full path)

The document structure (eight body sections — Task / Progress / Decisions made / Files modified /
Tried and ruled out / Open questions / Suggested skills / Files to review), the TaskList snapshot +
reconstitute format, and the frontmatter shape (including the `session_id` / `previous_handoff` /
`previous_session_id` chain fields that `/retro` walks) live in `context/structure.md` — walk it
while writing the file.

When the target file already exists on disk (extending an earlier turn's write), re-read it from
disk immediately before writing and append to it — never rewrite the whole file from the in-context
copy, which goes stale the moment disk moved on without this conversation seeing it.

## Final step: emit the copy/paste resume prompt

**Copy-region clarity (both paths) — two dashed rails, no fence:**

- The prompt sits between two full-width `─` (U+2500) rails — top rail, prompt, bottom rail. Use
  literal `─`, NOT markdown `---` (turns the adjacent line into a heading) and NOT a code fence
  (the user copies the text between the rails, not fence markers).
- The ONLY thing between the rails is the prompt — no labels, no padding lines. Commentary sits
  above the top rail or below the bottom rail, never between.
- One plain-language instruction sits directly ABOVE the top rail: "`/clear`, then copy everything
  between the dashed lines."
- **Goal-aware re-arm:** if a `/goal` is active this session (infer from conversation), the FIRST
  line between the rails starts with literal `/goal` — `/clear` destroys an active goal, so the
  pasted block must re-arm it. When unsure, omit it and note below the bottom rail: "if a goal was
  active, prepend `/goal <condition>`."

Full-path shape (minimum form — live: bare `─` rails, no fence; shown inside a fence here for
display):

```text
`/clear`, then copy everything between the dashed lines:

──────────────────────────────────────────────────────────
Read @<handoffs-dir>/<TS>-handoff-<topic>.md and continue per its "Open questions / next steps".
Prior session: <UUID>.
──────────────────────────────────────────────────────────
```

`<handoffs-dir>` is the path the write step actually used — the resolved
`<memory_dir>/handoffs/` (default `.work/handoffs/`). Never emit a
default the file was not written to.

When the next stage is a specific skill in the consuming repo, swap the directive to
`Read @… and execute /<skill>.` The `@`-reference is mandatory on the full path — the fresh session
loads it; do NOT inline the file's detail in the prompt. Prompt-only carries its remaining-work
bullets inline between the rails instead.

`<UUID>` = this session's `$CLAUDE_CODE_SESSION_ID` (the frontmatter `session_id`) — it lets a
fresh session or `/retro` chain-walker locate the transcript later.

## Background-agent launch (`--bg`)

Honored ONLY when the user explicitly passed `--bg` — never self-elected, including when this
skill is model-invoked. Composes with BOTH paths: the launched agent receives exactly the resume
prompt that sits between the rails (full path: it follows the prompt's Read directive to the
handoff file; prompt-only: the remaining-work bullets travel inline).

Sequence — the rails prompt from "Final step" is still emitted FIRST (transparency + manual
fallback), then:

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
   re-run `/handoff --bg`. Exception: launch anyway when the current session already runs inside
   a linked git worktree — isolation is skipped there per the same page.
2. Launch from the consuming project's root, passing the rails prompt verbatim as one argument.
   `<topic>` = the resolved topic slug (argument or inferred); when none resolves, use `resume`:

   ```bash
   cd "${CLAUDE_PROJECT_DIR}" && CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1 claude --bg --name "handoff-<topic>" "$(cat <<'HANDOFF_RESUME_PROMPT_END'
   <resume prompt exactly as emitted between the rails>
   HANDOFF_RESUME_PROMPT_END
   )"
   ```

   `claude --bg` starts the session as a background agent and returns immediately; the user
   manages it with `claude agents`. The launched agent is a NEW session: it inherits none of the
   current session's CLI configuration (e.g. `--mcp-config`, `--settings`, `--add-dir`,
   `--plugin-dir`) — mirror onto the launch command any such flags the resumed work depends on,
   and say so in the launch report. `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` is required
   because this launch runs from a Bash-tool subprocess, which carries
   `CLAUDE_CODE_CHILD_SESSION=1` — nested sessions are otherwise excluded from the
   `claude agents` list (<https://code.claude.com/docs/en/env-vars>). The heredoc sentinel is
   deliberately unique — a bare `EOF` line inside a freeform resume prompt would terminate a
   plain `<<'EOF'` heredoc early and silently truncate the prompt. Awareness note: the prompt
   travels in the process argument list, so it is briefly visible to other local processes
   (`ps`) — inherent to `claude --bg "<prompt>"`. The mandatory redaction pass has already
   scrubbed the prompt by this point; this exposure is one more reason secrets never belong in
   handoff output on ANY path.

3. Report the launch result: the command's output, the agent name, and the `claude agents`
   management hint. Swap the `/clear`-then-paste instruction for this report — the user no longer
   needs to paste anything.
4. **Launch failure → fall back, never block.** Non-zero exit (e.g. the installed Claude Code
   predates `--bg`) → report the error and fall back to the standard `/clear`-then-paste
   instruction. The save-point already exists; nothing is lost.
5. **STOP is unchanged.** The background agent is the continuation; this session still terminates
   the task per the hard rule. Do not monitor, poll, or babysit the launched agent.

## Post-write enforcement checklist

Tick each item in the response so the user can verify the exit shape. Missing any tick = handoff
incomplete. Known failure patterns live in `context/gotchas.md` — load on demand when a step feels
ambiguous.

**Full path:**

- [ ] Position located + next stage named (fresh reads this turn)
- [ ] Handoff file written to the handoff location (self-ignore guard verified first) with
  frontmatter per `context/structure.md`
- [ ] `previous_handoff` + `previous_session_id` present IF this session continued a prior
  handoff's task (chain continuity per `context/structure.md`); omitted otherwise — including when
  the directory holds only unrelated-task handoffs
- [ ] All eight body sections present
- [ ] Redaction pass swept the file AND the prompt (secrets/tokens/credentials/PII replaced with
  shape markers)
- [ ] TaskList snapshot + Reconstitute sections present (OR explicit "exception: 0 active tasks")
- [ ] Resume prompt emitted between dashed rails, `@`-referencing the file; copy instruction above
  the top rail; `/goal` first line if a goal is active
- [ ] **EXECUTION STOPS HERE**

**Prompt-only path:**

- [ ] Prompt-only justified (all auto-detect criteria hold, OR `prompt` explicitly passed)
- [ ] Redaction pass swept the prompt (secrets/tokens/credentials/PII replaced with shape markers)
- [ ] Self-contained resume prompt between dashed rails — remaining-work bullets inline
- [ ] Copy instruction above the rails; `/goal` first line if a goal is active
- [ ] **EXECUTION STOPS HERE** — "small enough" means the prompt captures the work, NOT "small
  enough to skip `/clear` and finish in-session"

**Either path with `--bg` (additional):**

- [ ] Dirty-tree gate evaluated (`git status --porcelain -uall` this turn, ignoring save-point
  files under the handoff location); other uncommitted changes without the linked-worktree
  exception → no launch, reason reported, fallback to `/clear`-then-paste
- [ ] Background agent launched with the rails prompt (`claude --bg --name …`) and the launch
  result reported — OR the non-zero exit reported with fallback to `/clear`-then-paste

## What this skill does NOT do

- **Does not commit** — handoff docs are durable task state, not source code. Commit ready code
  changes separately; describe uncommitted work in "Progress"
- **Does not invoke `/clear`** — the user types `/clear`. The skill produces the save-point, emits
  the resume prompt, and stops
- **Does not launch a background agent unprompted** — the `--bg` launch happens only when the user
  passed the flag; the default exit is always the copy/paste prompt
- **Does not continue executing the underlying task** — per the hard rule above. Prompt-only does
  NOT relax this
- **Does not replace a contract or plan** — it captures in-flight state at any point
- **Does not summarize the whole conversation** — task-relevant state only
