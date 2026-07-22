---
name: find-handoff
description: "Recover a lost handoff after `/clear` — find the save-point file or resume prompt when the resume prompt was written but never copied and the fresh session has zero context. Read-only detection ladder: known-location glob of `<memory_dir>/handoffs/`, then a bounded, recency-ranked scan of transcripts (excluding the current session's own file) for the handoff directive and dashed-rail markers, then a confirm-before-resume gate. Use when: 'find my handoff', 'recover the handoff', 'I lost the resume prompt', 'forgot to copy the resume prompt', 'I cleared without saving the prompt', 'where's my handoff', 'recover after /clear', 'get back the handoff'. Surfaces only the resume prompt + handoff metadata, never raw transcript content; hands to `/session-flow:keep-going` when the recovered session ended mid-work rather than at a clean save-point."
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Claude session: !`echo "${CLAUDE_CODE_SESSION_ID:-unknown}" || echo "unknown"`
Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Default-location handoffs (this repo): !`ls -1t .work/handoffs/*-handoff-*.md 2>/dev/null | head -5 || echo "none at default .work/handoffs/"`
Transcript project dirs (recent): !`ls -1dt "${HOME}/.claude/projects/"*/ 2>/dev/null | head -8 || echo "none"`

# Find handoff

## Purpose

Recover a handoff whose **resume prompt was never copied.** The canonical failure: a session
writes a save-point via `/session-flow:handoff`, the operator runs `/clear`, but forgets to copy
the dashed-rail resume prompt — so the fresh session starts with zero context and no path to the
handoff on disk. This skill runs a **read-only** detection ladder that finds the lost handoff (file
or prompt-only), confirms it with the operator, then routes to the normal resume path.

It exists because ad-hoc recovery is filesystem-plus-transcript archaeology that is easy to get
wrong: `/clear` keeps the same project directory but opens a **new** transcript file, so the
pre-clear content sits in a sibling — never in the current session's own file.

## The detection contract this keys off

`/session-flow:handoff`'s output shape is a **stable detection contract** (documented in
[`${CLAUDE_PLUGIN_ROOT}/reference/save-point.md`](${CLAUDE_PLUGIN_ROOT}/reference/save-point.md)
"Detection contract"). This skill depends on three signals, in precision order:

1. **The file directive** — `Read @<path>/handoffs/<TS>-handoff-<topic>.md …`. It embeds the exact
   path to recover and survives verbatim into transcript JSONL, so it is the highest-precision key
   for a **file-based** handoff.
2. **The dashed rails + instruction line** — the two `─` (U+2500) rails and the literal
   `` `/clear`, then copy everything between the dashed lines `` line. For a **prompt-only** handoff
   there is no file and no directive; the resume content is inline between the rails, and the
   transcript is the only record — so this is the primary key for that branch.
3. **`Prior session: <UUID>`** and the `type: handoff` frontmatter (structure doc) — corroborating
   signal that pins the session chain.

## The recovery ladder — read-only throughout

1. **Known-location glob first (no transcript needed).** Resolve `<memory_dir>/handoffs/` for the
   **current repo** through the plugin binding
   ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md))
   — never assume the literal `.work`; the memory root is consumer-configurable — plus the
   no-project-root fallback `${CLAUDE_PLUGIN_DATA}/topic-docs/handoffs/`. Glob `*-handoff-*.md`,
   keep only files whose frontmatter is `type: handoff`, rank by mtime. A strong, recent candidate
   → jump to step 4. **v1 scope: current repo only.** The cross-repo *filesystem* sweep (deriving
   other repo roots from transcript `cwd` fields) is deferred — step 2's transcript scan already
   recovers handoffs written in other repos, since transcripts are indexed by session, not repo.
2. **Transcript scan — bounded, recency-ranked, cross-repo.** Enumerate `~/.claude/projects/*/`
   project dirs (the lost session may have run in a **different** repo, so scan all of them, not
   only the current project's dir), rank `.jsonl` by mtime, and take the top handful. **Bound the
   scan** — a full recursive grep over every transcript is slow enough to time out; an mtime-sorted
   candidate list is mandatory, not optional. **Exclude the current session's own transcript**
   (`$CLAUDE_CODE_SESSION_ID`, pre-computed above): `/clear` opened a new file in the same project
   dir, so the pre-clear content is a sibling, never this file.
3. **Marker detection over candidate tails (grep, read-only).** Scan the tail of each candidate for
   the contract signals above:
   - **File mode** — match the `Read @…/handoffs/<TS>-handoff-<topic>.md` directive. **Filter out
     the template placeholder:** a match containing angle-bracket tokens (`<handoffs-dir>`, `<TS>`,
     `<topic>`) is the `save-point.md` doc being read into some session's context — not a real
     handoff. Keep only concrete paths. Confirm the referenced file exists on disk.
   - **Prompt-only mode** — no file, no directive. Detect off the `─` rails, the instruction line,
     and `Prior session:`; the resume content is the block inline between the rails.
   - **Un-escape before surfacing.** Each transcript message is ONE physical JSONL line with its
     text JSON-string-escaped (`\n` for newlines, `\"` for quotes, `\\` for backslashes). A raw grep
     hit is that escaped blob — decode it back to plain text (JSON-unescape the matched string)
     before surfacing, or the user sees a wall of `\n`/`\"` instead of the prompt. This matters most
     in prompt-only mode, where the whole inline block is what gets surfaced.
   - mtime alone can never pick the winner (multiple sessions land within seconds of each other) —
     the markers do.
4. **Confirm before resuming — hard gate.** Surface the found handoff's **metadata only**: topic,
   date, and the `session_id` chain (file mode) or the inline resume prompt (prompt-only mode). Ask
   for an explicit yes/no and **stop**. Do not read the file's body, `/clear`, or execute the
   resume prompt before the operator confirms. Resuming the **wrong** handoff is worse than
   recovering none.
5. **Chain validation (file mode).** Check the file's `session_id` / `previous_handoff` /
   `previous_session_id` frontmatter against the transcript the directive was found in. On a
   mismatch, flag it and let the operator decide — never silently splice an unrelated session into
   the chain.
6. **Hand off to the resume path.** On confirmation:
   - **Clean save-point** → read the handoff file and continue per its "Open questions / next
     steps" (the normal `/session-flow:handoff` resume path). For a prompt-only recovery, continue
     from the inline prompt.
   - **Ended mid-work** (the recovered state shows interrupted, in-flight work rather than a
     deliberate save-point) → hand to `/session-flow:keep-going`, which recovers and continues
     interrupted work.

## Read-only + redaction — hard invariants

- **Read-only.** No writes, no `/clear`, no resume execution before the confirm gate. This skill
  finds and surfaces; it never mutates state.
- **Redaction-aware.** Transcripts and handoff files can contain secrets. Quote **only** the resume
  prompt and the handoff metadata — **never** dump raw transcript content. Apply the same
  shape-marker redaction the producer uses (`save-point.md` "Redaction pass"): replace any
  secret / token / credential / connection string / PII with a shape marker (`<REDACTED: API key>`),
  never the value. A value acceptable in-session is not acceptable to re-surface from a transcript.

## Boundaries — pick the right sibling

- **`/session-flow:handoff`** — the producer. Writes the save-point + resume prompt this skill
  recovers. find-handoff writes nothing.
- **`/session-flow:keep-going`** — recovers and continues **off-thread / interrupted** work. When
  the lost session ended mid-work, this skill hands there. keep-going covers the case where the
  handoff path is *known* but work was interrupted; find-handoff covers the disjoint case where the
  path itself is lost.
- **`/session-flow:orient`** — reads durable state (including handoffs) whose location is already
  known, for a where-we-stand briefing. find-handoff is the recovery step for when that location is
  unknown.

## What this skill does NOT do

- **Writes nothing** — no files, no memory, no `/clear`, no resume execution before the confirm
  gate.
- **Does not dump raw transcript content** — surfaces only the resume prompt + metadata, redacted.
- **Does not auto-resume** — the confirm-before-resume gate is mandatory; wrong-handoff resumption
  is worse than none.
- **Does not scan unbounded** — the transcript scan is mtime-sorted and capped; it never grep-walks
  every transcript on the machine.
- **Does not diagnose the interruption** or recover off-thread work — that is
  `/session-flow:keep-going`.

## Gotchas

- **`/clear` writes a NEW transcript file** in the **same** project directory. The pre-clear
  content is in a sibling `.jsonl`; searching only the current session's file finds nothing. Always
  exclude the current `$CLAUDE_CODE_SESSION_ID` and scan siblings.
- **The template placeholder is a false positive.** `Read @<handoffs-dir>/<TS>-handoff-<topic>.md`
  appears verbatim in any transcript that read `save-point.md` into context. Discard matches
  containing `<`-angle-bracket tokens; keep only concrete resolved paths.
- **Near-identical mtimes.** Multiple sessions can write within seconds; mtime cannot rank them.
  The directive / rails / `Prior session:` markers break the tie, not the timestamp.
- **Handoff files live in gitignored dirs far from `$HOME`**, and `memory_dir` is
  consumer-configurable — so the filesystem glob can miss them. Transcripts are the reliable index:
  they record the exact path (file mode) or the whole prompt (prompt-only), regardless of where the
  file lived.
- **Prompt-only handoffs have no file at all.** Do not error on a missing file — the resume content
  is inline between the rails in the transcript, and that is the recovery.
