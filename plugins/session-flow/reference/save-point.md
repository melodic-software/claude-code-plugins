# Save-point engine — produce the save-point and the resume prompt

Shared by `/session-flow:handoff` and `/session-flow:continue-in-background`. This document owns
the delivery-agnostic machinery: locating the position, choosing the path, producing the (redacted)
save-point, and emitting the rails resume prompt. The citing skill owns everything after the rails
prompt — its delivery step (`/clear`-then-paste, or a background-agent launch) and its own STOP
semantics. Neither skill restates this content; both walk it in order.

## Where save-points live

Save-points are memory-tier, concern-scoped by session — resolve the destination through
the plugin binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).
A consumer-declared `memory_dir` (the `.claude/topic-docs.yaml` concern file, or a working-docs
convention in `CLAUDE.md` / `.claude/rules/`) wins as the memory-tier ROOT; save-points always live
at **`<memory_dir>/handoffs/`** (default `.work/handoffs/`) — files named `<TS>-handoff-<topic>.md`
with `TS = date -u +%Y%m%dT%H%M%SZ` (ISO basic, Windows-safe, sortable). On the session's first
memory-tier write, verify the resolved memory root's `.gitignore` exists and contains `*` — create
it (announced) when absent; never edit the consumer's root `.gitignore`.

## Locate the position first

Before emitting anything, establish where the work stands: if a plan or checklist artifact backs
the work (see the sibling `workflow` skill), read it THIS turn and name the next unfinished stage —
the resume prompt points at the next stage, not just "continue here". Ground every status claim in
a fresh read, never a prior session's assertion. With no plan artifact, name the next concrete
action from the conversation.

## Choosing the path: full save-point vs prompt-only

**A resume prompt is ALWAYS emitted.** The only decision is whether to ALSO write a durable handoff
file. Full save-point = prompt + file (prompt `@`-references the file); prompt-only = the same
prompt carrying its detail inline, no file.

**Default: write the file.** Skip it only when NO plan artifact backs the work AND all of these
clearly hold:

- Remaining follow-ups fit as a short bullet list in the prompt
- The work is straightforward, not exploratory
- No "tried and ruled out" dead-ends worth preserving
- No load-bearing decision + rationale a future session must not rediscover
- No non-trivial task list to reconstitute

ANY doubt → full save-point. A wrongly-skipped file loses state the fresh session must rediscover;
a wrongly-written one costs nothing. An explicit method argument overrides auto-detect — but note
`prompt` leaves a gap in the session-id chain that `/retro` walks (no file, no chain pointer).

## Redaction pass — mandatory on BOTH paths

Before writing the handoff file or emitting the resume prompt, sweep everything outbound — body
sections, TaskList snapshot, frontmatter, and the prompt between the rails — for secrets, API keys,
tokens, credentials, connection strings, and PII, and redact each hit with a shape marker
(`<REDACTED: API key>`), never the value. Save-point output outlives the session: it sits on disk
uncommitted-but-readable, travels to other sessions and machines, and gets read in contexts the
current conversation never anticipated. A value acceptable to see in-session is not acceptable to
persist. This pass gates the write — no artifact or prompt is emitted before it runs.

## Writing the handoff file (full path)

The document structure (eight body sections — Task / Progress / Decisions made / Files modified /
Tried and ruled out / Open questions / Suggested skills / Files to review), the TaskList snapshot +
reconstitute format, and the frontmatter shape (including the `session_id` / `previous_handoff` /
`previous_session_id` chain fields that `/retro` walks) live in
[`${CLAUDE_PLUGIN_ROOT}/reference/structure.md`](${CLAUDE_PLUGIN_ROOT}/reference/structure.md)
— walk it while writing the file.

When the target file already exists on disk (extending an earlier turn's write), re-read it from
disk immediately before writing and append to it — never rewrite the whole file from the in-context
copy, which goes stale the moment disk moved on without this conversation seeing it.

## Emit the copy/paste resume prompt

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

After the rails prompt is emitted, control returns to the citing skill's delivery step.

## Detection contract — consumed by `/session-flow:find-handoff`

The output shape above is a **stable detection contract**, not merely a display convention:
`/session-flow:find-handoff` keys off it to recover a handoff whose resume prompt was written but
never copied (operator ran `/clear` before copying it). The load-bearing signals, in precision
order, are (1) the `Read @…-handoff-*.md` directive — the exact path to recover, for a file-based
handoff; (2) the two `─` (U+2500) rails plus the `` `/clear`, then copy everything between the
dashed lines `` instruction line — the primary key for a prompt-only handoff, which writes no file;
and (3) the `Prior session: <UUID>` line, which — together with the `type: handoff` frontmatter
([`structure.md`](structure.md)) — pins the session chain. Changing this prompt/marker format is a
**knowing** break of that contract, not a cosmetic edit; update `find-handoff`'s detection in the
same change.
