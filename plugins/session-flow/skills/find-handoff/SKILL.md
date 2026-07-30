---
name: find-handoff
description: "Recover a lost handoff after `/clear` — find the save-point file or resume prompt when the resume prompt was written but never copied and the fresh session has zero context. Read-only detection ladder: known-location glob of `<memory_dir>/handoffs/`, then a bounded, recency-ranked scan of transcripts (excluding the current session's own file) for the handoff directive and dashed-rail markers, then a confirm-before-resume gate. Use when: 'find my handoff', 'recover the handoff', 'I lost the resume prompt', 'forgot to copy the resume prompt', 'I cleared without saving the prompt', 'where's my handoff', 'recover after /clear', 'get back the handoff'. Surfaces only the resume prompt + handoff metadata, never raw transcript content; hands to `/session-flow:keep-going` when the recovered session ended mid-work rather than at a clean save-point."
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

## Context — gather first

Collect these with **individual** Bash calls, one command per call:

- Claude session id — `printenv CLAUDE_CODE_SESSION_ID`
- Current branch — `git branch --show-current`

Treat any failure as an unknown value and carry on. These are gathered here rather than pre-computed
because a worktree-isolated agent refuses any command carrying a `$`-expansion, which made this skill
fail at load — keep `$`-expansion out of the pre-compute block (#1687). Bare `$HOME` above is the one
form observed to survive that guard; anything else, including `${HOME}`, is refused.

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
"Detection contract"). This skill depends on three DETECTION signals, in precision order — plus one
resolution input, `Handoff origin:`, described after them:

1. **The file directive** — `Read @<path>/handoffs/<TS>-handoff-<topic>.md …`. It embeds the exact
   path to recover and survives verbatim into transcript JSONL, so it is the highest-precision key
   for a **file-based** handoff. **Two path forms qualify.** The producer now emits an absolute
   path; every handoff written before that rule shipped states a repo-relative one, and those
   transcripts are on disk unchanged. Match the directive on its `…handoffs/<TS>-handoff-…` shape,
   which both forms share, and let them diverge only at the existence check (step 3).
2. **The dashed rails + instruction line** — the two `─` (U+2500) rails and the literal
   `` `/clear`, then copy everything between the dashed lines `` line. For a **prompt-only** handoff
   there is no file and no directive; the resume content is inline between the rails, and the
   transcript is the only record — so this is the primary key for that branch.
3. **`Prior session: <UUID>`** and the `type: handoff` frontmatter (structure doc) — corroborating
   signal that pins the session chain. Corroboration only: the file-mode shape emits the
   `Prior session:` line, but the producer's prompt-only checklist does not require it, so its
   absence never disqualifies a prompt-only candidate.

**`Handoff origin:` is a resolution input, not a detection signal.** It cannot admit or reject a
candidate — a block is already qualified by the three signals above before it is read — so it is
deliberately outside that numbered list, and outside the conditional-signal slot the `/loop` re-arm
note holds below. What the ladder depends on it for is step 3's existence check: it names the
repository and repo-relative path that let a ROOTED directive survive a machine or checkout change,
which is the one failure an absolute path has that a relative one does not. It is emitted by the
file-mode shape only and only since the producer rooted its path, so its absence disqualifies
nothing — prompt-only never emits it, and no handoff older than the rooted directive has one.

**The resume prompt this skill recovers is the rails block PLUS every below-rail `/loop` re-arm
message** (save-point.md "Detection contract"). Everything else the producer arms lives between the
rails and is recovered with the block — `/goal` included. The `/loop` re-arm cannot: a command is
recognized only at a message's start, so the producer emits it as a separate follow-up message and
places its instruction below the bottom rail. Recovering only the copy region would therefore hand
back a continuation that runs once and silently drops the loop — the same failure the producer's
re-arm rule exists to prevent. The note is a fourth, **conditional** signal: present only when the
lost session was running under `/loop`, so its absence disqualifies nothing — and a **repeatable**
one, since the producer emits a separate re-arm message per surviving loop, so "found one" is never
"found them all".

## The recovery ladder — read-only throughout

1. **Known-location glob first (no transcript needed).** Resolve `<memory_dir>/handoffs/` for the
   **current repo** through the plugin binding
   ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md))
   — never assume the literal `.work`; the memory root is consumer-configurable. Add the fallback
   `${CLAUDE_PLUGIN_DATA}/topic-docs/handoffs/` **only when project-root resolution fails**: the
   producer writes there only on its no-project-root branch (topic-docs binding), so inside a repo
   that shared location holds unrelated sessions' save-points, and a newer one could hijack the
   short-circuit ahead of the transcript holding this repo's lost handoff. Glob `*-handoff-*.md`,
   keep only files whose frontmatter is `type: handoff`, rank by mtime. A strong, recent candidate
   → jump to step 4 (step 5's chain validation then locates the producer transcript by the file's
   `session_id`, since this path found no transcript) — **but run step 3's re-arm-note capture
   before that jump**, or this short-circuit surfaces a looping handoff with its `/loop` re-arm
   missing while step 4 claims to present it. Locate the producer transcript by the candidate's
   own `session_id` (`<session_id>.jsonl` under `~/.claude/projects/*/` — the same lookup step 5
   performs, pulled ahead). That is a bounded, read-only read of ONE already-named file, not the
   step-2 scan reintroduced. **Bind the note to THIS candidate by content, never by taking the
   transcript's last one:** one session can emit several handoffs, so find the rails block whose
   `Read @…` directive names this exact file and capture only the note adjacent to that block. A
   tail read would hand back a later handoff's note — and if the loop was stopped and relaunched
   with a different prompt in between, that re-arms the wrong recurring work, which is worse than
   returning nothing. This is the same correlate-by-content rule the background-delivery screening
   above already runs on. No block names this file, transcript missing, or no note → surface the
   candidate without a note and say which, never block on it. **Exception — operator says the handoff was
   prompt-only:** then no file is the target (prompt-only writes none), and handoff files
   intentionally accumulate, so a recent file here belongs to some *other* handoff. Skip this
   short-circuit and go straight to the transcript scan. **Screen for background-delivery
   save-points before short-circuiting:** `/session-flow:continue-in-background` writes an
   indistinguishable `type: handoff` file with the same engine — but its rails prompt was
   *delivered*, to the agent it launched. Locate the candidate's producer transcript by the file's
   `session_id` and look for the launch signature (`claude --bg --name "continue-…"`, or the
   continue-in-background invocation) — then **correlate the launch with this exact file**: a
   launch delivers one specific rails prompt, and its `Read @…` directive names the exact
   timestamped file it delivered. The `--name "continue-<topic>"` slug identifies only the topic —
   same-topic files from the same session all match it — so slug-only evidence is **ambiguous**
   unless it uniquely resolves to one candidate. One session can produce a manual
   handoff *and* later a background launch, and both files carry the same `session_id`, so a
   session-wide signature match must never exclude by itself. **"Succeeded" means
   verified-visible, not exit-0** — the producer itself warns a zero-exit `claude --bg` can still
   be invisible and verifies the agent actually appeared, so exclusion requires transcript
   evidence of that verification (the agent listed/confirmed); this definition governs every
   screening site in this skill. Matched launch references this candidate and verifiably
   succeeded → **recheck the CURRENT `claude agents` state before excluding** — transcript
   evidence proves only launch-time persistence, and an agent that has since exited or failed
   leaves this save-point as the artifact needed to restart the work. Continuation still live →
   the save-point is not the lost handoff: exclude it from the default winner, say so, and keep
   looking for the older manual handoff. Continuation absent or failed now → keep the candidate,
   noting the failed background attempt. Launch references a different file, failed, or is
   unverified/ambiguous → keep the candidate (surfacing the provenance at the confirm gate when
   ambiguous). The current-state recheck applies to every screening site, prompt-only included. **v1 scope: current repo only.** The cross-repo *filesystem* sweep (deriving
   other repo roots from transcript `cwd` fields) is deferred — step 2's transcript scan already
   recovers handoffs written in other repos, since transcripts are indexed by session, not repo.

   **OPEN — this rung cannot correlate a candidate to the repository the work was in.** Run from a
   directory that is not the worked-in repo but has its own handoffs dir, the glob returns conforming
   `type: handoff` files from unrelated sessions and the target is not among them; nothing here can
   reject a same-cwd, different-repo candidate, because a handoff file records no durable repository
   identity — `structure.md`'s frontmatter carries `type`, `date`, `topic`, `session_id`, and
   `previous_handoff`, and none of those names a repo. Closing it needs a new frontmatter field, a
   cross-cutting schema change every existing handoff on disk would lack, decided on its own merits
   rather than inside a path fix (#1778). Until then: prefer the transcript scan whenever this rung's
   candidates are merely recent rather than clearly this work's, and never present a glob candidate
   as repo-verified. Reading the repository off the producer transcript is deliberately NOT used as
   a substitute — it depends on a transcript that may be absent, which this skill's own Gotchas say
   is the reason transcripts are the reliable index over the filesystem, and it returns nothing for
   every rootless legacy handoff, i.e. exactly where a correlation check is needed.
2. **Transcript scan — bounded, recency-ranked, cross-repo.** Enumerate `~/.claude/projects/*/`
   project dirs (the lost session may have run in a **different** repo, so scan all of them, not
   only the current project's dir), rank `.jsonl` by mtime, and take the top handful. **Bound the
   scan** — a full recursive grep over every transcript is slow enough to time out; an mtime-sorted
   candidate list is mandatory, not optional. **Exclude the current session's own transcript**
   (the session id gathered above): `/clear` opened a new file in the same project
   dir, so the pre-clear content is a sibling, never this file.
3. **Marker detection over candidate tails (grep, read-only).** Scan the tail of each candidate for
   the contract signals above. **Accept hits only from assistant text output**, in two stages:
   - *Cheap same-line pre-filter:* each transcript event is one physical JSONL line carrying its
     own role field, so drop any matching line that does not also contain `"type":"assistant"` — a
     substring check, no parsing. Rails in a user message or a tool result (a pasted sample, a doc
     echoed by a read) are not a handoff emission.
   - *Confirm on the per-candidate decode:* when un-escaping the surviving line (below), verify
     **both** that the decoded event's top-level `type` actually equals `assistant` (the
     pre-filter is only a substring — a user message *quoting* transcript JSON or docs contains
     the literal `"type":"assistant"` and would pass it) **and** that the marker sits in a
     `message.content` entry whose own `type` is `text`. An assistant
     `Write`/`Edit` call serializes its file content on an assistant line too, so a `tool_use`
     input carrying rails (writing a doc or fixture) is not assistant-visible output and not a
     handoff. This decode is per-candidate — a handful of lines — never a bulk parse.
   - **File mode** — match the `Read @…/handoffs/<TS>-handoff-<topic>.md` directive. **Filter out
     the template placeholder:** a match containing the template's own placeholder tokens
     (`<handoffs-dir>`, `<TS>`, `<topic>`) is the `save-point.md` doc being read into some
     session's context — not a real handoff. Keep only concrete paths. Then confirm the referenced
     file exists on disk, **by the directive's path form**:
     - **Rooted directive** (the current producer shape) — check the absolute path as given. No cwd
       is involved, so nothing can resolve it against the wrong root. **A rooted path can still
       miss**, and for a reason the rootless form does not have: an absolute path is machine-local,
       so a resume on a different machine or a different checkout of the same repository finds
       nothing there. That is exactly the case the producer emits `Handoff origin:` for — so on a
       rooted miss, read that line and re-resolve its repo-relative path against the repository it
       names; a hit there surfaces the recovered file normally, and only if that re-resolution
       ALSO finds nothing does the candidate fall through to the shared rule below. Never treat a
       rooted miss as absence: it is the same not-found-here condition, reached from the other
       direction.
     - **Rootless directive** (every handoff written before the producer rooted its path) —
       **resolve it against the source transcript's `cwd` field, not the current session's cwd**. A
       handoff recovered from another repo's transcript is otherwise falsely reported missing when
       checked from here. These blocks carry no `Handoff origin:` line: it shipped with the rooted
       form, so nothing older than that has one.
     - **A path that resolves to nothing — rooted or rootless — is UNRESOLVED, never dropped.**
       Neither resolution is proof of absence. The rootless one is an inference: it assumes the
       producer's cwd *was* the repository it wrote into, which is the very assumption that loses
       the handoff when a session works in a repo that is not cwd's project root. The rooted one is
       a machine-local literal that a different machine or checkout cannot satisfy. Either way,
       discarding the candidate throws away a directive that names the right filename and is the
       strongest evidence in hand. Keep it, carry the filename plus whichever path form was tried,
       and surface it at step 4 marked UNRESOLVED. Before doing so, spend one bounded, read-only
       widening: glob that filename under the **verified repository roots** already in hand — the
       current repo, and the repository named by any `Handoff origin:` line. **A candidate
       transcript's `cwd` earns a place in that set only once it is confirmed to BE a repository
       root** — `git -C <cwd> rev-parse --show-toplevel`, and glob under the top level it prints
       rather than `cwd` itself. A session launched from a home directory records that home
       directory as its `cwd`, so globbing under an unverified `cwd` is a recursive sweep of most
       of the user's files: the machine-wide scan this rule forbids, reached by accident rather
       than by intent, and slow enough to time the recovery out. A `cwd` with no git top level
       contributes no root — the candidate stays UNRESOLVED and step 4 asks the operator which
       checkout to look in, which is the honest answer when nothing in hand can name one. Promote a
       single unambiguous hit to a resolved candidate. Two or more hits stay UNRESOLVED with the
       matches listed; the operator picks. Never widen into a machine-wide filesystem sweep.

     **Apply step 1's background-delivery screening to these candidates too** — the launch
     signature, if any, sits in this same transcript: a file whose exact directive a verifiably
     successful `claude --bg` launch (step 1's definition) delivered is not a lost handoff, wherever
     it was discovered.
   - **Prompt-only mode** — no file, no directive. Detect off the `─` rails and the instruction
     line; the resume content is the block inline between the rails. `Prior session:` is
     **optional corroboration, never a required key** — the producer's prompt-only checklist
     requires only a self-contained prompt between the rails plus the copy instruction, so
     requiring it would skip valid handoffs. **Apply the same placeholder filter as file mode:** a
     block still carrying the template's own placeholder tokens (`<handoffs-dir>`,
     `<TS>-handoff-<topic>`, a literal `Prior session: <UUID>`) is the `save-point.md` template
     read into some session's context, not a real handoff. Match those **specific tokens only** —
     never a blanket no-angle-brackets rule: a valid prompt legitimately contains other
     angle-bracket text, notably the redaction shape markers the producer deliberately emits
     (`<REDACTED: API key>`) and generic code syntax (`<T>`). When a `Prior session:` line is
     present, its value must be a concrete session UUID. **Screen delivered continuations here
     too:** `continue-in-background prompt` emits this same rails block as assistant text and then
     delivers the inline prompt to the agent it launches — check the same transcript after the
     block for a verifiably successful `claude --bg --name "continue-…"` launch (step 1's
     definition: transcript evidence the agent appeared, not exit-0 alone). **Bind the launch to the
     block by content, never by ordering alone:** the producer writes the exact launched prompt to
     a temp file (visible in the same transcript as the Write preceding the launch) — a launch
     excludes only the block whose content it delivered; a later launch of a *different* prompt
     never disqualifies an earlier manual block in the same transcript. A delivered block is not a
     lost handoff (its work is already running — `claude agents` lists it); exclude it and keep
     scanning.
   - **Capture the below-rail `/loop` re-arm entries — every mode, every discovery path, every
     loop.** Once a candidate qualifies on the signals above, also take the re-arm instructions the
     producer emits below the bottom rail. **Read the `Re-arm <i> of <n> — <L> lines:` headers and
     take the next `<L>` lines verbatim** (save-point.md "Loop-aware re-arm"). The next header
     begins where the previous entry's `<L>` lines end; repeat until `n` entries are held. Anchor
     the search to the bottom rail — never "the lines after the rail" unbounded, which would widen
     this skill into the raw-transcript dump it forbids.

     **Match on the length, never on the content.** The three ways this capture has been got wrong
     are all the same mistake — bounding a verbatim region with a content test:

     - **Command wording** ends the entry at the first continuation line of a multi-line prompt,
       cutting it in half and losing every entry behind it.
     - **The next header** looks safe until a prompt quotes one. The prompt is reproduced exactly as
       the operator typed it, so a prompt containing the literal text `Re-arm 2 of 3` would split
       its own command. Any sentinel has this flaw; a line count does not.
     - **Stopping at the first hit** recovers one of three re-arms and drops two schedules while
       looking like it worked.

     Read `<L>` as a literal count — `lines` never inflects, so `1 lines` is a well-formed header
     and not a shape drift.

     `<n>` is the self-check, not the scanner: recover all `n`. Finding fewer, or an `<L>` that runs
     past the end of the message, means the transcript is truncated or the shape drifted — surface
     what was found and say `n` were expected, rather than presenting a subset as the whole.

     **This is a capture, never a detection
     key:** it is taken only from an already-qualified candidate, so it cannot admit a candidate
     the rails markers rejected. No header at all → the session was not looping; surface nothing extra.
     **Do not add the note's placeholder tokens to the template-rejection list.** Unlike the rails
     template, the producer *really does* emit `<interval>` and `<the prompt you originally
     launched it with>` verbatim on its no-launch-signal branch, under a `Re-arm <i> of <n> — <L>
     lines:` header like any other entry (save-point.md "Loop-aware re-arm"), so rejecting on them would discard a
     genuine note; a transcript that merely read
     `save-point.md` is already rejected by the existing rails-template filter.
   - **Un-escape before surfacing.** Each transcript message is ONE physical JSONL line with its
     text JSON-string-escaped (`\n` for newlines, `\"` for quotes, `\\` for backslashes). A raw grep
     hit is that escaped blob — decode it back to plain text (JSON-unescape the matched string)
     before surfacing, or the user sees a wall of `\n`/`\"` instead of the prompt. This matters most
     in prompt-only mode, where the whole inline block is what gets surfaced.
   - mtime alone can never pick the winner (multiple sessions land within seconds of each other) —
     the markers do.
4. **Confirm before resuming — hard gate.** Surface the found handoff's **metadata only**: the
   recovered file path (or the original `Read @…` directive as found), topic, date, and the
   `session_id` chain (file mode) or the inline resume prompt (prompt-only mode) — the path is the
   thing being recovered, and the operator cannot verify the candidate without it. **Surface the
   captured `/loop` re-arm notes with it — all of them, on both modes, whenever any were found**,
   and say plainly that each re-arm is its own follow-up message sent after the continuation is
   under way — dropping one here loses that loop just as surely as never recovering the prompt. Ask
   for an explicit yes/no and **stop**. Do not read the file's body, `/clear`, or execute the
   resume prompt before the operator confirms. Resuming the **wrong** handoff is worse than
   recovering none.

   **UNRESOLVED candidates are presented, not suppressed.** A candidate whose directive named a file
   that could not be located is surfaced alongside the resolved ones and labelled `UNRESOLVED`,
   carrying the directive verbatim, the filename, and any `Handoff origin:` line. Name the reason
   precisely rather than reporting "the file is missing" — those are different failures, and
   reporting absence for either of them is what makes this expensive to diagnose:
   - **Rootless** — the path has no root, and the transcript `cwd` it was resolved against did not
     hold it. Say which `cwd` was tried. Closing it takes one fact: the operator names the
     repository the work was in, and the relative path resolves under it.
   - **Rooted** — the path is absolute and nothing is at it on THIS machine, which is what a resume
     on a different machine or checkout looks like. Say the absolute path that was tried, and the
     repository the `Handoff origin:` line named. Closing it takes the local checkout of that
     repository.

   An UNRESOLVED candidate never auto-wins over a resolved one, and it is never the default answer
   when a resolved candidate exists.
5. **Chain validation (file mode).** Validate each frontmatter pointer against what it actually
   names:
   - `session_id` identifies the **emitting** session. Compare it with the source transcript when
     the candidate came from the transcript scan. On a glob-only recovery (step 1 jumped straight
     to step 4 with no transcript in hand), locate the producer transcript by that `session_id` —
     transcript files are named `<session_id>.jsonl` under `~/.claude/projects/*/` — and compare
     against that; when it cannot be found, say so and present the candidate as unvalidated rather
     than blocking or guessing.
   - `previous_handoff` deliberately names the **predecessor** in the chain (structure doc "Chain
     continuity"), not the emitting transcript. Validate it against the named prior handoff file —
     never against the source transcript, or a valid chained handoff looks inconsistent.
   On a mismatch, flag it and let the operator decide — never silently splice an unrelated session
   into the chain.
6. **Hand off to the resume path.** On confirmation:
   - **Clean save-point** → read the handoff file and continue its remaining next steps (the normal
     `/session-flow:handoff` resume path). For a prompt-only recovery, continue from the inline
     prompt.
   - **Ended mid-work** (the recovered state shows interrupted, in-flight work rather than a
     deliberate save-point) → hand to `/session-flow:keep-going`, which recovers and continues
     interrupted work.

## Read-only + redaction — hard invariants

- **Read-only through the confirm gate.** Detection and everything before the operator's
  confirmation writes nothing, never `/clear`s, never executes the resume. **After** confirmation,
  control passes to the selected resume path (the handoff's next steps, or
  `/session-flow:keep-going`), which acts normally — the read-only guarantee covers the recovery,
  not the resumed work.
- **Redaction-aware.** Transcripts and handoff files can contain secrets. Quote **only** the resume
  prompt — the rails block plus every below-rail `/loop` re-arm note — and the handoff metadata;
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
  it is checked for an `@` ahead of its host before either. **Drop the userinfo and keep the rest — do
  NOT replace the URL with a shape marker.** The shape-marker rule above assumes the whole value is
  secret and unneeded downstream; a remote URL is the opposite. Its host and path are not secret and
  they are what makes the value useful: this line is the input that re-resolves a rooted miss, so a
  `<REDACTED: remote URL>` marker would destroy the identity recovery depends on and turn a
  credential leak into a failed recovery. So `https://<token>@github.com/<owner>/<repo>.git` is
  surfaced as `https://github.com/<owner>/<repo>.git`, never a marker; when the userinfo boundary is
  not clear (`save-point.md` `<repo-identity>` gives the test), surface the repository name alone
  rather than guessing. The producer strips it at emit time, but a recovered handoff predates that
  rule as easily as it predates the rooted path — recovery is exactly where an unsanitized one
  arrives.

## Boundaries — pick the right sibling

- **`/session-flow:handoff`** — the producer. Writes the save-point + resume prompt this skill
  recovers. find-handoff writes nothing during recovery.
- **`/session-flow:keep-going`** — recovers and continues **off-thread / interrupted** work. When
  the lost session ended mid-work, this skill hands there. keep-going covers the case where the
  handoff path is *known* but work was interrupted; find-handoff covers the disjoint case where the
  path itself is lost.
- **`/session-flow:orient`** — reads durable state (including handoffs) whose location is already
  known, for a where-we-stand briefing. find-handoff is the recovery step for when that location is
  unknown.

## What this skill does NOT do

- **Writes nothing during recovery** — no files, no memory, no `/clear`, no resume execution
  before the confirm gate. Post-confirmation work belongs to the selected resume path, not to this
  skill's recovery ladder.
- **Does not dump raw transcript content** — surfaces only the resume prompt (rails block plus the
  below-rail `/loop` re-arm notes) + metadata, redacted.
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
  containing the template's placeholder tokens; keep only concrete resolved paths. The prompt-only
  template — the `─` rails plus a placeholder body and a literal `Prior session: <UUID>` — is the
  same false positive; reject a block on those specific tokens, and require a concrete session
  UUID (not the `<UUID>` placeholder) on any `Prior session:` line before surfacing. **Never
  blanket-reject angle brackets** — valid prompts carry `<REDACTED: …>` shape markers and code
  syntax.
- **A rootless directive is the legacy form, and resolving it is inference.** The producer emits an
  absolute path now; handoffs written before that shipped state a repo-relative one, so both forms
  keep arriving. For the rootless form, read the `cwd` field of the transcript the directive was
  found in and resolve against that — checking existence from the current session's cwd falsely
  reports a cross-repo handoff missing. But that resolution assumes the producer's cwd *was* the
  repository it wrote into, which is untrue for exactly the sessions this skill exists to rescue: a
  session working in a repo that is not cwd's project root. So a rootless miss is UNRESOLVED, not
  absent — surface it with its directive and say the path has no root, never that the file is
  missing.
- **Markers in user messages, tool results, and tool INPUTS are not handoffs.** A pasted sample or
  an echoed doc puts the rails on a `"type":"user"` line — and an assistant `Write`/`Edit` call
  carrying rails in its file content serializes on a `"type":"assistant"` line. The same-line role
  check is only the cheap pre-filter; confirm on the per-candidate decode that the marker sits in
  an assistant `text` content entry, not a `tool_use` input.
- **Near-identical mtimes.** Multiple sessions can write within seconds; mtime cannot rank them.
  The directive / rails / `Prior session:` markers break the tie, not the timestamp.
- **Handoff files live in gitignored dirs far from `$HOME`**, and `memory_dir` is
  consumer-configurable — so the filesystem glob can miss them. Transcripts are the reliable index:
  they record the exact path (file mode) or the whole prompt (prompt-only), regardless of where the
  file lived.
- **Prompt-only handoffs have no file at all.** Do not error on a missing file — the resume content
  is inline between the rails in the transcript, and that is the recovery.
- **The `/loop` re-arm sits OUTSIDE the rails, and recovering only the block loses it.** Every
  other armed thing — `/goal` included — is inside the copy region, so it comes back for free; the
  loop re-arm cannot be, because a command is only recognized at a message's start and the re-arm
  has to be its own message. Recover the note anchored to the bottom rail and surface it at the
  confirm gate, or the recovered continuation runs exactly once and the recurring behavior dies
  silently — which is the failure the producer's re-arm rule was written to stop.
- **A background-launch save-point is not a lost handoff.** `continue-in-background` uses the same
  save-point engine, so its file looks identical — but its rails prompt was delivered, to the
  launched agent, and resuming it manually duplicates work already running in the background.
  Screen candidates via the producer transcript's launch signature, correlated to the exact file
  the launch's resume directive references — never session-wide, since one session can produce
  both a manual handoff and a later background launch under the same `session_id`, and never on
  the `continue-<topic>` slug alone (topic-only: same-topic files all match; ambiguous unless it
  uniquely resolves). "Successful" always means verified-visible — transcript evidence the agent
  appeared, never exit-0 alone, since the producer itself warns a zero-exit launch can be
  invisible; unverified → ambiguous, keep the candidate. Exclusion also requires the continuation
  to be live in the CURRENT `claude agents` state — historical visibility is launch-time only,
  and a since-exited or failed agent leaves the save-point as the restart artifact. Exclude only
  the correlated, verifiably successful, still-live launch's file and point the operator at
  `claude agents` instead.
  Prompt-only continuations screen the same way, bound by content: a rails block whose exact
  prompt a verifiably successful `claude --bg` launch delivered (the producer writes it to a temp
  file in the same transcript first) was delivered, not lost — a later launch of a different
  prompt never disqualifies an earlier manual block.
