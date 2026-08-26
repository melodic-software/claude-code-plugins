---
description: "Recover a lost handoff after `/clear`. Find the save-point file or resume prompt when the resume prompt was written but never copied and the fresh session has zero context. Read-only detection ladder: known-location glob of `<memory_dir>/handoffs/`, then a bounded, recency-ranked scan of transcripts (excluding the current session's own file) for the handoff directive and dashed-rail markers, then a confirm-before-resume gate. Use when: 'find my handoff', 'recover the handoff', 'I lost the resume prompt', 'forgot to copy the resume prompt', 'I cleared without saving the prompt', 'where's my handoff', 'recover after /clear', 'get back the handoff'. Surfaces only the resume prompt + handoff metadata, never raw transcript content; hands to `/session-flow:keep-going` when the recovered session ended mid-work rather than at a clean save-point."
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: session
  summary: Recover a lost handoff or resume prompt after /clear
---

## Pre-computed context

Default-location handoffs (this repo): !`ls -1t .work/handoffs/*-handoff-*.md 2>/dev/null | head -5 || echo "none at default .work/handoffs/"`
Transcript project dirs (recent): !`ls -1dt "$HOME/.claude/projects/"*/ 2>/dev/null | head -8 || echo "none"`

## Context. Gather first

Take `session-id` and `branch` only. This skill's detection ladder reads the filesystem, not git
state. Probe commands, the one-command-per-call and treat-failure-as-unknown rules, and the
`$`-expansion rationale, including that bare `$HOME` is the one form observed to survive the
worktree-isolation guard while `${HOME}` is refused:
[`${CLAUDE_PLUGIN_ROOT}/reference/gather.md`](${CLAUDE_PLUGIN_ROOT}/reference/gather.md).

# Find handoff

## Purpose

Recover a handoff whose **resume prompt was never copied.** The canonical failure: a session
writes a save-point via `/session-flow:handoff`, the operator runs `/clear`, but forgets to copy
the dashed-rail resume prompt, so the fresh session starts with zero context and no path to the
handoff on disk. This skill runs a **read-only** detection ladder that finds the lost handoff (file
or prompt-only), confirms it with the operator, then routes to the normal resume path.

It exists because ad-hoc recovery is filesystem-plus-transcript archaeology that is easy to get
wrong: `/clear` keeps the same project directory but opens a **new** transcript file, so the
pre-clear content sits in a sibling, never in the current session's own file.

## The detection contract this keys off

`/session-flow:handoff`'s output shape is a **stable detection contract** (documented in
[`${CLAUDE_PLUGIN_ROOT}/reference/save-point.md`](${CLAUDE_PLUGIN_ROOT}/reference/save-point.md)
"Detection contract"). This skill depends on three DETECTION signals, in precision order, plus one
resolution input, `Handoff origin:`, described after them:

1. **The file directive**. `Read @<path>/handoffs/<TS>-handoff-<topic>.md …`. It embeds the exact
   path to recover and survives verbatim into transcript JSONL, so it is the highest-precision key
   for a **file-based** handoff. **Two path forms qualify.** The producer now emits an absolute
   path; every handoff written before that rule shipped states a repo-relative one, and those
   transcripts are on disk unchanged. Match the directive on its `…handoffs/<TS>-handoff-…` shape,
   which both forms share, and let them diverge only at the existence check (step 3).
2. **The dashed rails + instruction line**, the two `─` (U+2500) rails and the literal
   `` `/clear`, then copy everything between the dashed lines `` line. For a **prompt-only** handoff
   there is no file and no directive; the resume content is inline between the rails, and the
   transcript is the only record, so this is the primary key for that branch.
3. **`Prior session: <UUID>`** and the `type: handoff` frontmatter (structure doc), corroborating
   signal that pins the session chain. Corroboration only: the file-mode shape emits the
   `Prior session:` line, but the producer's prompt-only checklist does not require it, so its
   absence never disqualifies a prompt-only candidate.

**`Handoff origin:` is a resolution input, not a detection signal.** It cannot admit or reject a
candidate, a block is already qualified by the three signals above before it is read, so it is
deliberately outside that numbered list, and outside the conditional-signal slot the `/loop` re-arm
note holds below. What the ladder depends on it for is step 3's existence check: it names the
repository and repo-relative path that let a ROOTED directive survive a machine or checkout change,
which is the one failure an absolute path has that a relative one does not. It is emitted by the
file-mode shape only and only since the producer rooted its path, so its absence disqualifies
nothing. Prompt-only never emits it, and no handoff older than the rooted directive has one.

**The resume prompt this skill recovers is the rails block PLUS every below-rail `/loop` re-arm
message** (save-point.md "Detection contract"). Everything else the producer arms lives between the
rails and is recovered with the block. `/goal` included. The `/loop` re-arm cannot: a command is
recognized only at a message's start, so the producer emits it as a separate follow-up message and
places its instruction below the bottom rail. Recovering only the copy region would therefore hand
back a continuation that runs once and silently drops the loop, the same failure the producer's
re-arm rule exists to prevent. The note is a fourth, **conditional** signal: present only when the
lost session was running under `/loop`, so its absence disqualifies nothing, and a **repeatable**
one, since the producer emits a separate re-arm message per surviving loop, so "found one" is never
"found them all".

## The recovery ladder. Read-only throughout

1. **Known-location glob first (no transcript needed).** Resolve `<memory_dir>/handoffs/` for the
   **current repo** through the plugin binding
   ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)),
   never the literal `.work`. Read
   [reference/rung-1-known-location.md](reference/rung-1-known-location.md) before globbing: it owns
   the fallback-root rule and when it applies, the `type: handoff` frontmatter filter, the mtime
   ranking, the short-circuit bar and where a short-circuit jumps to, and the repo-correlation check
   that stops a merely recent candidate from being presented as this work's. A strong, recent
   candidate ends the ladder here.

2. **Transcript scan. Bounded, recency-ranked, cross-repo.** Enumerate `~/.claude/projects/*/`
   project dirs (the lost session may have run in a **different** repo, so scan all of them, not
   only the current project's dir), rank `.jsonl` by mtime, and take the top handful. **Bound the
   scan**, a full recursive grep over every transcript is slow enough to time out; an mtime-sorted
   candidate list is mandatory, not optional. **Exclude the current session's own transcript**
   (the session id gathered above): `/clear` opened a new file in the same project
   dir, so the pre-clear content is a sibling, never this file.

3. **Marker detection over candidate tails (grep, read-only).** Read
   [reference/rung-3-marker-detection.md](reference/rung-3-marker-detection.md) before scanning any
   candidate tail: it owns the three marker forms, the two-stage assistant-text-only acceptance,
   the rails-block reconstruction, the below-rail `/loop` re-arm capture, the JSON-unescape step
   that keeps the surfaced prompt readable, and the read-only bounds on the scan. A run that
   resolved at rung 1 never needs it.

4. **Confirm before resuming. Hard gate.** Surface the found handoff's **metadata only**: the
   recovered file path (or the original `Read @…` directive as found), topic, date, and the
   `session_id` chain (file mode) or the inline resume prompt (prompt-only mode), the path is the
   thing being recovered, and the operator cannot verify the candidate without it. **Surface the
   captured `/loop` re-arm notes with it, all of them, on both modes, whenever any were found**,
   and say plainly that each re-arm is its own follow-up message sent after the continuation is
   under way. Dropping one here loses that loop just as surely as never recovering the prompt. Ask
   for an explicit yes/no and **stop**. Do not read the file's body, `/clear`, or execute the
   resume prompt before the operator confirms. Resuming the **wrong** handoff is worse than
   recovering none.

   **UNRESOLVED candidates are presented, not suppressed.** A candidate whose directive named a file
   that could not be located is surfaced alongside the resolved ones and labelled `UNRESOLVED`,
   carrying the directive verbatim, the filename, and any `Handoff origin:` line. Name the reason
   precisely rather than reporting "the file is missing"; those are different failures, and
   reporting absence for either of them is what makes this expensive to diagnose:
   - **Rootless**. The path has no root, and the transcript `cwd` it was resolved against did not
     hold it. Say which `cwd` was tried. Closing it takes one fact: the operator names the
     repository the work was in, and the relative path resolves under it.
   - **Rooted**. The path is absolute and nothing is at it on THIS machine, which is what a resume
     on a different machine or checkout looks like. Say the absolute path that was tried, and the
     repository the `Handoff origin:` line named. Closing it takes the local checkout of that
     repository.

   An UNRESOLVED candidate never auto-wins over a resolved one, and it is never the default answer
   when a resolved candidate exists.
5. **Chain validation (file mode).** Validate each frontmatter pointer against what it actually
   names:
   - `session_id` identifies the **emitting** session. Compare it with the source transcript when
     the candidate came from the transcript scan. On a glob-only recovery (step 1 jumped straight
     to step 4 with no transcript in hand), locate the producer transcript by that `session_id`,
     transcript files are named `<session_id>.jsonl` under `~/.claude/projects/*/`, and compare
     against that; when it cannot be found, say so and present the candidate as unvalidated rather
     than blocking or guessing.
   - `previous_handoff` deliberately names the **predecessor** in the chain (structure doc "Chain
     continuity"), not the emitting transcript. Validate it against the named prior handoff file,
     never against the source transcript, or a valid chained handoff looks inconsistent.
   On a mismatch, flag it and let the operator decide, never silently splice an unrelated session
   into the chain.
6. **Hand off to the resume path.** On confirmation:
   - **Clean save-point** → read the handoff file and continue its remaining next steps (the normal
     `/session-flow:handoff` resume path). For a prompt-only recovery, continue from the inline
     prompt.
   - **Ended mid-work** (the recovered state shows interrupted, in-flight work rather than a
     deliberate save-point) → hand off by invoking `/session-flow:keep-going` via the Skill tool, which recovers and continues
     interrupted work.

## Read-only + redaction. Hard invariants

- **Read-only through the confirm gate.** Detection and everything before the operator's
  confirmation writes nothing, never `/clear`s, never executes the resume. **After** confirmation,
  control passes to the selected resume path (the handoff's next steps, or
  `/session-flow:keep-going`), which acts normally, the read-only guarantee covers the recovery,
  not the resumed work.
- **Redaction-aware.** Transcripts and handoff files can contain secrets. Quote **only** the resume
  prompt, the rails block plus every below-rail `/loop` re-arm note, and the handoff metadata;
  **never** dump raw transcript content. The re-arm notes are no exception: each quotes the
  operator's original loop prompt verbatim, which can carry a token, so they go through the same pass as
  everything else rather than riding along unscanned. Apply the same
  shape-marker redaction the producer uses (`save-point.md` "Redaction pass"): replace any
  secret / token / credential / connection string / PII with a shape marker (`<REDACTED: API key>`),
  never the value. A value acceptable in-session is not acceptable to re-surface from a transcript.
- **The `Handoff origin:` value is a named credential vector, and it takes a different treatment from
  the bullet above.** It can carry a git remote URL, and a remote embeds its credential in the URL's
  userinfo component (`https://<token>@host/…`), where it reads as a path segment rather than as a
  secret. This skill surfaces that value at the confirm gate and derives a widening root from it, so
  it is checked for an `@` ahead of its host before either. **Drop the userinfo and keep the rest. Do
  NOT replace the URL with a shape marker.** The shape-marker rule above assumes the whole value is
  secret and unneeded downstream; a remote URL is the opposite. Its host and path are not secret and
  they are what makes the value useful: this line is the input that re-resolves a rooted miss, so a
  `<REDACTED: remote URL>` marker would destroy the identity recovery depends on and turn a
  credential leak into a failed recovery. So `https://<token>@github.com/<owner>/<repo>.git` is
  surfaced as `https://github.com/<owner>/<repo>.git`, never a marker; when the userinfo boundary is
  not clear (`save-point.md` `<repo-identity>` gives the test), surface the repository name alone
  rather than guessing. The producer strips it at emit time, but a recovered handoff predates that
  rule as easily as it predates the rooted path. Recovery is exactly where an unsanitized one
  arrives.

## Boundaries. Pick the right sibling

- **`/session-flow:handoff`**, the producer. Writes the save-point + resume prompt this skill
  recovers. find-handoff writes nothing during recovery.
- **`/session-flow:keep-going`**. Recovers and continues **off-thread / interrupted** work. When
  the lost session ended mid-work, this skill hands there. keep-going covers the case where the
  handoff path is *known* but work was interrupted; find-handoff covers the disjoint case where the
  path itself is lost.
- **`/session-flow:orient`**. Reads durable state (including handoffs) whose location is already
  known, for a where-we-stand briefing. find-handoff is the recovery step for when that location is
  unknown.

## What this skill does NOT do

- **Writes nothing during recovery**, no files, no memory, no `/clear`, no resume execution
  before the confirm gate. Post-confirmation work belongs to the selected resume path, not to this
  skill's recovery ladder.
- **Does not dump raw transcript content**. Surfaces only the resume prompt (rails block plus the
  below-rail `/loop` re-arm notes) + metadata, redacted.
- **Does not auto-resume**. The confirm-before-resume gate is mandatory; wrong-handoff resumption
  is worse than none.
- **Does not scan unbounded**. The transcript scan is mtime-sorted and capped; it never grep-walks
  every transcript on the machine.
- **Does not diagnose the interruption** or recover off-thread work; that is
  `/session-flow:keep-going`.

## Gotchas

- **`/clear` writes a NEW transcript file** in the **same** project directory. The pre-clear
  content is in a sibling `.jsonl`; searching only the current session's file finds nothing. Always
  exclude the current `$CLAUDE_CODE_SESSION_ID` and scan siblings.
- **The template placeholder is a false positive.** `Read @<handoffs-dir>/<TS>-handoff-<topic>.md`
  appears verbatim in any transcript that read `save-point.md` into context. Discard matches
  containing the template's placeholder tokens; keep only concrete resolved paths. The prompt-only
  template, the `─` rails plus a placeholder body and a literal `Prior session: <UUID>`, is the
  same false positive; reject a block on those specific tokens, and require a concrete session
  UUID (not the `<UUID>` placeholder) on any `Prior session:` line before surfacing. **Never
  blanket-reject angle brackets**. Valid prompts carry `<REDACTED: …>` shape markers and code
  syntax.
- **A rootless directive is the legacy form, and resolving it is inference.** The producer emits an
  absolute path now; handoffs written before that shipped state a repo-relative one, so both forms
  keep arriving. For the rootless form, read the `cwd` field of the transcript the directive was
  found in and resolve against that. Checking existence from the current session's cwd falsely
  reports a cross-repo handoff missing. But that resolution assumes the producer's cwd *was* the
  repository it wrote into, which is untrue for exactly the sessions this skill exists to rescue: a
  session working in a repo that is not cwd's project root. So a rootless miss is UNRESOLVED, not
  absent. Surface it with its directive and say the path has no root, never that the file is
  missing.
- **Markers in user messages, tool results, and tool INPUTS are not handoffs.** A pasted sample or
  an echoed doc puts the rails on a `"type":"user"` line, and an assistant `Write`/`Edit` call
  carrying rails in its file content serializes on a `"type":"assistant"` line. The same-line role
  check is only the cheap pre-filter; confirm on the per-candidate decode that the marker sits in
  an assistant `text` content entry, not a `tool_use` input.
- **Near-identical mtimes.** Multiple sessions can write within seconds; mtime cannot rank them.
  The directive / rails / `Prior session:` markers break the tie, not the timestamp.
- **Handoff files live in gitignored dirs far from `$HOME`**, and `memory_dir` is
  consumer-configurable, so the filesystem glob can miss them. Transcripts are the reliable index:
  they record the exact path (file mode) or the whole prompt (prompt-only), regardless of where the
  file lived.
- **Prompt-only handoffs have no file at all.** Do not error on a missing file, the resume content
  is inline between the rails in the transcript, and that is the recovery.
- **The `/loop` re-arm sits OUTSIDE the rails, and recovering only the block loses it.** Every
  other armed thing, `/goal` included, is inside the copy region, so it comes back for free; the
  loop re-arm cannot be, because a command is only recognized at a message's start and the re-arm
  has to be its own message. Recover the note anchored to the bottom rail and surface it at the
  confirm gate, or the recovered continuation runs exactly once and the recurring behavior dies
  silently, which is the failure the producer's re-arm rule was written to stop.
- **A background-launch save-point is not a lost handoff.** `continue-in-background` uses the same
  save-point engine, so its file looks identical, but its rails prompt was delivered, to the
  launched agent, and resuming it manually duplicates work already running in the background.
  Screen candidates via the producer transcript's launch signature, correlated to the exact file
  the launch's resume directive references, never session-wide, since one session can produce
  both a manual handoff and a later background launch under the same `session_id`, and never on
  the `continue-<topic>` slug alone (topic-only: same-topic files all match; ambiguous unless it
  uniquely resolves). "Successful" always means verified-visible. Transcript evidence the agent
  appeared, never exit-0 alone, since the producer itself warns a zero-exit launch can be
  invisible; unverified → ambiguous, keep the candidate. Exclusion also turns on the
  continuation's CURRENT state, because historical visibility is launch-time only, and that state
  must be read with **`claude agents --json --all`**. The bare `--json` lists active sessions only,
  so a continuation that COMPLETED SUCCESSFULLY is absent from it and indistinguishable there from
  one that died; treating that absence as failure surfaces a finished continuation's save-point as
  a lost handoff, which invites redoing done work and can bury the older manual handoff. Apply
  step 1's four-way resolution: live → exclude (running); terminal and completed → exclude, saying
  it FINISHED and pointing at that session's output; terminal and not completed → keep, as the
  restart artifact; absent even from `--all` → UNKNOWN (the history is bounded), keep, and do not
  call it a failure.
  Prompt-only continuations screen the same way, bound by content: a rails block whose exact
  prompt a verifiably successful `claude --bg` launch delivered (the producer writes it to a temp
  file in the same transcript first) was delivered, not lost, a later launch of a different
  prompt never disqualifies an earlier manual block.
