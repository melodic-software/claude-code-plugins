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

**Worktree caveat.** A save-point written inside a `git worktree` checkout resolves its memory
root within that worktree, so the handoff file lives there — and dies with `git worktree remove`.
That is acceptable only when the worktree completes as a merged PR unit: the work is durable in
merged history by the time the worktree goes. When pausing un-merged worktree work, write the
handoff from the main checkout instead, or rely on `/session-flow:clean-stop`'s
preserve-before-remove step — before removing a worktree it inspects the ignored content a plain
`git status` hides (`git status --ignored`) and preserves or surfaces anything not reproducible,
generated handoff data included.

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
- No abandoned approaches or hard-won findings worth preserving
- No load-bearing decision + rationale a future session must not rediscover
- No non-trivial task list to reconstitute
- No invariant a resuming session could violate without noticing
- No side effect already applied that a fresh session would otherwise repeat

The last two are the sharpest: a short, straightforward remainder is exactly the shape that passes
every other test, and "the migration is already applied — do not re-run" is precisely the fact a
prompt-only bullet list drops. A single one of them is enough to force the full path.

ANY doubt → full save-point. A wrongly-skipped file loses state the fresh session must rediscover;
a wrongly-written one costs nothing. An explicit method argument overrides auto-detect — but note
`prompt` leaves a gap in the session-id chain that `/session-flow:retro` walks (no file, no chain pointer).

## Redaction pass — mandatory on BOTH paths

Before writing the handoff file or emitting the resume prompt, sweep everything outbound — body
sections, TaskList snapshot, frontmatter, and the prompt between the rails — for secrets, API keys,
tokens, credentials, connection strings, and PII, and redact each hit with a shape marker
(`<REDACTED: API key>`), never the value. Save-point output outlives the session: it sits on disk
uncommitted-but-readable, travels to other sessions and machines, and gets read in contexts the
current conversation never anticipated. A value acceptable to see in-session is not acceptable to
persist. This pass gates the write — no artifact or prompt is emitted before it runs.

**Git remote URLs are a named vector on that list, and they take a different treatment.** A remote
embeds its credential in the URL's userinfo component (`https://<token>@host/…`), where it reads as
one more path segment rather than as a secret — the shape this sweep is likeliest to walk past. So
every **git remote** URL in the outbound set is checked for an `@` ahead of its host. **Drop the
userinfo and keep the rest — do NOT replace the URL with a shape marker. This is a deliberate
exception to the rule above, and it wins for git remote URLs and nothing else.** The general rule
redacts to a marker because the whole value is secret and nothing downstream needs it; here the
opposite holds. The scheme, host, and path are not secret, and they are load-bearing:
`Handoff origin:` exists so a resume on another machine can re-resolve the file from the repository it
names, and a `<REDACTED: remote URL>` marker would destroy the identity the line is emitted to carry —
turning a credential leak into a broken recovery. So
`https://<token>@github.com/<owner>/<repo>.git` becomes `https://github.com/<owner>/<repo>.git`,
never a marker. `Handoff origin:` is where such a URL most plausibly appears, and it sits inside the
copy region; `<repo-identity>` below requires it stripped at emit time so this pass has nothing left
to catch.

**The exception does not generalize to other credential-bearing URLs.** A connection string such as
`mongodb+srv://<user>:<secret>@<host>/<db>` keeps the general treatment — a shape marker
(`<REDACTED: database connection string>`), not a host-preserving strip. What earns a git remote URL
its exception is that something downstream re-resolves from the surviving host and path; nothing
re-resolves from a database host, so preserving it discloses infrastructure for no recovery benefit.
Strip-and-keep applies where the remainder is load-bearing; everywhere else the marker still wins.

## Claim provenance — mandatory on BOTH paths

A status claim earns plain statement only when THIS session verified it — a command run, a file
read, an output observed. Anything inherited — a prior handoff's assertion, an issue label, a
remembered state — carries an explicit `UNVERIFIED (<source>)` marker instead: the resuming session
treats an unmarked claim as fact and builds on it, so an inherited claim is a claim to falsify, not
a fact to forward.

This governs both paths, not just the full path's body sections. On the full path it shows up
throughout [`structure.md`](structure.md) — most visibly the met/unmet marks in Completion criteria.
Prompt-only writes no body sections at all, so the marker attaches directly to whichever inline
remaining-work bullet carries the inherited status; a bullet that folds in an inherited "done" or
"blocked" without `UNVERIFIED (<source>)` reproduces the exact failure this rule exists to prevent,
with no file left behind for a later review to catch it in.

## Original goal — mandatory on BOTH paths

The goal in the user's own words travels with every save-point, and a chain of them carries it
forward unchanged. A save-point serializes the machinery in front of it effortlessly — the phase,
the checklist, the bundle — and hands the resuming session a mission made of process, which that
session then optimizes faithfully. State is what a save-point preserves for free; intent is what it
drops in silence, and no amount of detail elsewhere replaces it.

On the full path this is body section 1, `Original goal` ([`structure.md`](structure.md)) — which
also owns the immutability rule and the disk-read copy step a successor handoff runs.
**Prompt-only writes no body sections, so it carries the verbatim goal inline between the rails**,
above its remaining-work bullets — and below an active `/goal` re-arm when one holds the first
line: the re-arm keeps that line ("Combining both", below), the goal quote comes next, the bullets
after. It has no file to point at, and a prompt-only save-point listing only the follow-ups is the
exact shape that loses the goal.

**Amendments travel too.** A bare single goal line is valid only while the goal has no recorded
amendment (`Amended: None.` on the full path). Once an amendment exists, the prompt-only form
carries the original dated quote plus EVERY dated amendment — compact, one line each,
`amended <date>: "<verbatim quote>"` under the original — still verbatim, still copied unchanged on
later hops. The full path preserves that history in §1's `Amended:` field; a prompt-only hop that
collapses it back to a single line discards the record of what the goal was and when it stopped
being that, which no later full-path handoff can reconstruct.

## The purpose argument tailors emphasis only

A citing skill may hand the engine optional trailing purpose text — the invocation's answer to
"what will the next session be used for?" (the producer's `[file|prompt] [topic] [purpose...]`
surface, parsed from `$ARGUMENTS`). When present, purpose tailors **emphasis only**, in exactly
three places:

- The **Resumption brief** leads with it — the brief's framing opens from what the next session is
  for, still inside its six-line cap.
- **Suggested skills** are selected for it — the skills recommended are the ones serving that use,
  each still tied to a concrete remaining item.
- **Remaining actions** are ordered by it — among actions whose order is otherwise free; a genuine
  sequencing dependency still binds, purpose never licenses running an action before one it
  depends on.

**Prompt-only carries the purpose inline — never discard it.** The three surfaces above are
full-path sections, and prompt-only writes none of them; its delivery can also hand the rails
block to a background agent as the only thing that agent ever sees. So on prompt-only, a stated
purpose travels between the rails as a single `Purpose: <text>` line directly below the goal
quote (and its dated amendment lines, when present) and above the remaining-work bullets — the
same travels-in-the-prompt-or-not-at-all rationale the Original goal rule above states. The
inline bullets are still ordered by it where ordering is free, but ordering alone cannot carry
it — with one action left it expresses nothing — so the line is the carrier, not a fallback.
This is content between the rails, not a shape change: every detection-contract signal below
(the rails, the copy-instruction line, the `Read @…` directive, the `Prior session:` line) is
untouched.

What purpose may NEVER do:

- It never drops, renames, or reorders the mandatory section set ([`structure.md`](structure.md)'s
  ordered body sections). The structure is the anti-drift contract; every section is still present,
  and one with nothing purpose-relevant to say still says so.
- It never alters the emitted resume-prompt shape — the rails, the directive, the origin line, the
  re-arm notes. That shape is the detection contract below; changing it for a purpose would be a
  knowing contract break requiring a coordinated `find-handoff` change, which passing a purpose is
  not.
- It never amends the Original goal. A purpose that contradicts the goal is **flagged at write
  time, not silently obeyed**: say plainly that the stated purpose does not serve the recorded
  goal and ask whether the goal has changed — the goal moves only by the explicit dated amendment
  the structure doc's `Amended:` field records, never because a purpose pointed elsewhere.

Absent purpose text, nothing here applies and the engine behaves exactly as it always has.

## Writing the handoff file (full path)

The body sections, the TaskList reconstitute format, and the frontmatter shape (including the
`session_id` and `previous_handoff` chain fields that `/session-flow:retro` walks) live in
[`${CLAUDE_PLUGIN_ROOT}/reference/structure.md`](${CLAUDE_PLUGIN_ROOT}/reference/structure.md)
— walk it while writing the file; never write the section list from memory.

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
- **Goal-aware re-arm:** if a `/goal` is active this session — check for a `/goal` establishing or
  re-arming call earlier in this conversation with no later stop/completion, not "infer from
  conversation" prose — the FIRST line between the rails starts with literal `/goal <condition>` —
  `/clear` destroys an active goal, so the pasted block must re-arm it. When no such call is found,
  omit it and note below the bottom rail: "if a goal was active, prepend `/goal <condition>`."
- **Loop-aware re-arm:** if this session is running under `/loop` — check for this session's own
  `/loop [<interval>] <prompt>` launch turns earlier in the conversation with no later stop (`Esc`, or
  a `ScheduleWakeup` call carrying `stop: true`), not "infer from conversation" prose. A subsequent
  `ScheduleWakeup` reschedule call (`stop` absent or `false`) corroborates self-paced mode but is
  never required to conclude the loop is active — on the loop's first iteration no reschedule has
  fired yet, so its absence is not evidence of anything. Starting a fresh conversation clears every
  session-scoped scheduled task
  (<https://code.claude.com/docs/en/scheduled-tasks#limitations>), so a resume prompt that says
  nothing about the loop runs the continuation once and silently loses the recurring behavior — the
  same failure class `/goal` re-arm exists to prevent.

  **Enumerate every surviving loop, and only the surviving ones.** A session can hold up to 50
  scheduled tasks at once (<https://code.claude.com/docs/en/scheduled-tasks#manage-scheduled-tasks>),
  so treat the launch turns as a set, not a single find: `/clear` takes them all, and a note that
  re-arms one silently drops the rest. Two conditions retire a launch from that set. A later stop for
  that specific loop, as above. And elapsed time: a recurring task expires seven days after creation
  (<https://code.claude.com/docs/en/scheduled-tasks#seven-day-expiry>), so a launch turn older than
  that is already gone on its own — reading it as active would have the note resurrect a schedule the
  operator's session had already stopped running. Emit one re-arm message per loop left standing, and
  nothing at all when none is.

  **The re-arm is a SECOND message, and it carries the ORIGINAL loop prompt — never the resume
  directive.** `/loop` re-runs the prompt it was given on *every* iteration
  (<https://code.claude.com/docs/en/scheduled-tasks#run-a-prompt-repeatedly-with-%2Floop>), and a
  save-point is an immutable record of one moment. Wrapping the resume directive in `/loop` would
  therefore make every later tick re-read that frozen file and replay a remainder already done —
  the loop would stop doing its actual recurring job. So the rails block stays exactly what it is on
  every other path (the resume directive, unwrapped, bootstrapping the continuation once), and the
  note below the bottom rail reads: "this session was running under `/loop`; after pasting the block
  above, send `/loop [<interval>] <original prompt>` as a separate message to re-arm it" — quoting
  the interval and the prompt verbatim from the launch turn, self-paced meaning no interval token,
  and listing one such message per surviving loop, since a command is recognized only at a message's
  start and two cannot share one. Order matters and is stated in the note: bootstrap first, re-arm
  second, because the re-armed loop's own first iteration must not run before the continuation it is
  resuming into. When no launch-turn signal is found, say instead: "if a loop was active, re-arm it
  with `/loop [<interval>] <the prompt you originally launched it with>` after pasting the block
  above."

  **Delimit the re-arm entries; a verbatim prompt can be several lines long.** The prompt is quoted
  exactly as the operator typed it, and a message can carry newlines, so an entry is not reliably
  one physical line and "the next line that stops looking like a re-arm" is not a boundary a
  consumer can trust — it truncates the first multi-line prompt it meets and swallows the entries
  after it. Give the block real edges instead:

  - Head each entry with a literal `Re-arm <i> of <n> — <L> lines:` line, then the entry body on
    exactly the next `<L>` lines. `<n>` is the number of surviving loops; `<L>` counts the body
    lines only, never the header. The word `lines` does not inflect — a one-line entry still reads
    `1 lines`, because a parser should not have to know English plurals to find a boundary.
  - **`<L>` is the boundary, and it is a length, not a pattern.** No marker, sentinel, or
    "looks like a re-arm" test can bound a region whose content is reproduced verbatim: whatever
    string is chosen, a prompt is allowed to contain it, and the delimiter then fires inside the
    payload. Counting lines is the only rule that cannot collide with what it delimits, so a prompt
    holding a blank line, a dashed rail, or the literal text `Re-arm 2 of 3` passes through intact.
  - `<n>` is not needed to find the entries — the lengths already do that — but it makes recovery
    self-checking: a consumer can prove it holds the whole set instead of hoping so.
  - Put the re-arm block LAST in the message, after the paste-condition note, so the entries are
    contiguous and nothing interleaves them.
  - The no-launch-signal fallback is a single entry with the same header, so a consumer parses one
    shape rather than two.

  Changing this shape is a knowing break of the detection contract below, and must move
  `find-handoff` with it.

  **The note is conditioned on the paste, not on the citing skill.** Re-arming exists only because
  `/clear` destroys the session-scoped schedule, so a delivery that never clears needs none: a
  successful `/session-flow:continue-in-background` launch hands the rails prompt straight to a
  detached agent, clearing nothing, and the loop stays armed on the session still sitting there.
  But the engine emits this prompt BEFORE that skill runs its dirty-tree gate or its launch, and
  both can fall back to the standard `/clear`-then-paste instruction — so the delivery path is not
  yet knowable here, and keying the note off the citing skill's identity would drop the re-arm on
  exactly the fallbacks that do clear. Word the note conditionally instead, so it is correct
  whichever way delivery resolves: "this session was running under `/loop` — **if you paste this
  block after `/clear`** (including the fallback when a background launch is refused or fails),
  send `/loop [<interval>] <original prompt>` as a separate message afterwards to re-arm it; a
  background launch that succeeds clears nothing, so the loop keeps running here and needs no
  re-arm." Transferring the loop INTO the launched agent is deliberately not done: that would arm a
  recurring schedule inside a detached session the operator is not watching, which is a new
  behavior to decide on its own merits, not a side effect of writing a save-point.
- **Combining both:** a command is recognized only at the start of a message
  (<https://code.claude.com/docs/en/commands>), so neither re-arm can ride inside the other's prompt
  argument — text after the command name is just more of that argument, not a second command
  invocation, and would silently fail to arm. Each is therefore its own message. `/goal` keeps its
  place as the first line between the rails (it is session-scoped and evaluated after every
  subsequent turn regardless of what invoked it, so arming it there covers the loop's later
  iterations too); the `/loop` re-arm follows as the separate message described above. On
  prompt-only, the verbatim goal quote — with its dated amendment lines, per "Original goal —
  mandatory on BOTH paths" — sits directly BELOW the `/goal` line and above the remaining-work
  bullets: an active `/goal` keeps the first line, the quote never displaces it, and with no active
  `/goal` the quote itself opens the block.

Full-path shape (minimum form — live: bare `─` rails, no fence; shown inside a fence here for
display):

```text
`/clear`, then copy everything between the dashed lines:

──────────────────────────────────────────────────────────
Read @<handoffs-dir>/<TS>-handoff-<topic>.md, confirm its Original goal still governs the remaining next steps, then continue them.
Prior session: <UUID>.
Handoff origin: <repo-identity>, relative path <memory_dir>/handoffs/<TS>-handoff-<topic>.md.
──────────────────────────────────────────────────────────
```

### The directive path is ROOTED, and that is the whole point

`<handoffs-dir>` is the **absolute** path of the directory the write step actually used — the
resolved `<memory_dir>/handoffs/` (default `.work/handoffs/`) with the root it hangs off rendered
in front of it. Never emit a default the file was not written to, and never emit the relative
segment alone.

A rootless `@.work/handoffs/…` resolves against the *resuming* session's cwd, which is not
guaranteed to be the root of the repository the work happened in — the producer may have written
into a repo that is not cwd's project root, and the resuming session may sit in a subdirectory of
the right repo or in a different repo entirely. When the wrong root happens to contain its own
`.work/handoffs/`, the failure presents as "the file is missing" rather than "the path has no
root", which is the most expensive shape to diagnose. Rooting the path removes the resolution step
that can be wrong. This is the same answer the binding already gives on its no-project-root branch,
where handoffs land under `${CLAUDE_PLUGIN_DATA}/topic-docs/handoffs/` "with the absolute path
announced prominently" ([`topic-docs.md`](topic-docs.md)) — absolute is already what this engine
does wherever a relative path has no anchor.

**Render it forward-slash normalized** — `/home/<user>/src/<repo>/.work/handoffs/…` on a POSIX
host, `D:/repos/<owner>/<repo>/.work/handoffs/…` on Windows — never with backslashes: the directive
survives into transcript JSONL, where a backslash is escaped again, and `find-handoff` greps that
record.

**The `@` is an accelerator, not the mechanism.** Official docs state an `@` reference's path "can
be relative or absolute"
(<https://code.claude.com/docs/en/common-workflows#reference-files-and-directories>), and expansion
pre-loads the file. They document no drive-letter or whitespace-bearing form, so treat expansion as
unverified for those: the same line states the absolute path in full either way, and a resuming
session that sees no expanded content reads the path directly. Write the directive so it is
actionable without expansion — that is what makes rooting a strict improvement over the rootless
form rather than a trade.

**`<repo-identity>` keeps the prompt usable off this machine.** An absolute path is machine-local,
and a save-point's own "When to invoke" includes sharing state with another machine — so the third
line names what the path can be re-derived from: the repository's `origin` remote URL when it has one
AND that URL can be sanitized with confidence (the test is below), else its root directory name, and
the repo-relative path under it. It is computed at emit time
from the repository actually written into — when cwd is NOT that repository, name the repository the
file was actually written to, never the one cwd happens to sit in; it is NOT a stored field, and
nothing in the handoff file's frontmatter carries it. A resume on a different machine or checkout
ignores line 1's root and re-resolves from line 3.

**Strip the remote URL's userinfo before embedding it.** A remote URL routinely carries a credential
in its userinfo component — `https://<token>@github.com/<owner>/<repo>.git` for HTTPS-with-PAT,
`https://<user>:<token>@host/…` for a stored password, and the `x-access-token:<token>@` form a
credential helper writes — and this line sits INSIDE the rails, in the region the operator is told
to copy, so an embedded credential travels into the next session and onto every machine the prompt
is forwarded to. Take `git remote get-url origin` and remove the credential-bearing userinfo —
everything from `://` up to and including the `@` — before embedding what is left, so a PAT-bearing
remote is emitted as `https://github.com/<owner>/<repo>.git`. The redaction pass is the backstop, not
the mechanism: it is a model-driven sweep that can read a bare token as just another path segment,
and a credential never put into the string cannot be missed.

**A bare ssh account name is not a credential.** `ssh://git@github.com/<owner>/<repo>.git` carries no
secret — the secret is the local key, which the URL does not contain — so the `git@` stays. Strip
userinfo that carries a token or a password; leave userinfo that is only a well-known ssh account
name. Dropping it would not hurt recovery, but it would state something false about the remote.

**"Cannot be sanitized with confidence" has a test: can you say where the userinfo ends and the host
begins?** Fall back to the root directory name when you cannot. Concretely: more than one `@` sits
ahead of the path, so the boundary is ambiguous; there is no `://` to anchor on, as in the SCP-style
`git@host:<owner>/<repo>.git` form, where the `@` delimits an ssh user and no scheme marks where
stripping would begin; or the string is not a shape you recognize. Guessing the boundary risks
leaving the token in or mangling the identity — the directory name loses neither, and it re-resolves
nearly as well.

When the next stage is a specific skill in the consuming repo, swap the directive to
`Read @…, confirm its Original goal still governs the remaining next steps, then execute /<skill>.`
The `@`-reference is mandatory on the full path — the fresh session
loads it; do NOT inline the file's detail in the prompt. Prompt-only carries its remaining-work
bullets inline between the rails instead, and needs no origin line: it references no file.

**The alignment clause rides in the directive because the directive is the one thing every resume
path passes through.** The dominant resume is a paste into a fresh session that invokes no skill at
all, so a check living only in a skill fires only when someone happens to call it — which is how a
chain of save-points can run for many sessions with nothing ever testing the work against its goal.
`/session-flow:keep-going` owns the same check on the skill-mediated path (its goal-alignment
step, which gates its recovery actions); this covers the bare paste, the background agent
`/session-flow:continue-in-background` launches, and a `find-handoff` recovery alike. It is not a
detection-contract change: signal 1 below is matched on the `…handoffs/<TS>-handoff-…` shape the
directive names, which the added clause leaves untouched.

`<UUID>` = this session's `$CLAUDE_CODE_SESSION_ID` (the frontmatter `session_id`) — it lets a
fresh session or `/session-flow:retro` chain-walker locate the transcript later.

After the rails prompt is emitted, control returns to the citing skill's delivery step.

## Detection contract — consumed by `/session-flow:find-handoff`

The output shape above is a **stable detection contract**, not merely a display convention:
`/session-flow:find-handoff` keys off it to recover a handoff whose resume prompt was written but
never copied (operator ran `/clear` before copying it). The load-bearing signals, in precision
order, are (1) the `Read @…-handoff-*.md` directive — the exact path to recover, for a file-based
handoff; (2) the two `─` (U+2500) rails plus the `` `/clear`, then copy everything between the
dashed lines `` instruction line — the primary key for a prompt-only handoff, which writes no file;
and (3) the `Prior session: <UUID>` line, which — together with the `type: handoff` frontmatter
([`structure.md`](structure.md)) — pins the session chain; it is emitted by the file-mode shape
but is not required of prompt-only output, so consumers treat it as corroboration, never a
required key.

**Signal 1 carries a rooted path now, and a consumer must still accept the rootless form.** Every
handoff emitted before this rule shipped states a repo-relative path, and those files and
transcripts are on disk unchanged — a detector that recognizes only rooted directives stops
recovering the entire existing corpus. So the directive is matched on its `…handoffs/<TS>-handoff-…`
shape, and the two forms diverge only at the existence check: a rooted path is checked as given,
while a rootless one keeps the old rule of resolving against the SOURCE transcript's `cwd`. That
resolution is inference — the producer's cwd is not necessarily the repository it wrote into, which
is exactly the defect rooting removes — so a rootless candidate whose file is not found is
**UNRESOLVED, never discarded**: dropping it is what made the recovery ladder unable to recover the
failure it was written for.

The `Handoff origin:` line is a **resolution input, not a detection signal** — it cannot admit or
reject a candidate, so it is neither a fourth key nor the conditional slot the `/loop` re-arm note
holds below. A consumer reads it only after a candidate has qualified, at the existence check: when
the ROOTED path does not exist on this machine — a resume on another machine or another checkout,
which is the one failure mode absolute paths have and relative ones do not — the line names the
repository and repo-relative path to re-resolve from. **A rooted path that is not found is therefore
the same not-found-here condition as a rootless one that does not resolve, and gets the same
UNRESOLVED treatment**; a consumer that reports it as a missing file reintroduces the defect on the
new path. The line is emitted by the file-mode shape only and only from this version on, so its
absence disqualifies nothing: prompt-only never emits it, and no handoff written before this has it.

**The recoverable unit is the rails prompt PLUS every below-rail `/loop` re-arm message.** Every other
element of a resume prompt sits between the rails, so recovering the copy region recovers the whole
contract — `/goal` included, since it is the first line inside the block. The `/loop` re-arm is the
one exception, and not by choice: a command is recognized only at a message's start
(<https://code.claude.com/docs/en/commands>), so the re-arm must be its own message and therefore
lives below the bottom rail, outside the copy region. A recovery that surfaces only the block
between the rails hands back a continuation that runs once and drops the recurring behavior — the
exact failure the re-arm rule exists to prevent, reintroduced one layer down. So the re-arm note
that directly follows the bottom rail is part of what a recovery must surface, not commentary it may
discard. Nor is one of them enough: the rule above emits one re-arm message per loop left standing,
so the recoverable unit is however many the producer wrote, and a consumer that stops at the first
loses the rest exactly as quietly.

Each entry is recovered by its `Re-arm <i> of <n> — <L> lines:` header and the `<L>` body lines that
follow it — **a length boundary, never a wording match**. The entry carries the operator's original
prompt verbatim, so any content test can be defeated by the content: matching the note's wording
truncates a prompt whose continuation lines do not resemble a re-arm, and matching a marker fails on
a prompt that quotes the marker. A count cannot collide with what it delimits. `<n>` is the
self-check that the whole set came back, not the scanner. The verbatim prompt also means the same
redaction pass applies here as to everything else surfaced from a transcript.

Changing this prompt/marker format — the rails, the header, or the meaning of `<L>` — is a
**knowing** break of that contract, not a cosmetic edit; update `find-handoff`'s detection in the
same change.
