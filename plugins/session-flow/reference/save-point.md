# Save-point engine: produce the save-point and the resume prompt

## Contents

- [Where save-points live](#where-save-points-live)
- [Locate the position first](#locate-the-position-first)
- [Choosing the path: full save-point vs prompt-only](#choosing-the-path-full-save-point-vs-prompt-only)
- [Urgent handoff](#urgent-handoff)
- [Redaction pass, mandatory on both paths](#redaction-pass-mandatory-on-both-paths)
- [Claim provenance, mandatory on both paths](#claim-provenance-mandatory-on-both-paths)
- [Original goal, mandatory on both paths](#original-goal-mandatory-on-both-paths)
- [The purpose argument tailors emphasis only](#the-purpose-argument-tailors-emphasis-only)
- [Writing the handoff file (full path)](#writing-the-handoff-file-full-path)
- [Emit the position panel](#emit-the-position-panel)
- [Emit the copy/paste resume prompt](#emit-the-copypaste-resume-prompt)
- [Markdown surfaces](#markdown-surfaces)
- [Detection contract, consumed by `/session-flow:find-handoff`](#detection-contract-consumed-by-session-flowfind-handoff)

Shared by `/session-flow:handoff` and `/session-flow:continue-in-background`. This document owns
delivery-agnostic machinery: locating the position, choosing the path, producing the (redacted)
save-point, and emitting the rails resume prompt. The citing skill owns everything after the rails
prompt: its delivery step (`/clear`-then-paste, a background-agent launch, or, where this session
can start another session, a sibling session per [sibling-session-delivery.md](sibling-session-delivery.md))
and its own STOP semantics. Neither skill restates this content; both walk it in order.

## Where save-points live

Save-points are memory-tier, concern-scoped by session. A consumer-declared `memory_dir` (a
working-docs convention in `CLAUDE.md` / `.claude/rules/`) wins as the memory-tier root; save-points always live
at **`<memory_dir>/handoffs/`** (default `.work/handoffs/`), in files named `<TS>-handoff-<topic>.md`
with `TS = date -u +%Y%m%dT%H%M%SZ` (ISO basic, Windows-safe, sortable). A shape-3 hop also
writes one archive file under `<memory_dir>/handoffs/archive/` (structure doc, "Shape 3"), which
is handoff state like the handoff file and is never globbed as a save-point. On the session's first
memory-tier write, verify the resolved memory root's `.gitignore` exists and contains `*`, creating
it (announced) when absent; never edit the consumer's root `.gitignore`.

**Worktree caveat.** A save-point written inside a `git worktree` checkout resolves its memory
root within that worktree, so the handoff file lives there, and dies with `git worktree remove`.
Acceptable only when the worktree completes as a merged PR unit: the work is durable in merged
history by the time the worktree goes. When pausing un-merged worktree work, write the handoff
from the main checkout, or rely on `/session-flow:clean-stop`'s preserve-before-remove step.
Before removing a worktree it inspects ignored content a plain `git status` hides
(`git status --ignored`) and preserves or surfaces anything not reproducible, generated handoff
data included.

## Locate the position first

Before emitting anything, establish where the work stands: if a plan or checklist artifact backs
the work (see the sibling `workflow` skill), read it this turn and name the next unfinished stage.
The resume prompt points at the next stage, not just "continue here". Ground every status claim in
a fresh read, never a prior session's assertion. With no plan artifact, name the next concrete
action from the conversation.

## Choosing the path: full save-point vs prompt-only

**A resume prompt is always emitted.** The only decision is whether to also write a durable handoff
file. Full save-point = prompt + handoff file (the prompt `@`-references the file). Prompt-only
carries its detail inline. A [new-session launch](structure.md#new-session-launch) uses a prompt
file on either path.

**Default: write the file.** Skip it only when no plan artifact backs the work and all of these
clearly hold:

- Remaining follow-ups fit as a short bullet list in the prompt
- The work is straightforward, not exploratory
- No abandoned approaches or hard-won findings worth preserving
- No consequential decision + rationale a future session must not rediscover
- No non-trivial task list to reconstitute
- No invariant a resuming session could violate without noticing
- No side effect already applied that a fresh session would otherwise repeat

The last two are the sharpest: a short, straightforward remainder is the shape that passes every
other test, and "the migration is already applied, do not re-run" is the fact a prompt-only
bullet list drops. A single one of them forces the full path.

**Tracker short form (`/session-flow:handoff` only).** When a tracker item already holds every
finding, decision and remaining action, and no session state is left to carry, the handoff skill
emits a two-line resume naming the item's URL instead of either path, even when a plan artifact
backs the work; eligibility and shape are in that skill's `reference/tracker-short-form.md`. It is
still the resume prompt, so the rule above holds. Findings not yet on the tracker take the full
path.

Any doubt → full save-point. A wrongly-skipped file loses state the fresh session must rediscover;
a wrongly-written one costs nothing. An explicit method argument overrides auto-detect, but
`prompt` leaves a gap in the session-id chain that `/session-flow:retro` walks (no file, no chain
pointer).

## Urgent handoff

When the [handoff skill selects its urgent path](../skills/handoff/SKILL.md#urgent-path),
use the full file path in the same turn. The normal file guards and refusal paths still apply.

1. Apply the [redaction pass](#redaction-pass-mandatory-on-both-paths) before each write or emit.
   Run `new`. Record running work and its dependencies in Environment without waiting. List each
   named subagent as `not inspected (urgent)`. Skip subagent output reads and optional profile
   checks. A new-session launch still uses its selected profile's command. Record
   `wip_commit: not applied (urgent)` in the file.
2. Apply the slots in one `fill`, including Reminders, Environment and its recurring entries,
   and the next session's `Next:` actions. On PASS or WARN, paste the rails `fill` returns.
3. On a repairable FAIL, make one repair and run `validate`. If the file still fails, show only
   `UNVALIDATED: <first failing line>` immediately above the copy instruction, outside the copy
   region. Emit the stored rails even on failure. On every verdict, skip the position panel and
   checklist echo and end with the resume prompt.

## Redaction pass, mandatory on both paths

Before writing the handoff file or emitting the resume prompt, sweep everything outbound
for secrets, API keys, tokens, credentials, connection strings, and PII, and redact each hit with
a shape marker (`<REDACTED: API key>`), never the value. Outbound means the body
sections, the TaskList snapshot, the frontmatter, the position panel, and the prompt between the
rails. Save-point output outlives the session: it
sits on disk uncommitted-but-readable, travels to other sessions and machines, and gets read in
contexts the current conversation never anticipated. A value acceptable to see in-session is not
acceptable to persist. This pass gates the write: no artifact or prompt is emitted before it runs.

**Git remote URLs are a named vector on that list, and they take a different treatment.** A remote
embeds its credential in the URL's userinfo component (`https://<token>@host/…`), where it reads as
one more path segment rather than as a secret, the shape this sweep is likeliest to walk past. So
every **git remote** URL in the outbound set is checked for an `@` ahead of its host. **Drop the
userinfo and keep the rest. Do not replace the URL with a shape marker. This is a deliberate
exception to the rule above, and it wins for git remote URLs and nothing else.** The general rule
redacts to a marker because the whole value is secret and nothing downstream needs it; here the
opposite holds. The scheme, host, and path are not secret, and recovery needs them:
`Handoff origin:` exists so a resume on another machine can re-resolve the file from the repository it
names, and a `<REDACTED: remote URL>` marker would destroy the identity the line is emitted to carry,
turning a credential leak into a broken recovery. So
`https://<token>@github.com/<owner>/<repo>.git` becomes `https://github.com/<owner>/<repo>.git`,
never a marker. `Handoff origin:` is where such a URL most plausibly appears, and it sits inside the
copy region; `<repo-identity>` below requires it stripped at emit time so this pass has nothing left
to catch.

**The exception does not generalize to other credential-bearing URLs.** A connection string such as
`mongodb+srv://<user>:<secret>@<host>/<db>` keeps the general treatment: a shape marker
(`<REDACTED: database connection string>`), not a host-preserving strip. What earns a git remote URL
its exception is that something downstream re-resolves from the surviving host and path; nothing
re-resolves from a database host, so preserving it discloses infrastructure for no recovery benefit.
Strip-and-keep applies where something downstream needs the remainder; everywhere else the marker
still wins.

## Claim provenance, mandatory on both paths

A status claim earns plain statement only when this session verified it: a command run, a file
read, an output observed. Anything inherited, whether a prior handoff's assertion, an issue label,
or a remembered state, carries an explicit `UNVERIFIED (<source>)` marker instead: the resuming session
treats an unmarked claim as fact and builds on it, so an inherited claim is a claim to falsify, not
a fact to forward.

**Verified is not CI-green.** A pushed commit, a "CI is running" observation, or a local test
pass is not a green check. A fix still in CI, merge, or another unreturned check is
`UNVERIFIED (<check>)`, naming the run id, job name, or PR check, never plain "the fix" or
"verified". When the check returns after emit and before `/clear`, `save_point.py amend` folds
its result into the handoff (structure doc, "Shape 3"); one that returns after `/clear` reaches
no handoff, so a pending check written as fact stays wrong. A pending-verification field in the shape is parked:
[`skills/handoff/reference/pending-ci-caveat.md`](../skills/handoff/reference/pending-ci-caveat.md).

This governs both paths, not just the full path's body sections. On the full path it shows up
throughout [`structure.md`](structure.md), most visibly the met/unmet marks in Completion criteria.
Prompt-only writes no body sections, so the marker attaches directly to whichever inline
remaining-work bullet carries the inherited status; a bullet that folds in an inherited "done" or
"blocked" without `UNVERIFIED (<source>)` reproduces the exact failure this rule exists to prevent,
with no file left behind for a later review to catch it in.

**Write history, not the present.** A claim about code or state that a save-point keeps (the
resumption brief, Observations, Decisions in force, a cumulative entry) carries, in its own text,
the date it was true and, for code, the commit it was true at: `2026-11-24: …`, `as of
owner/repo@<sha>, …`. Never a bare "currently", "now" or "is" about code or state: entries are
carried across hops, and an undated present tense reads as true on every later one. When a fact
changes, write a new dated claim and supersede the old one through its section's own mechanism (a
`Superseded:` line or the `retire` list, structure doc), never by editing it.

## Original goal, mandatory on both paths

The goal in the user's own words travels with every save-point, and a chain of them carries it
forward unchanged. A save-point serializes the machinery in front of it: the phase, the
checklist, the bundle. It then hands the resuming session a mission made of process, which that
session then optimizes faithfully. State is what a save-point preserves for free; intent is what it
drops in silence, and no amount of detail elsewhere replaces it.

On the full path this is body section 1, `Original goal` ([`structure.md`](structure.md)), which
also owns the immutability rule and the disk-read copy step a successor handoff runs.
**Prompt-only writes no body sections, so it carries the verbatim goal inline between the rails**,
above its remaining-work bullets. It has no file to point at, and a prompt-only save-point listing
only the follow-ups is the exact shape that loses the goal.

**Amendments travel too.** A bare single goal line is valid only while the goal has no recorded
amendment (`Amended: None.` on the full path). Once an amendment exists, the prompt-only form
carries the original dated quote plus every dated amendment, compact, one line each,
`amended <date>: "<verbatim quote>"` under the original, still verbatim, still copied unchanged on
later hops. The full path preserves that history in §1's `Amended:` field; a prompt-only hop that
collapses it back to a single line discards the record of what the goal was and when it stopped
being that, which no later full-path handoff can reconstruct.

## The purpose argument tailors emphasis only

A citing skill may hand the engine optional trailing purpose text, the invocation's statement of
the next session's intended work (the producer's `[file|prompt] [topic] [purpose...]`
surface, parsed from `$ARGUMENTS`). When present, purpose tailors **emphasis only**, in exactly
three places:

- The **Resumption brief** leads with it: `new --purpose <text>` writes it as the brief's first
  line, `Purpose: <text>`, and the brief's framing opens from it, still inside its six-line cap.
- **Suggested skills** are selected for it: the skills recommended are the ones serving that use,
  each still tied to a concrete remaining item.
- **Remaining actions** are ordered by it, among actions whose order is otherwise free; a genuine
  sequencing dependency still binds, purpose never licenses running an action before one it
  depends on.

**Prompt-only carries the purpose inline. Never discard it.** The three surfaces above are
full-path sections, and prompt-only writes none of them; its delivery can also hand the rails
block to a background agent as the only thing that agent ever sees. So on prompt-only, a stated
purpose travels between the rails as a single `Purpose: <text>` line directly below the goal
quote (and its dated amendment lines, when present) and above the remaining-work bullets, on the
same travels-in-the-prompt-or-not-at-all rationale the Original goal rule above states. The
inline bullets are still ordered by it where ordering is free, but ordering alone cannot carry
it, since with one action left it expresses nothing, so the line is the carrier, not a fallback.
This is content between the rails, not a shape change: every detection-contract signal below
(the rails, the copy-instruction line, the `Read @…` directive, the `Prior session:` line) is
untouched.

What purpose may never do:

- It never drops, renames, or reorders the mandatory section set ([`structure.md`](structure.md)'s
  ordered body sections). The structure is the anti-drift contract; every section is still present,
  and one with nothing purpose-relevant to say still says so.
- It never alters the emitted resume-prompt shape: the rails, the directive, the origin line, the
  re-arm notes. That shape is the detection contract below; changing it for a purpose would be a
  knowing contract break requiring a coordinated `find-handoff` change, which passing a purpose is
  not.
- It never amends the Original goal. A purpose that contradicts the goal is **flagged at write
  time, not silently obeyed**: say plainly that the stated purpose does not serve the recorded
  goal and ask whether the goal has changed. The goal moves only by the explicit dated amendment
  the structure doc's `Amended:` field records, never because a purpose pointed elsewhere.

Absent purpose text, nothing in this section applies.

## Writing the handoff file (full path)

The body sections, the TaskList reconstitute format, and the frontmatter shape (including the
`session_id` and `previous_handoff` chain fields that `/session-flow:retro` walks) live in
[`${CLAUDE_PLUGIN_ROOT}/reference/structure.md`](${CLAUDE_PLUGIN_ROOT}/reference/structure.md).
Walk it while writing the file; never write the section list from memory.

**The file is a handoff file plus its archive file, and a script owns its deterministic tier.** This
flow describes the shape `new` writes by default, shape 5.
`${CLAUDE_PLUGIN_ROOT}/scripts/save_point.py` has five subcommands, run through the interpreter
ladder the structure doc's write procedure shows (`"$PY" -X utf8 …`, Python 3.10+, stdlib only):

- `save_point.py memory-root` is read-only and prints the memory root `new` uses when
  `--memory-dir` is omitted: `.work` under the git top level; outside a git work tree,
  `<plugin data>/artifacts`. When neither exists, `new` refuses and asks for `--memory-dir`.
- `save_point.py new --topic <slug> [--memory-dir <root>] [--purpose <text>] (--previous <file> | --no-previous)`
  writes the skeleton with every deterministic field filled (filename and `date:`, `session_id`
  from `CLAUDE_CODE_SESSION_ID`, the resolved `transcript:`, `previous_handoff` and the chain
  position keys, the headings in order, what it carries off the predecessor, the last
  `## Prior sessions` rows, and the whole `## Resume prompt` block except its `Next:` headlines),
  writes this hop's archive file with the predecessor's other sections verbatim, and prints the
  handoff file's absolute forward-slash path. It also prints a `budget:` line on stderr:
  write the slot values to it. Only the `<!-- FILL: <name> — <instruction> -->` slots are the
  model's, and `fill` is what applies them. It never overwrites an existing handoff; it rewrites an archive file only when a retry
  of the same session writes it again. `--shape 2` writes the shape-2 single file instead (the eval and
  projection harnesses build shape-2 chains with it); it refuses a shape-3 predecessor.
- `save_point.py fill <file> --slots <json>` replaces every slot in the file from one JSON object
  keyed by slot name, in a single write. An inline prefix on a slot's line (`**Amended:**`,
  `**Next action serves it by:**`, `did:`, the `left:` separator) is preserved; a multi-line value
  is one JSON string with escaped newlines and lands as those lines in place, each taking the
  file's own line terminator; an optional slot (`goal-first`, `goal-after`, `below-rail`,
  `<section>-new`) left out of the object has its line deleted. Every refusal names the slot or key
  and what to change, and leaves the file byte-identical, so nothing is ever half-applied. It
  fits the handoff file to the cap itself and prints the verdict and the `emit` output. The
  slots JSON lives beside the handoff as `<same stem>.slots.json` and is left in place. `fill`
  never judges a value against its slot's instruction; `validate` is the gate.
- `save_point.py validate <file>` prints PASS/WARN/FAIL lines and exits 0 on pass (shape 1: one
  WARN, exit 0), 1 on a validation failure, 2 on usage, 3 on a `handoff_shape` newer than it
  knows ("read it, do not rewrite it"). A leftover `FILL` slot, a prefixed `previous_handoff`, a
  non-UUID `session_id`, a stated `transcript:` that does not exist, a heading out of order, a
  non-U+2500 rail, more than five `Next:` lines, a `|` in the `did: … · left: …` line, and a
  dropped predecessor entry are all failures. `--strict-transcript` turns the honest
  `unresolved (…)` transcript from WARN into FAIL (the acceptance harness passes it). It also runs
  a WARN-only secret-shape scan; the model rules on each hit under the redaction pass above. On a
  shape-3, shape-4 or shape-5 file it also checks the carry against the predecessor and both archive files, and
  the size; each FAIL line names the fix.
- `save_point.py emit <file>` prints the `## Resume prompt` section body verbatim (heading
  excluded, leading and trailing blank lines trimmed) and exits 1 on a shape-1 file (no section,
  says so) or a file that still carries a `FILL` slot (an unfinished skeleton is never emitted).
  A shape-3 file over the Read page cap still emits, with a `FAIL:` notice on stderr.
  When the stored `Read @` path is not the file's own real path (a file preserved out of a removed
  worktree) it warns on stderr and substitutes the current path on stdout only; the file is never
  rewritten.
- `save_point.py amend <file> --json <path>` folds an event that arrives after emit into a
  filled shape-3, shape-4 or shape-5 tip file. The JSON object takes any of `sections` (`{title: body}`, replacing
  written sections), `append` (`{title: [lines]}`, adding lines to Original goal or Direction
  changes), `retire` (`[{ref, reason}]`, as `fill` takes it), `next` (new `Next:` lines) and
  `floors` (raising id floors only). It appends what it replaces to this hop's file, validates
  before it writes, prints the verdict and then the `emit` output, and never blocks on a size
  finding. It refuses a no-op, a carried section other than `Next:`, an unfilled skeleton and a
  file that is not the chain's tip (naming the successor's `amend` command); `amend --help` lists
  the keys. Same-session `new` refuses to rewrite an archive file that holds amended or retired
  content, so `amend` is the only way to fold a late event in. On a role chain, `fill` and
  `amend` also write the standing-rules file and the retired-entries index
  (structure.md, "Role chains: the standing-rules file" and "The retired-entries index").

The rails on screen are the `emit` output, so the file is validated before the prompt exists on
screen and the two cannot disagree ("Emit the copy/paste resume prompt", full-path block).

`new` never overwrites, so there is no "extend an earlier turn's write" path: a skeleton that an
earlier turn left unfinished (compaction mid-fill) stays on disk carrying `FILL` slots, is never
emitted, and a fresh `new` writes a new timestamped file beside it. Legacy shape-1 files are read
and never rewritten. The script is read-only on the repository except the handoff file and archive
file it creates; the self-ignore guard is the skill's own bash step (structure doc), which `new` verifies
and refuses without.

## Emit the position panel

An [urgent handoff](#urgent-handoff) skips this section.

A save-point is written for the next session, but a human reads the turn that produces it, and at
that moment they decide two things the save-point never tells them: whether this is a sane place
to stop, and whether the work is still pointed where they wanted it. Everything needed to answer
both was already established by "Locate the position first" and the sections above; without this
step it is all filed into the handoff document, whose stated reader is a session with no prior
context, and on prompt-only it is written down nowhere. The panel renders that state for the
operator.

**It restates; it never discovers.** Every line comes from what this turn already established. A
fact not good enough for the file is not good enough here, and the panel never triggers a read the
save-point did not already need. That separates it from `/session-flow:orient`, which sweeps
durable and off-thread state on demand; this is the free exit-side view.

**One call is exempt, and only one:** the `TaskList` fetch a forced prompt-only save-point never
made (unit ladder, rung 4), in a session that has the task tools. It reads the session's own task ledger rather than the world outside
the conversation, so it cannot turn the panel into an orientation sweep, which is the thing this
rule exists to prevent. Nothing else is exempt: no `gh`, no ledger re-read, no artifact this turn
has not already opened.

**Shape: a vertical rail, one unit per line:**

```text
**You are here**

  [x] Phase 1: discovery
  [x] Phase 2: engine
▸ [~] Phase 3: wiring            you are here
  [ ] Phase 4: evals
  [ ] Phase 5: docs

2 of 5 phases complete · completion criteria 4/7 met (2 UNVERIFIED)

Done this session: retry wrapper landed and green (a1b2c3d); OrderWriter stub does not compile yet.
Where we are: mid Phase 3, blocked on that stub.
Up next: finish the cancellation pass-through, then Phase 3 edge-case tests (§11 owns the rest).
```

**Every line stands alone. Nothing wraps.** One unit per line, and each of the three blocks is a
single line. When a line runs long, tighten the wording; never continue it onto an indented second
line. The rail is vertical rather than a `→`-chained row because a horizontal rail wraps at
whatever width the terminal happens to be, and the wrap orphans the position marker from the unit
it marks, destroying the one thing the panel exists to show.

Status glyphs are the ones [`structure.md`](structure.md) already uses for the TaskList snapshot
(`[x]` completed, `[~]` in progress, `[ ]` pending, `[!]` blocked), so a reader who has seen a
handoff file needs no legend. The `▸` gutter marker and the trailing `you are here` label are the
only additions.

**Above 8 units the middle elides; the panel never scrolls.** Keep the first two units, the current
unit with one neighbor either side, and the last one, replacing each dropped run with a `… N more`
line. A map keeps its ends and its "you are here" and drops the middle, readable at a glance. A
rail long enough to scroll is one the operator will not read.

The whole panel is capped at 16 lines, blocks included.

**The count is of completed units, and an in-progress unit is not one.** The example above reads
`2 of 5` with a `[~]` third phase for that reason: `[~]`, `[ ]`, and `[!]` all count against the
total, and only `[x]` counts toward it. Rounding the current unit up is the one arithmetic a
progress read is most tempted into and least allowed. It reports work as landed while the operator
is looking at the line that says it is not.

### Resolving the units

Units are whatever this work is actually divided into, which is why the panel reads differently on
different tasks. Take the first that applies, and name the unit kind in the rail so the operator
knows what they are looking at:

1. Workflow-checklist stages: the stage ledger at `<memory_dir>/<slug>/` the sibling `workflow`
   skill maintains.
2. Phases named by a backing plan, spec, or PRD: the artifact "Locate the position first" already
   read this turn.
3. An issue chain: the parent work-item and its sub-issues.
4. Live `TaskList` items, **full path only, where they are already fetched** for
   [`structure.md`](structure.md)'s `Environment to re-establish`, so the panel spends nothing on
   them. Prompt-only walks no body sections and so makes no such call: skip this rung there and
   fall through to 5. That costs almost nothing, because "no non-trivial task list to reconstitute"
   is one of the criteria that selects prompt-only in the first place ("Choosing the path"). A
   session with a task list worth drawing was supposed to be on the full path. When prompt-only was
   forced by the explicit `prompt` argument, so that criterion was never tested, make the one
   `TaskList` call rather than guessing from the conversation. A session with `TodoWrite` instead
   reads the list from its latest `TodoWrite` call; one with neither has no live list on either
   path: skip to 5 (structure.md's tool-presence branch).
5. Completion criteria, as the units of last resort.
6. **None of the above: emit no rail.** Give the three blocks as prose and say plainly that the
   work has no delineated units. **Never invent phases to have something to draw.** A fabricated
   rail reads as a plan that exists, and the operator will resume against it.

### Rules the panel inherits

- **Claim provenance** ("Claim provenance, mandatory on both paths") governs it. An inherited
  status carries its `UNVERIFIED (<source>)` marker, and the completeness line says how many of its
  marks are unverified. A bare count reads as measured when it is partly remembered.
- **Redaction** ("Redaction pass, mandatory on both paths") sweeps it with everything else
  outbound. The panel is screen output, and screen output is copied, pasted, and screenshotted.
- **Divergence is surfaced, not resolved.** Where the rail and the durable record disagree, say so
  in one line and point at `/session-flow:reanchor`; do not pick a side inside the panel.

### The panel never gates the rails prompt

If the units will not resolve, a count cannot be grounded, or anything else about the panel is
uncertain, emit an abbreviated panel, or none, saying so in a line, and continue immediately to
the rest of the response. The panel is a courtesy; the rails prompt is the deliverable, and the one
observed failure mode of this whole engine is a turn that ends before that prompt reaches the screen
(the citing skill's gotchas). Nothing added here may become a new reason to reach that ending.

Where the panel sits in the response belongs to the citing skill, which owns its own output order.

## Emit the copy/paste resume prompt

**Copy-region clarity (both paths), dashed rails per region, no fence:**

- Each region sits between two full-width `─` (U+2500) rails: top rail, text, bottom rail. Use
  literal `─`, not markdown `---` (turns the adjacent line into a heading) and not a code fence
  (the user copies the text between the rails, not fence markers). This is the terminal's form and
  the form the file stores; a surface that renders markdown prints it differently ("Markdown
  surfaces").
- The only thing between a region's rails is its text, with no labels and no padding lines.
  Commentary sits above the top rail or below the bottom rail, never between.
- One plain-language instruction sits directly above each region's top rail. The resume region's is
  "`/clear`, then copy everything between the dashed lines:". A goal region has its own, below.
  For a [new-session launch](structure.md#new-session-launch), show the terminal command above
  both copy regions. It supplies the initial prompt in one paste. The copy lines stay available
  for recovery. If the checkout is missing, report the launch error.
- **Goal region:** when a goal applies, the prompt holds a second railed region for it, unless
  the condition check below omits it. A goal
  applies when the user asked for a fresh goal, or when a `/goal` is active in the producing
  session. Active means a `/goal` establishing or re-arming call earlier in this conversation with
  no later stop/completion, not "infer from conversation" prose; `/clear` destroys an active goal,
  so this region is how the next session gets it back. With no goal, the prompt is the single
  resume region and nothing in this bullet applies.

  The region, top to bottom:

  1. The fixed instruction line, on one line: ``Type `/goal ` (with a trailing space), then paste
     everything between the dashed lines. Confirm the `◎ /goal active` indicator appears after you
     send it; if it is missing, redo it:``
  2. The top rail.
  3. The goal's condition text, verbatim from the `/goal` call or the user's request. No line
     between any rails starts with `/goal`: the user types the command, and the region holds the
     condition only.
  4. Full path: the resume region's `Read @…` directive line, byte for byte. Setting a goal starts
     a turn at once with the condition as the directive, so the goal paste has to carry the resume
     pointer itself. Prompt-only: the verbatim goal quote with its dated amendment lines
     ("Original goal, mandatory on both paths") in its place, since there is no file to point at
     and so no `Read @` line.
  5. The bottom rail.

  Everything between the goal region's rails, lines joined by newlines, stays within the documented
  condition limit. Over it, shorten the condition text; the directive line stays whole. Record:
  the claims are that a condition holds up to 4,000 characters, that setting a goal starts a turn
  at once with the condition as the directive, and that a `◎ /goal active` indicator shows while it
  is active; basis <https://code.claude.com/docs/en/goal#write-an-effective-condition> ("The
  condition can be up to 4,000 characters") and <https://code.claude.com/docs/en/goal#set-a-goal>
  ("Setting a goal starts a turn immediately, with the condition itself as the directive"; the
  `◎ /goal active` indicator); as of 2026-10-18; recheck when either section changes the limit,
  the start-a-turn behavior, or the indicator text. This is the one place the limit is stated.

  **Check the condition before emitting the region.** The goal evaluator does not call tools, so
  it judges only what the conversation shows, and the next session's conversation holds none of
  this one's output. Two checks follow, on both paths:

  1. **Conversation-bound wording.** When the condition ties its proof to the producing
     conversation ("in the transcript", "in this conversation", "shown by output you produced",
     "output you produced", or a close variant), put a warning line above the goal region's
     instruction line; on the full path it goes in the `goal-first` or `goal-after` slot value
     directly above the fixed goal instruction line, so `emit` prints it. In `goal-first` it is
     the value's first line; in `goal-after` it comes after the value's leading newline, so the
     blank line below the resume region's bottom rail stays. It says the next session must re-produce every earlier proof before the
     goal can be met, and suggests rewording the proof as "at commit `<sha>` or in
     `<evidence file>`, shown in the conversation", with this session's commit or evidence file
     filled in. The condition between the rails stays verbatim; a rewrite goes in only when the
     user approves it, since only the person arms a goal.
  2. **Nothing left but the user's decisions.** When every criterion in the condition is met,
     each at a commit SHA or file path this save-point records, and every remaining action is a
     decision only the user can make, omit the goal region. Below the resume region's bottom rail,
     say the goal region was left out because its criteria are met at the recorded commit or file,
     and list the pending decisions. A criterion met only by this session's say-so, or one that
     still needs a command run, keeps the region.

  **A flagged goal is re-drafted at resume, never armed by the model.** When check 1 fires on the
  full path, also make the first remaining action `Re-draft the carried /goal condition: <reason>`.
  The resumed session drafts a new condition with `/planning:draft-goal-condition` (if enabled;
  otherwise it states the reason and a suggested rewording), offers it once in its first reply and
  goes on with the work. If the user neither takes nor rejects it, the carried goal stands; the
  next handoff runs the check again and flags it again only if it still fails.

  Record for the evaluator claim: basis
  <https://code.claude.com/docs/en/goal#evaluation-model-and-cost> ("It
  does not call tools, so it can only judge what Claude has already surfaced in the
  conversation"); as of 2026-10-29; recheck when that section says the evaluator reads files or
  runs commands.

  **Order follows what the user asked for.** The region for the payload the user asked for comes
  first, so a fresh-goal request puts the goal region above the resume region. When the user asked
  only for a handoff and the goal is merely carried over from an active `/goal`, the resume region
  comes first and the goal region second. The file cannot record which was asked, so order is a
  producer rule, not a validated one. The regions are alternatives, one paste per fresh session:
  the goal region arms the goal and starts the continuation in one message, the resume region
  continues without a goal. Each has its own instruction line, and a blank line separates the two.

  **Prompt-only emits the same two regions**, and runs the same condition check. The goal region
  carries the condition and the inline goal quote and no `Read @` line; the resume region is the
  prompt-only prompt as before.

  On the full path the file's `## Resume prompt` section stores both regions in the emitted order,
  through the optional slots `goal-first` (above the resume region) and `goal-after` (below it).
  Fill the one the order calls for with the whole region, and leave the other out.

  When no `/goal` call is found and the user asked for no fresh goal, omit the region and note
  below the bottom rail: "if a goal was active, type /goal and a space, then paste the condition."
- **Plugin reload:** when the structure doc's "Plugin changes" entry names a plugin, put a note
  below the bottom rail, ahead of any `/loop` re-arm block: "a plugin changed this session
  (`<plugin> <version>`): after `/clear`, type `/reload-plugins`, then paste the block above."
  Prompt-only, which has no Environment section, names the plugin and version in that note alone.
- **Where recurring items go.** On the full path, each surviving loop, cron task and monitor is an
  entry under the handoff file's `Environment to re-establish`
  ([structure.md](structure.md#environment-to-re-establish)), and the resumed session lists its
  scheduled tasks and re-arms what is missing itself ([`resume.md`](resume.md)). The below-rail
  `Re-arm <i> of <n>` block described next is retired for new files; `find-handoff` keeps reading
  it from older ones. The rules below still decide which loops count as surviving, and their
  list-first step is the one `resume.md` runs. Prompt-only, which has no file, carries the same
  entries as one `Re-arm:` bullet between the rails, each entry in the Environment entry shape.
- **Loop-aware re-arm (older files and prompt-only):** running under `/loop` means this session's own
  `/loop [<interval>] <prompt>` launch turns earlier in the conversation with no later stop (`Esc`, a
  `ScheduleWakeup` call carrying `stop: true`, or, for a fixed-interval loop, a turn in which Claude
  cancelled it, since `Esc` does not stop one), not "infer from conversation" prose. A subsequent
  `ScheduleWakeup` reschedule call (`stop` absent or `false`) corroborates self-paced mode. On Claude
  Code 2.1.319 or later, a self-paced loop counts as stopped once a finished iteration made no
  reschedule, unless `CLAUDE_CODE_LOOP_KEEPALIVE=1` is set; the iteration in progress still counts
  as active (pointer: the
  [2.1.319 changelog](https://code.claude.com/docs/en/changelog#2-1-319) and
  <https://code.claude.com/docs/en/scheduled-tasks#stop-a-loop>, as of 2026-11-07; recheck when
  that section drops its fallback-wakeup sentence). On the loop's first iteration no reschedule has
  fired yet, so its absence is not evidence of anything. Starting a fresh conversation clears every
  session-scoped scheduled task
  (<https://code.claude.com/docs/en/scheduled-tasks#limitations>), so a resume prompt that says
  nothing about the loop runs the continuation once and silently loses the recurring behavior, the
  same failure class `/goal` re-arm exists to prevent.

  **Enumerate every surviving loop, and only the surviving ones.** A session can hold many
  scheduled tasks at once (pointer: <https://code.claude.com/docs/en/scheduled-tasks#manage-scheduled-tasks>),
  so treat the launch turns as a set, not a single find: `/clear` takes them all, and a note that
  re-arms one silently drops the rest. Two conditions retire a launch from that set. A later stop for
  that specific loop, as above. And elapsed time: a recurring task expires a fixed period after creation
  (read the period live at <https://code.claude.com/docs/en/scheduled-tasks#seven-day-expiry>), so a launch turn older than
  that is already gone on its own. Reading it as active would have the note resurrect a schedule the
  operator's session had already stopped running. Emit one re-arm message per loop left standing, and
  nothing at all when none is.

  **The re-arm is a second message, and it carries the original loop prompt, never the resume
  directive.** `/loop` re-runs the prompt it was given on *every* iteration
  (<https://code.claude.com/docs/en/scheduled-tasks#run-a-prompt-repeatedly-with-%2Floop>), and a
  save-point is an immutable record of one moment. Wrapping the resume directive in `/loop` would
  therefore make every later tick re-read that frozen file and replay a remainder already done.
  The loop would stop doing its actual recurring job. So the rails block stays exactly what it is on
  every other path (the resume directive, unwrapped, bootstrapping the continuation once), and the
  note below the bottom rail reads: "this session was running under `/loop`; after pasting the block
  above, list this session's scheduled tasks, and only if this loop is not among them, send
  `/loop [<interval>] <original prompt>` as a separate message to re-arm it", quoting
  the interval and the prompt verbatim from the launch turn, self-paced meaning no interval token,
  and listing one such message per surviving loop, since a command is recognized only at a message's
  start and two cannot share one. Order matters and is stated in the note: bootstrap first, re-arm
  second, because the re-armed loop's own first iteration must not run before the continuation it is
  resuming into. When no launch-turn signal is found, say instead: "if a loop was active and is not
  among this session's scheduled tasks after pasting the block above, re-arm it with
  `/loop [<interval>] <the prompt you originally launched it with>`." The list-first step holds on
  every path, `/clear`-and-paste and `claude --resume` alike: which tasks a resume restores is
  upstream behavior (pointer: the Limitations link above), so the note never assumes a loop died or
  survived, and re-arming one that came back would schedule it twice.

  **Delimit the re-arm entries; a verbatim prompt can be several lines long.** The prompt is quoted
  exactly as the operator typed it, and a message can carry newlines, so an entry is not reliably
  one physical line and "the next line that stops looking like a re-arm" is not a boundary a
  consumer can trust. It truncates the first multi-line prompt it meets and swallows the entries
  after it. Give the block real edges instead:

  - Head each entry with a literal `Re-arm <i> of <n> — <L> lines:` line, then the entry body on
    exactly the next `<L>` lines. `<n>` is the number of surviving loops; `<L>` counts the body
    lines only, never the header. The word `lines` does not inflect: a one-line entry still reads
    `1 lines`, because a parser should not have to know English plurals to find a boundary.
  - **`<L>` is the boundary, and it is a length, not a pattern.** No marker, sentinel, or
    "looks like a re-arm" test can bound a region whose content is reproduced verbatim: whatever
    string is chosen, a prompt is allowed to contain it, and the delimiter then fires inside the
    payload. Counting lines is the only rule that cannot collide with what it delimits, so a prompt
    holding a blank line, a dashed rail, or the literal text `Re-arm 2 of 3` passes through intact.
  - `<n>` is not needed to find the entries, since the lengths already do that, but it makes recovery
    self-checking: a consumer can prove it holds the whole set instead of hoping so.
  - Put the re-arm block last in the message, after the paste-condition note, so the entries are
    contiguous and nothing interleaves them.
  - The no-launch-signal fallback is a single entry with the same header, so a consumer parses one
    shape rather than two.

  Changing this shape is a knowing break of the detection contract below, and must move
  `find-handoff` with it.

  **The note is conditioned on the paste, not on the citing skill.** Re-arming exists only because
  `/clear` destroys the session-scoped schedule, so a delivery that never clears needs none: a
  successful `/session-flow:continue-in-background` launch hands the rails prompt straight to a
  detached agent, clearing nothing, and the loop stays armed on the session still sitting there.
  But the engine emits this prompt before that skill runs its dirty-tree gate or its launch, and
  both can fall back to the standard `/clear`-then-paste instruction, so the delivery path is not
  yet knowable here, and keying the note off the citing skill's identity would drop the re-arm on
  exactly the fallbacks that do clear. Word the note conditionally instead, so it is correct
  whichever way delivery resolves: "this session was running under `/loop`. **If you paste this
  block after `/clear`** (including the fallback when a background launch is refused or fails),
  list this session's scheduled tasks, and only if this loop is not among them, send
  `/loop [<interval>] <original prompt>` as a separate message afterwards to re-arm it; a
  background launch that succeeds clears nothing, so the loop keeps running here and needs no
  re-arm." Transferring the loop into the launched agent is deliberately not done: that would arm a
  recurring schedule inside a detached session the operator is not watching, which is a new
  behavior to decide on its own merits, not a side effect of writing a save-point. A started
  sibling session is the same case: nothing is cleared, the loop stays armed here, and the new
  session does not re-arm it.
- **Combining both:** a command is recognized only at the start of a message
  (<https://code.claude.com/docs/en/commands>), so neither re-arm can ride inside the other's prompt
  argument. Text after the command name is just more of that argument, not a second command
  invocation, and would silently fail to arm. Each is therefore its own message. The `/goal` is the
  user's own typed command followed by the goal region's paste (a goal is session-scoped and
  evaluated after every subsequent turn regardless of what invoked it, so arming it first covers
  the loop's later iterations too); the `/loop` re-arm follows as the separate message described
  above. Where a loop note says "the block above", a two-region prompt means whichever region was
  pasted. On prompt-only, the verbatim goal quote, with its dated amendment lines, sits above the
  remaining-work bullets in the resume region, per "Original goal, mandatory on both paths".

Full-path shape (live: bare `─` rails, no fence; shown inside a fence here for display; the
`Next:` headlines and the goal condition are illustrative; the goal region appears only when a goal
applies, and with no goal the output starts at the `/clear` line):

```text
Type `/goal ` (with a trailing space), then paste everything between the dashed lines. Confirm the `◎ /goal active` indicator appears after you send it; if it is missing, redo it:

──────────────────────────────────────────────────────────
Every call site of OrderReader uses the retry policy and the project's test command exits 0 with the cancellation edge cases covered.
Read @<handoffs-dir>/<TS>-handoff-<topic>.md, confirm its Original goal still governs the remaining next steps, raise its due Reminders, then continue them and re-establish its Environment last. For the next save-point invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.
──────────────────────────────────────────────────────────

`/clear`, then copy everything between the dashed lines:

──────────────────────────────────────────────────────────
Read @<handoffs-dir>/<TS>-handoff-<topic>.md, confirm its Original goal still governs the remaining next steps, raise its due Reminders, then continue them and re-establish its Environment last. For the next save-point invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.
Prior session: <UUID>.
Handoff origin: <remote URL, userinfo stripped> <repo-relative path>
Next:
Wire the retry policy into OrderReader
Add the cancellation edge-case tests
Then: /testing:write
──────────────────────────────────────────────────────────

Or reopen the producing session in place: `claude --resume <UUID>`.
```

### Full path only: the block is validated, stored, and printed, never regenerated

These steps validate and emit the durable handoff. Prompt-only delivery has no handoff document
to validate.
For an [urgent handoff](#urgent-handoff), use its repair limit and failure banner.

- **The verdict decides which rails are pasted.** `fill` writes the file, then prints its
  verdict and the rails, whatever the verdict. On a PASS or WARN verdict those rails are the
  block to paste. On a FAIL, the rails `fill` printed are not the resume prompt yet: fix what the
  FAIL lines name with the Edit tool and re-run `validate`, at most three attempts, then paste
  the `emit` output. Size is the exception, settled by `fill`: an over-budget slot is rewritten
  once, in the second `fill` call its refusal asks for, and a `slot_size` FAIL that `validate`
  reports after that is final and quoted, never edited around; an `OVER-CAP` line never withholds
  the rails, and is acted on only as it says, never by cutting binding text. Quote the outcome in
  the citing skill's checklist (`validate: exit 0`, WARN lines listed).
- **Three failed attempts do not withhold the rails.** The observed failure class is an operator
  left with nothing to paste, and "A resume prompt is always emitted" wins: print an
  `UNVALIDATED: <validator output>` banner above the copy instruction (outside the copy region, so
  the detection contract below holds), mark the checklist box `validate: FAILED`, and still emit
  the rails from the file's `## Resume prompt` section. Never green-silent.
- **The on-screen block is the `emit <file>` output pasted verbatim.** Each region's copy
  instruction, top rail, text and bottom rail, the below-rail `claude --resume` line, and any
  notes, exactly as printed, never retyped, reflowed, or regenerated from the conversation. The file's
  `## Resume prompt` section and the screen are byte-equal by construction, which is what lets
  `find-handoff` rung 1 recover the prompt from the file alone and `continue-in-background` launch
  from it. Python absent: emit the section by hand from the file, still verbatim.
- **The directive is fixed text.** `Read @<absolute path>, confirm its Original goal still governs
  the remaining next steps, raise its due Reminders, then continue them and re-establish its
  Environment last. For the next save-point invoke /session-flow:handoff via the Skill tool; never
  write a handoff file free-hand.` The second sentence is the successor's license to write
  handoffs: through the skill only. The "raise its due Reminders" and "re-establish its
  Environment last" clauses are the fallback for a session the resume-context hook does not reach
  (the setting off, or an older plugin); with the hook on, the procedure it injects,
  [`resume.md`](resume.md), says how. `validate` checks only the license clause, so an older
  file's shorter directive still passes. The
  "then execute /<skill>" swap the prompt-only rule below allows is expressed on the full path by
  the `Then:` line instead, so the directive never changes shape.
- **`Handoff origin:` has one form:** `Handoff origin: <remote URL, userinfo stripped> <repo-relative path>`,
  two whitespace-separated slots, a slot that contains whitespace double-quoted. The script
  computes both at write time from the repository the file was actually written into: the
  `origin` remote sanitized per `<repo-identity>` below, else the root directory name; and
  `<repo-relative path>`, the file's path relative to that repository's root
  (`<memory_dir>/handoffs/<TS>-handoff-<topic>.md` with the relative memory root, `.work` by
  default; never the absolute `<handoffs-dir>` form line 1 uses), or the absolute path on the
  no-project-root branch. The value is stored, inside the file's `## Resume prompt` section, and
  nowhere else.
- **`Next:` carries headlines, not detail.** The line `Next:` followed by 1 to 5 plain lines, one
  headline per line, no bullets, no blank lines, each the first words of an item from
  `Remaining actions, in order`. Headlines yes, detail no: the file `@`-referenced on line 1 holds
  the sequence, and the between-rails text is what a resuming session or a background agent sees
  first. The last headline may be `Then: /<one skill>`, the fully-qualified skill the next stage
  starts with, at a stage boundary only, never mid-stage. A closing handoff is written by giving
  `fill` the `next` value `Next: none (closed)` exactly: `fill` puts that text on the `Next:` line
  and deletes the slot line, so the closed form carries no headlines. The validator refuses a
  sixth line, a bullet, and a `Then:` that is not last.
- **Below the bottom rail, first line:** the sentence `Or reopen the producing session in place:`
  followed by `claude --resume <UUID>` in a code span and a period, the alternative to
  `/clear`-and-paste when the producing session is still worth reopening. A session in a plugin
  profile adds `--settings "<file>"` after the UUID inside the code span, since a resumed session does not
  keep `--settings`. The no-goal-found and plugin-reload notes
  the rules above prescribe follow it, unchanged in shape (a file older than the Environment
  entries also carries its `/loop` re-arm block here); it is
  outside the copy regions and outside the detection contract.

### The directive path is rooted, and that is the whole point

`<handoffs-dir>` is the **absolute** path of the directory the write step actually used: the
resolved `<memory_dir>/handoffs/` (default `.work/handoffs/`) with the root it hangs off rendered
in front of it. Never emit a default the file was not written to, and never emit the relative
segment alone.

A rootless `@.work/handoffs/…` resolves against the *resuming* session's cwd, which is not
guaranteed to be the root of the repository the work happened in. The producer may have written
into a repo that is not cwd's project root, and the resuming session may sit in a subdirectory of
the right repo or in a different repo entirely. When the wrong root happens to contain its own
`.work/handoffs/`, the failure presents as "the file is missing" rather than "the path has no
root", which is the most expensive shape to diagnose. Rooting the path removes the resolution step
that can be wrong. On the no-project-root branch handoffs land under `${CLAUDE_PLUGIN_DATA}/artifacts/handoffs/` with
the absolute path announced prominently, and absolute is already what this engine does wherever a
relative path has no anchor.

**Render it forward-slash normalized**, as `/home/<user>/src/<repo>/.work/handoffs/…` on a POSIX
host and `D:/repos/<owner>/<repo>/.work/handoffs/…` on Windows, never with backslashes: the directive
survives into transcript JSONL, where a backslash is escaped again, and `find-handoff` greps that
record.

**The `@` is an accelerator, not the mechanism.** An `@` reference pre-loads the file it names; which
path forms expand is read at
<https://code.claude.com/docs/en/common-workflows#reference-files-and-directories>, which documents no
drive-letter or whitespace-bearing form, so treat expansion as
unverified for those: the same line states the absolute path in full either way, and a resuming
session that sees no expanded content reads the path directly. Write the directive so it is
actionable without expansion. That is what makes rooting a strict improvement over the rootless
form rather than a trade.

**`<repo-identity>` keeps the prompt usable off this machine.** An absolute path is machine-local,
and a save-point's own "When to invoke" includes sharing state with another machine, so the third
line names what the path can be re-derived from: the repository's `origin` remote URL when it has one
and that URL can be sanitized with confidence (the test is below), else its root directory name, and
the repo-relative path under it. It is computed at write time by `save_point.py new`
from the repository actually written into. When cwd is not that repository, it names the repository
the file was actually written to, never the one cwd happens to sit in (`--repo-root` defaults to the
git top level of the resolved memory dir, never cwd). It is stored exactly once, inside the file's
`## Resume prompt` section, because that section stores the whole emitted block; nothing in the
frontmatter carries it. A resume on a different machine or checkout ignores line 1's root and
re-resolves from line 3.

**Strip the remote URL's userinfo before embedding it.** A remote URL routinely carries a credential
in its userinfo component: `https://<token>@github.com/<owner>/<repo>.git` for HTTPS-with-PAT,
`https://<user>:<token>@host/…` for a stored password, and the `x-access-token:<token>@` form a
credential helper writes. This line sits inside the rails, in the region the operator is told
to copy, so an embedded credential travels into the next session and onto every machine the prompt
is forwarded to. Take `git remote get-url origin` and remove the credential-bearing userinfo,
everything from `://` up to and including the `@`, before embedding what is left, so a PAT-bearing
remote is emitted as `https://github.com/<owner>/<repo>.git`. The redaction pass is the backstop, not
the mechanism: it is a model-driven sweep that can read a bare token as just another path segment,
and a credential never put into the string cannot be missed.

**A bare ssh account name is not a credential.** `ssh://git@github.com/<owner>/<repo>.git` carries no
secret, since the secret is the local key, which the URL does not contain, so the `git@` stays. Strip
userinfo that carries a token or a password; leave userinfo that is only a well-known ssh account
name. Dropping it would not hurt recovery, but it would state something false about the remote.

**"Cannot be sanitized with confidence" has a test: can you say where the userinfo ends and the host
begins?** Fall back to the root directory name when you cannot. Concretely: more than one `@` sits
ahead of the path, so the boundary is ambiguous; there is no `://` to anchor on, as in the SCP-style
`git@host:<owner>/<repo>.git` form, where the `@` delimits an ssh user and no scheme marks where
stripping would begin; or the string is not a shape you recognize. Guessing the boundary risks
leaving the token in or mangling the identity. The directory name loses neither, and it re-resolves
nearly as well.

When the next stage is a specific skill in the consuming repo, the full path names it on the
`Then: /<skill>` line (full-path block above; the directive itself is fixed text).
The `@`-reference is mandatory on the full path, since the fresh session
loads it; do not inline the file's detail in the prompt. Prompt-only carries its remaining-work
bullets inline between the rails instead, and needs no origin line: it references no file.

**The alignment clause rides in the directive because the directive is the one thing every resume
path passes through.** The dominant resume is a paste into a fresh session that invokes no skill at
all, so a check living only in a skill fires only when someone happens to call it, which is how a
chain of save-points can run for many sessions with nothing ever testing the work against its goal.
`/session-flow:keep-going` owns the same check on the skill-mediated path (its goal-alignment
step, which gates its recovery actions); this covers the bare paste, the background agent
`/session-flow:continue-in-background` launches, and a `find-handoff` recovery alike. It is not a
detection-contract change: signal 1 below is matched on the `…handoffs/<TS>-handoff-…` shape the
directive names, which the added clause leaves untouched.

`<UUID>` = this session's `$CLAUDE_CODE_SESSION_ID` (the frontmatter `session_id`). It lets a
fresh session or `/session-flow:retro` chain-walker locate the transcript later, and it is the id
the below-rail `claude --resume <UUID>` line reopens. On the full path the script refuses a
missing or non-UUID value (such as a Remote Control bridge id; `CLAUDE_CODE_BRIDGE_SESSION_ID`
is never read); the save-point then takes the prompt-only path with the reason
stated ("no session UUID available; chain gap accepted"), never a hand-written handoff file.

After the rails prompt is emitted, control returns to the citing skill's delivery step.

## Markdown surfaces

The Desktop app and Claude Code on the web render a reply as markdown in a proportional font.
There the rails are plain lines with no copy control, paths inside them turn into links, a `- [x]`
checklist draws struck through, and the position panel's leading spaces collapse. The terminal
draws none of that, so the rails stay the terminal's form.

A citing skill reads the surface from the `surface` probe ([`gather.md`](gather.md)): a
`CLAUDE_CODE_ENTRYPOINT` of `claude-desktop`, or a `CLAUDE_CODE_REMOTE` of `true`, is a markdown
surface; anything else, an unset value included, is the terminal. On a markdown surface:

- **The prompt is the `emit --format markdown` output**, pasted verbatim. Each rail pair prints as
  a fenced `text` block (a fence longer than any backtick run inside it), which the app draws with
  a copy button and without links. The resume copy line reads ``Run `/clear`, then paste this:``,
  and the goal line reads ``then paste this.`` before its confirm sentence. Every line between the
  rails is unchanged, and everything outside them, the below-rail notes included, prints as it is.
  `amend --format markdown` prints its prompt the same way.
- **The file is untouched.** It still stores the rails, so `emit` with no flag, recovery from the
  file, and `continue-in-background`'s launch read the same bytes as before.
- **The position panel is a numbered list**, one unit per item: ✅ for `[x]`, ▶ and bold with
  `← you are here` for the current unit, ⬜ for pending, ⛔ for blocked. The completeness line and
  the three blocks follow, and every other panel rule holds.

- **The handoff's enforcement checklist is one line**, `Checklist: <ticked>/<total> pass`, then
  each box not ticked and each `validate` WARN or FAIL line as one bullet, never a `- [x]` list,
  which the app draws struck through. On the prompt-only path each region prints as a fenced
  `text` block under the same copy lines.

A citing skill's own audit lines follow that skill's rule for this surface.

## Detection contract, consumed by `/session-flow:find-handoff`

The output shape above is a **stable detection contract**, not merely a display convention:
`/session-flow:find-handoff` keys off it to recover a handoff whose resume prompt was written but
never copied (operator ran `/clear` before copying it). The keyed signals, in precision
order, are (1) the `Read @…-handoff-*.md` directive, the exact path to recover, for a file-based
handoff, which appears in both regions when a goal region exists and names one path; (2) the
`─` (U+2500) rail pair headed by the `` `/clear`, then copy everything between the dashed lines ``
instruction line (the resume region), the primary key for a prompt-only handoff, which writes no
file, or, as a markdown surface prints it ("Markdown surfaces"), the fenced `text` block under
the ``Run `/clear`, then paste this:`` line, whose content is the region's text;
and (3) the `Prior session: <UUID>` line, which, together with the `type: handoff` frontmatter
([`structure.md`](structure.md)), pins the session chain; it is emitted by the file-mode shape
but is not required of prompt-only output, so consumers treat it as corroboration, never a
required key.

**The position panel sits outside this contract.** It is emitted above every keyed signal and
outside the copy region, carries no rails, no directive, and no `Prior session:` line, and a
consumer that ignores it entirely recovers exactly what it recovered before. Adding it is
therefore not a contract change and needs no `find-handoff` edit, stated explicitly because
everything else in this section treats a shape change as a knowing break.

**Signal 1 is rooted or rootless, and a consumer accepts both.** Older handoffs state a
repo-relative path, and those files and transcripts stay on disk, so a detector that recognizes
only rooted directives misses them. The directive is matched on its `…handoffs/<TS>-handoff-…`
shape, and the two forms diverge only at the existence check: a rooted path is checked as given,
while a rootless one resolves against the source transcript's `cwd`. That resolution is inference,
since the producer's cwd is not necessarily the repository it wrote into, so a rootless candidate
whose file is not found is **UNRESOLVED, never discarded**: a discarded candidate is a handoff the
recovery cannot return.

The `Handoff origin:` line is a **resolution input, not a detection signal**. It cannot admit or
reject a candidate, so it is neither a fourth key nor the conditional slot the `/loop` re-arm note
holds below. A consumer reads it only after a candidate has qualified, at the existence check: when
the rooted path does not exist on this machine, as on a resume on another machine or another checkout,
which is the one failure mode absolute paths have and relative ones do not, the line names the
repository and repo-relative path to re-resolve from. **A rooted path that is not found is therefore
the same not-found-here condition as a rootless one that does not resolve, and gets the same
UNRESOLVED treatment**; a consumer that reports it as a missing file reintroduces the defect on the
new path. The line is emitted by the file-mode shape only, and older file-mode handoffs lack it, so its
absence disqualifies nothing: prompt-only never emits it.

**The recoverable unit is the resume region plus the goal region plus every below-rail `/loop`
re-arm message.** The goal region, when a goal applies, is a second rail pair headed by its own
instruction line (the fixed goal-region line under "Emit the copy/paste resume prompt"), placed
above or below the resume region. It is not a keyed signal, since the resume region is always
present and keys the recovery, but a recovery that returns only the resume region hands back a
continuation whose goal is gone, the failure the goal region exists to prevent, reintroduced one
layer down. So a consumer expects two or four rails and recovers every region, in the emitted
order. A file stores both regions, so `save_point.py emit <file>` returns them. The `/loop`
re-arm is the other element outside the resume region, and not by choice: a command is recognized
only at a message's start (<https://code.claude.com/docs/en/commands>), so the re-arm must be its
own message and therefore lives below the bottom rail, outside every copy region. A recovery that
surfaces only the regions between the rails hands back a continuation that runs once and drops the
recurring behavior, the exact failure the re-arm rule exists to prevent, reintroduced one layer
down. So the re-arm note that directly follows the bottom rail is part of what a recovery must
surface, not commentary it may discard. Nor is one of them enough: the rule above emits one re-arm message per loop left standing,
so the recoverable unit is however many the producer wrote, and a consumer that stops at the first
loses the rest exactly as quietly.

Each entry is recovered by its `Re-arm <i> of <n> — <L> lines:` header and the `<L>` body lines that
follow it, **a length boundary, never a wording match**. The entry carries the operator's original
prompt verbatim, so any content test can be defeated by the content: matching the note's wording
truncates a prompt whose continuation lines do not resemble a re-arm, and matching a marker fails on
a prompt that quotes the marker. A count cannot collide with what it delimits. `<n>` is the
self-check that the whole set came back, not the scanner. The verbatim prompt also means the same
redaction pass applies here as to everything else surfaced from a transcript.

**The shape-2 and shape-3 block carries these elements, and `find-handoff` reads them** (the
keyed signals above are the same for every shape: signal 1 matches the `…handoffs/<TS>-handoff-…` shape, signal 2
the rails plus the copy line, signal 3 the `Prior session:` UUID):

- The directive continues after `then continue them.` with the sentence `For the next save-point
  invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.` A
  consumer matches the path shape, never the sentence's presence or absence: every handoff
  written before shape 2 lacks it.
- `Handoff origin:` has the two-slot form `<remote URL> <repo-relative path>`; the legacy form
  `<identity>, relative path <p>.` is on disk and in transcripts unchanged. A consumer reads
  both, and still treats the line as a resolution input, never a key.
- `Next:` and its headline lines, and an optional `Then: /<skill>` line, sit between the rails.
  They are content in the copy region, not shape: a consumer that recovers the region recovers
  them, and never keys on them.
- The first line below the bottom rail reads `Or reopen the producing session in place:` followed
  by `claude --resume <UUID>` in a code span. A consumer anchoring the `/loop` re-arm capture to
  the bottom rail skips that line (and the blank line above it) before scanning for
  `Re-arm <i> of <n>` headers.
- The file stores the whole block as its final `## Resume prompt` section, so a shape-2 or
  shape-3 file is recoverable from disk alone: `save_point.py emit <file>` prints it. A file still carrying a
  `<!-- FILL` slot is an unfinished skeleton, never a candidate, and `emit` refuses it.

Changing this prompt/marker format, the rails, the header, or the meaning of `<L>`, is a
**knowing** break of that contract, not a cosmetic edit; update `find-handoff`'s detection in the
same change.
