# Handoff document structure + full-path write procedure

Reference consulted while WRITING a full-path handoff (delivery-decision logic — STOP gate,
launch gates, exit checklists — stays in the citing skill's `SKILL.md`; path choice and destination
resolution live in the sibling `save-point.md` engine doc).

Reader is a session with NO prior context. It will act on this file. Be specific — vague handoffs
cost the next session a re-investigation, which is the cost this document exists to avoid.

**Shape 2.** A handoff file written by this procedure carries `handoff_shape: 2` in its
frontmatter. Every deterministic field of a shape-2 file is written by the engine script
`${CLAUDE_PLUGIN_ROOT}/scripts/save_point.py` (`new` writes the skeleton, `validate` gates it,
`emit` prints its resume prompt); the model fills only the reasoning slots the skeleton leaves as
`<!-- FILL: <name> — <instruction> -->`. The write procedure below is the one path that produces a
shape-2 file. Files written before shape 2 (no `handoff_shape` key) are shape 1: read normally,
tolerated by the validator with one WARN, and never rewritten.

## Contents

- [Body sections](#body-sections)
  - [Cumulative sections and provenance tags](#cumulative-sections-and-provenance-tags)
  - [Original goal](#original-goal)
  - [Resumption brief](#resumption-brief)
  - [Completion criteria](#completion-criteria)
  - [Constraints that must hold](#constraints-that-must-hold)
  - [Environment to re-establish](#environment-to-re-establish)
  - [Side effects already applied](#side-effects-already-applied)
  - [File roles in this work](#file-roles-in-this-work)
  - [Decisions already settled](#decisions-already-settled)
  - [Approaches tried and abandoned](#approaches-tried-and-abandoned)
  - [Findings that cost effort to discover](#findings-that-cost-effort-to-discover)
  - [Remaining actions, in order](#remaining-actions-in-order)
  - [Open questions to investigate](#open-questions-to-investigate)
  - [Blockers needing an outside decision](#blockers-needing-an-outside-decision)
  - [Suggested skills](#suggested-skills)
  - [This session](#this-session)
  - [Prior sessions](#prior-sessions)
  - [Resume prompt](#resume-prompt)
- [How this document is referenced elsewhere](#how-this-document-is-referenced-elsewhere)
- [Full-path write procedure](#full-path-write-procedure)
  - [Frontmatter shape 2](#frontmatter-shape-2)
  - [Chain continuity, same task only](#chain-continuity-same-task-only)
  - [Legacy predecessors and unfinished skeletons](#legacy-predecessors-and-unfinished-skeletons)

## Body sections

Ordered so the cheapest useful layer comes first. A reader can stop after **Original goal** plus
**Resumption brief** and still take the correct next action; everything below is there for the
reader who needs more.

| Order | Section | Owns |
|---|---|---|
| 1 | Original goal | what the work is FOR, in the user's own words, plus the opening ask |
| 2 | Resumption brief | the resumption decision |
| 3 | Completion criteria | what "done" means, observably |
| 4 | Constraints that must hold | invariants whose violation breaks the work (cumulative) |
| 5 | Environment to re-establish | machine and session state `/clear` destroyed |
| 6 | Side effects already applied | persistent effects that must NOT be repeated (cumulative) |
| 7 | File roles in this work | which file plays which role, and how far its change got |
| 8 | Decisions already settled | closed choices, with the reasoning that closed them (cumulative) |
| 9 | Approaches tried and abandoned | directions walked and rejected (cumulative) |
| 10 | Findings that cost effort to discover | non-obvious system facts, expensive to re-derive (cumulative) |
| 11 | Remaining actions, in order | every action still to take, sequenced |
| 12 | Open questions to investigate | unknowns the resuming session can resolve itself |
| 13 | Blockers needing an outside decision | work that cannot proceed without someone else |
| 14 | Suggested skills | which skills to invoke for the remaining work |
| 15 | This session | one past-tense `did: … · left: …` line about THIS hop |
| 16 | Prior sessions | one table row per prior hop, copied forward |
| 17 | Resume prompt | the rails block exactly as emitted on screen; always last |

**Every section is always present, in this order, and `## Resume prompt` is last.** The
validator checks all 17 headings by name and order. A section with nothing to report reads `None.`
plus a half-line of reason. A cold reader cannot otherwise tell "nothing to report" from "the
author forgot", and the absence is itself load-bearing — "no approaches abandoned" tells the resumer
the ground is untrodden. **`Original goal` is the one section `None.` never satisfies:** work with
no statable goal is the condition this document exists to surface, so an empty §1 is a defect to
raise with the user, not a box to tick. (Its `Amended:` line is the field that legitimately reads
`None.`)

**Emit body sections at `##`.** This document nests them under its own heading, so they appear here
one level deeper than they are written.

**Layering is not truncation.** No section carries a length budget except the brief. Progressive
disclosure governs the ORDER facts are met in, never whether they survive. Sections 8, 9, and 10
exist specifically for what a summarizer discards first — rationale, negative knowledge, and
hard-won facts — because those read as "old" while being the most expensive to rediscover.

**Provenance: verified this session, or marked.** [`save-point.md`](save-point.md)'s "Claim
provenance" rule governs every body section here (and, per that rule, prompt-only's inline bullets
too): plain statement only for what this session itself verified, an explicit
`UNVERIFIED (<source>)` marker on anything inherited. The met/unmet marks in Completion criteria
carry the same rule.

### Cumulative sections and provenance tags

Five sections are **cumulative**: §4 Constraints, §6 Side effects, §8 Decisions, §9 Abandoned,
§10 Findings. They are never rewritten from memory; the script copies the predecessor's entries
forward verbatim off disk and the writer appends. Every other section is rewritten each hop (the
state of now).

- **Every entry carries an `[hN]` tag** — `- [h3] …` — naming the hop that asserted it (`N` counts
  from the root of the chain; hop 1 is `[h1]`). The tag IS this document's `UNVERIFIED (<source>)`
  marker for a carried entry: an entry tagged with an earlier hop was verified by that hop, not
  this one. **Re-verifying an entry this session re-tags it to the current hop**; leaving the
  old tag is the honest default when nothing re-checked it. `N` never exceeds the chain length.
- **Entries are never deleted.** A disproved or no-longer-binding entry moves under a
  `Superseded:` marker line at the end of the section, tag intact, so the chain shows what was
  believed and when it stopped being true. The validator fails a successor that drops a
  predecessor's entry outright.
- **One entry per line**, continuation lines indented. A section with nothing to carry and nothing
  new reads `None.` plus a half-line of reason; `None.` lines are exempt from the tag rule.
- Legacy (shape-1) predecessor entries arrive untagged; `new` tags them `[h1]`. A predecessor that
  itself failed validation has every carried entry prefixed
  `UNVERIFIED (predecessor failed validation):` after its tag.

### Original goal

**The user's own words, quoted, and immutable across the chain.** This section owns the goal; every
other section is subordinate to it. It is the one thing a chain of save-points loses first, because
each writer serializes the machinery in front of them — the phase, the bundle, the checklist — and
machinery reads as mission to the session that inherits it.

- **Goal (verbatim):** the user's goal statement quoted as they wrote it, with the date they stated
  it. Quote it; never paraphrase, condense, or "clarify" — a paraphrase is a re-derivation, and this
  section exists because re-derivation is what fails. Where the goal was never put in one sentence,
  quote the closest thing the user actually wrote and mark it `RECONSTRUCTED`: a reconstruction is a
  defect to settle with them, not a substitute for their words.
- **Amended:** `None.` until the goal changes. It changes ONLY on an explicit statement from whoever
  set it — never because the work went somewhere else. Record an amendment as a new dated verbatim
  quote with the prior goal kept above it, so the chain shows what the goal was and when it stopped
  being that. A writer never amends the goal on its own authority.
- **Opening ask:** the user's opening message of the chain, the words the whole task started from.
  At hop 1 it is quoted verbatim (redacted, at most 15 lines, no bullets; the transcript is the
  full source, so a longer ask is cut, never summarized). At every later hop the line is a
  pointer the script writes: `Opening ask: see <root file> § Original goal`, naming `chain[0]`;
  when the root is a shape-1 file the pointer adds `(shape-1 root, no verbatim ask recorded)`.
  The ask is stored once and never re-derived.
- **Next action serves it by:** one sentence tying the first item of `Remaining actions, in order`
  back to the goal. This couples to §11 deliberately — a reader who stops here has to be able to
  tell whether the work is still pointed at the goal, and a pointer to another section cannot
  answer that.

**Cannot state that sentence? That is drift, and this is where it gets said.** Write what the next
action actually serves, then route it: re-derive an action that serves the goal, or ask whether the
goal has changed. Staying silent is what lets drift run — nothing else in this document would have
caught it, because every other section describes the work faithfully.

**A successor handoff COPIES the goal and its amendments; it never restates them.** The write
procedure below makes that a disk read, not a recollection: `new --previous <file>` copies the
goal quote and every amendment off the predecessor unchanged and writes the `Opening ask:`
pointer. The drift-check line is the one part re-answered each hop — it is about the next action,
which moved.

### Resumption brief

Six lines maximum. The one section a reader may stop at *after* the goal above it.

Carries: when it was written and against which branch or commit, where the work stands in one line,
and the single next concrete action. Name the section that governs that action so a reader wanting
more is routed rather than left searching. It does NOT restate the goal — §1 owns that, verbatim,
and a six-line onboarding surface is exactly where a goal gets compressed into the process that was
serving it.

The brief names the FIRST action only. It always points at `Remaining actions, in order`, which owns
the full sequence — otherwise a session that completes the one named action has nothing to go on.

This deliberately restates facts owned below — it is an onboarding surface on a document read cold.
The six-line cap bounds the drift, and naming each owning section keeps the pointer honest.

Close it with the one obligation the brief cannot carry: an agent about to change anything reads
**Constraints that must hold** first.

### Completion criteria

One line of why the work exists, then each criterion as an observable test with a met/unmet mark.

A criterion nobody can check is not a criterion — rewrite until a command or a diff settles it.

**Each criterion names the goal-state it establishes, and keeps its observable.** A criterion reads
as a condition the goal in §1 requires — "the repo's docs follow conventions X, Y, and Z" — never as
the process step meant to produce it ("phase 3 done", "the bundle merged"). Process framing is what
turns a resumed session onto the machinery: it is satisfiable while the goal is no closer, and it
reports done when the process finished rather than when the work landed.

This stacks on the observability rule; it does not relax it. Goal-framed criteria are harder to
settle mechanically, which is why writers drift to process framing — so each criterion carries
both halves, the goal-state and the command or diff that settles it.

```markdown
- [x] `dotnet test` green on the affected projects
- [ ] the retry path is exercised by a test that fails without the fix
```

**Process milestones are recorded subordinate to the criteria, never as criteria.** They pace the
work and cannot define done. Put them under a `Process milestones` sub-heading one level below this
section's own emitted heading, each tied to the criterion it advances.

### Constraints that must hold

Invariants whose violation breaks the work. One testable assertion per line, each followed by the
consequence of violating it.

Only things that would actually break something. A preference is a decision — section 8.

Before closing the section, re-scan for *but*, *except*, *unless*, "the exception is", "the corner
case" — those words mark constraints that emerged mid-discussion and never rose to a top-line
bullet, and an omitted one is exactly what the resuming session ships as a bug.

**Compaction changes what "the conversation" is.** Detect it from a concrete signal — a compaction
notice or summary turn actually present in this conversation — never inferred from the history
merely feeling short or discontinuous. (The citing skill's "When to invoke" — "last turn had an
unexpected compaction" — names the common case that brings a session here, but compaction can also
happen mid-session without being the reason `/session-flow:handoff` was invoked, so check for the signal itself,
not the invocation reason.) Once that signal is present, the model-visible conversation is the
summarizer's output, not the original turns, and a scan of what remains cannot find a caveat the
summarizer already dropped. Exactly one of the following must be true when the section closes, and
the section must say which — silence on this point reads as the first, so it is never a third
option:

- The re-scan read the lossless on-disk transcript instead of, or in addition to, the model-visible
  conversation — it stays lossless across compaction (the same record `retro`'s parser reads:
  `${CLAUDE_PLUGIN_ROOT}/skills/retro/scripts/parse_transcript.py`, paths resolved per retro's
  "Paths"; `/session-flow:running-retro`'s "2. Resolve inputs for the subagent" is a worked example
  of reading it without flooding the current context with the raw record).
- It did not, and the section states so explicitly: "Re-scanned the visible conversation only; a
  compaction occurred this session, so pre-compaction turns were NOT re-scanned for buried
  constraints."

```markdown
- The public `IOrderReader` signature is frozen — three downstream repos compile against it.
- Migrations run forward-only; a down-migration corrupts the tenant partition key.
```

### Environment to re-establish

Machine and session state the previous session had and this one does not. One entry per item: what
was running, the exact command that restores it, and the observable that confirms it worked.

Covers branch and worktree, services and ports, environment variables, background tasks — and the
in-memory task list, which `/clear` destroys completely.

**TaskList.** Call `TaskList` before writing this section and render live state, not remembered
state:

| Glyph | Status |
|-------|--------|
| `[x]` | completed |
| `[~]` | in_progress |
| `[ ]` | pending |
| `[!]` | blocked |

````markdown
- [x] Profile update — done; unclear handles investigated.
- [~] Full scan — wave 1 initialized (0/178 complete). Drive the loop in the fresh session.
- [ ] Full pipeline run — collection → dedup → ranking → synthesis.

Recreate before resuming. Run in this exact order (preserves numbering):

```text
TaskCreate(subject="Profile update", description="...")    → status=completed via TaskUpdate
TaskCreate(subject="Full scan", description="...")         → status=in_progress via TaskUpdate
TaskCreate(subject="Full pipeline run", description="...") → status=pending (default)
```
````

With 0 active tasks, or all `completed`, say so — there is nothing to recreate.

### Side effects already applied

Persistent, non-file effects a fresh session would otherwise repeat. One line each, and say plainly
that it must not be re-run.

The resuming session is exactly the reader that will re-run a migration because nothing told it not
to.

```markdown
- Migration `20260724_add_tenant_index` is APPLIED to the local database — do not re-run.
- PR #1204 is already open against this branch — push, do not create a second one.
```

### File roles in this work

The role each file plays, and how far its change got. One line per file: path, exactly one role, why
it matters, and a concise summary of the change — one clause, not a transcribed diff.

Roles: modified / still to modify / specification to obey / reference for understanding / test that
must pass / generated, do not hand-edit.

**Summarize; never transcribe.** For work already committed, the commit range is the diff — name what
the change accomplishes in a clause and point at the branch or commit for the lines.

**Uncommitted or half-finished edits are the exception, and they are why this section carries state
at all.** There is no commit to point at, so say which part is already implemented and working and
which part is not — that state exists nowhere else, and a resuming session that has to re-derive it
from a working tree is doing the rediscovery this document exists to prevent. `Remaining actions, in
order` owns what to do next; this owns where the file currently stands.

```markdown
- `src/Ordering/OrderReader.cs` — modified; retry wrapper added and green (commit `a1b2c3d`).
- `src/Ordering/OrderWriter.cs` — modified (uncommitted, half-done); the retry wrapper is in place
  and passing, the cancellation-token pass-through is stubbed and does not compile yet.
- `tests/Ordering/OrderReaderTests.cs` — still to modify; edge cases uncovered.
- `docs/adr/0012-retry-policy.md` — specification to obey.
```

### Decisions already settled

Closed choices, so the next session does not relitigate them. One entry per decision: the decision
as a one-line claim, then its rationale and what it forecloses. Rationale is a field of the
decision, never a separate list.

If a contract or approved plan on disk already records a decision, reference it rather than
restating it.

```markdown
- Using `Result<T>` instead of exceptions for not-found → railway-oriented style is the project
  default per its CLAUDE.md. Forecloses the exception-filter approach in the handler.
```

### Approaches tried and abandoned

Directions walked and rejected. One entry per attempt: what was tried, what was observed to fail,
and why it cannot be salvaged.

Without this the next session repeats the dead end. Budget detail generously.

A fact about how the system behaves belongs in section 10; a path you walked belongs here.

```markdown
- Wrapping the call in `Polly` retry → the transport already retries, so failures multiplied to
  9 attempts and tripped the upstream rate limit. Not salvageable without disabling transport retry,
  which other callers depend on.
```

### Findings that cost effort to discover

Non-obvious facts about the system that would be expensive to re-derive, and that are neither a
decision nor a failed approach. One entry per finding: the fact as a one-line claim, then where it
was observed — a file, a command's output, an error string.

This is the section that beats compaction. Write it long.

```markdown
- The hook fires twice per Write on Windows, once with a normalized path and once raw — observed in
  `.claude/observability/hooks.jsonl` across 40 events.
```

### Remaining actions, in order

Every action still to take, sequenced. Not just the next one — the whole remainder, so finishing
the first action does not leave the resuming session guessing at the second.

An action is something to *do*. An unknown to resolve is section 12; something you cannot proceed
on is section 13. Cross-reference those rather than duplicating them: an action that waits on a
blocker is listed here in its sequence position, marked as waiting, and named once in section 13.

The `Resumption brief` names only the first of these. This section owns the rest — it is the one
place the full sequence exists, so it survives when the brief's single action is done.

```markdown
1. Wire the retry policy into `OrderReader` (spec: `docs/adr/0012-retry-policy.md`).
2. Add the cancellation edge-case tests — the happy path is already covered.
3. Waiting on the staging credential grant: re-run the integration suite against staging (§13).
4. Update the module README once 1-3 land.
```

### Open questions to investigate

Unknowns the resuming session can resolve on its own. One question per entry, each with the probe
that answers it.

If the session cannot answer it alone it is not a question — it is a blocker.

```markdown
- Does the reader honor `CancellationToken` on the streaming path? Probe: cancel mid-enumeration in
  `OrderReaderTests` and assert the stream stops.
```

### Blockers needing an outside decision

Work that cannot proceed without a human, an access grant, or an upstream fix. One line per
blocker: what is stuck, who or what unblocks it, and what to do meanwhile.

```markdown
- Cannot verify the staging path — no credentials for the staging tenant. Unblocks: ops grant.
  Meanwhile: the local integration suite covers the same code path.
```

### Suggested skills

Which skills the resuming session should invoke for the remaining work, each tied to a concrete
remaining item — not generic recommendations.

Use fully-qualified names (`plugin:skill`) and qualify each with "if installed": the resuming
session may run under a different plugin set, and a missing skill degrades to doing that work
inline.

When no skill maps to the remaining work, write `None — remaining work runs inline`.

### This session

Exactly one line, about THIS hop only, in the past tense:

```markdown
did: wrote the re-run test and got it green · left: the staging migration and the double-run check
```

The separator is a middle dot, `·` (U+00B7), with a space either side; the validator matches
`did: … · left: …` literally. `did` is what landed, `left` is what is still open — both past
tense, no "next", no imperative: this line becomes the `did/left` cell of the successor's
`## Prior sessions` row, where it is read as a one-line record of a finished session, so a `|`
anywhere in it breaks that table and is refused. The current hop never carries a longer summary
of itself: beside the high-resolution sections above, a summary gets read instead of them.

### Prior sessions

One table row per PRIOR hop, in chain order, copied forward verbatim by the script and appended
to, never authored:

```markdown
| date | session id | transcript | did/left | file |
|---|---|---|---|---|
| 2026-09-01T10:00:00Z | <UUID> | /home/<user>/.claude/projects/<slug>/<UUID>.jsonl | did: … · left: … | 20260901T100000Z-handoff-<topic>.md |
```

`new` copies the predecessor's rows unchanged and appends the predecessor's OWN row: its `date`,
`session_id`, and `transcript` from its frontmatter, its `## This session` line as `did/left`, its
filename. A shape-1 predecessor has no `This session` line, so its cell reads
`UNVERIFIED (shape-1 predecessor; brief: <first line of its Resumption brief>)`. Hop 1 writes the
literal line `None (first hop).` instead of a table. The validator checks that the predecessor's
rows are a prefix of this file's and that exactly one row was added.

This table plus the frontmatter `chain:` is how a fresh session sees the whole chain from ONE
file: high-resolution for the last session (the sections above), one pointer-backed line per
session before it (this table, each row naming the file and transcript to open for more).

### Resume prompt

The final section, always. It stores the copy/paste resume prompt exactly as it is emitted on
screen: the copy instruction, the two U+2500 rails with the prompt between them, and the
below-rail lines. The on-screen rails block IS this section, printed by
`save_point.py emit <file>`, never regenerated from the conversation. Every rule about what goes
between the rails (the directive, `Prior session:`, `Handoff origin:`, `Next:`, `Then:`, the
`/goal` first line) is owned by [`save-point.md`](save-point.md) "Emit the copy/paste resume
prompt", full-path block. `new` writes every line of it except the `Next:` headlines and the
optional `/goal` and re-arm slots.

## How this document is referenced elsewhere

The emitted resume directive points at the handoff FILE and names exactly one section — `Original
goal`, by name and never by number — because its alignment clause has to say what the resuming
session confirms; `/session-flow:keep-going`, `/session-flow:reanchor`, and the handoff enforcement
checklist name that same section for the same reason. Renaming §1 therefore requires an edit to
those surfaces. Three more sections are read by name: `## Resume prompt` by `save_point.py emit`,
`/session-flow:find-handoff` rung 1, and `/session-flow:continue-in-background`; `## This session`
and `## Prior sessions` by `save_point.py new` when it builds the successor's table. Renaming or
reordering any of those four requires a coordinated change of the script and those consumers;
renaming or reordering the rest still requires none, and no change here orphans handoffs already
written to disk (shape-1 files are never rewritten).

Consumers cite this section list rather than restating it. A copy of the list in another file
drifts silently — it has before.

## Full-path write procedure

Write the file into the handoff location (`save-point.md` "Where save-points live"). The
procedure is: resolve the memory root, run the existing guards, run `new`, fill the slots, run
`validate`, then `emit`. Every step that needs no judgment is the script's; the model touches only
the `<!-- FILL: … -->` slots.

```bash
TOPIC=<short-kebab-topic>                  # e.g. plan-rev2, retry-loop, post-merge

# 1. Memory root via the shared helper (the retro skill's Phase 1.1 is the worked
#    call form) — never assume the literal .work. DECLARED_MEMORY_DIR is a root
#    you inferred from CLAUDE.md / .claude/rules, or empty.
MEMORY_ROOT=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/retro/scripts/parse-concern-value.sh" \
  .claude/topic-docs.yaml memory_dir "${DECLARED_MEMORY_DIR:-}")
MEMORY_ROOT="${MEMORY_ROOT:-.work}"

# 2. Refuse a memory root at/above the repo root before the self-ignore guard can
#    touch the consumer's root .gitignore.
memory_root_is_repo_root() {
  local raw="${1//\\//}" segment
  local -a segments=() stack=()
  IFS='/' read -r -a segments <<< "$raw"
  for segment in "${segments[@]}"; do
    case "$segment" in
      '' | .) ;;
      ..)
        ((${#stack[@]} > 0)) || return 0 # at or above the repo root is invalid
        unset 'stack[${#stack[@]}-1]'
        ;;
      *) stack+=("$segment") ;;
    esac
  done
  ((${#stack[@]} == 0))
}
REPO_ROOT=$(git rev-parse --show-toplevel)
MEMORY_ROOT_COMPARE="${MEMORY_ROOT//\\//}"
if memory_root_is_repo_root "$MEMORY_ROOT" ||
  [[ "${MEMORY_ROOT_COMPARE%/}" == "${REPO_ROOT%/}" ]]; then
  echo "Invalid memory_dir: must resolve to a dedicated directory below the repository root" >&2
  exit 1
fi

DIR="$MEMORY_ROOT/handoffs"                # resolved per save-point.md "Where save-points live"

# 3. Self-ignore guard (new location only; the session's FIRST memory-tier write —
#    skip when already verified this session): the resolved memory root must
#    gitignore itself. `new` re-verifies this and refuses without it; it never
#    writes the file itself, so this step is the only place the guard is created.
mkdir -p "$DIR"
if [[ "$DIR" == "$MEMORY_ROOT"/* ]]; then
  grep -qx '\*' "$MEMORY_ROOT/.gitignore" 2>/dev/null \
    || printf '*\n' >> "$MEMORY_ROOT/.gitignore"   # announce this write to the user
fi

# 4. Interpreter ladder (the retro skill's form): Python 3.10+, stdlib only.
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 \
     && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PY="$c"; break
  fi
done
# PY empty → the Python-absent fallback (below); never a silent skip.

# 5. Skeleton. Exactly one of --previous / --no-previous (see "Chain continuity").
#    `new` reads CLAUDE_CODE_SESSION_ID itself and prints the file's absolute
#    forward-slash path: reuse THAT string for every later step (Edit, validate,
#    emit, the directive); never recompute the path in bash.
SAVE_POINT="${CLAUDE_PLUGIN_ROOT}/scripts/save_point.py"
FILE=$("$PY" -X utf8 "$SAVE_POINT" new --topic "$TOPIC" --memory-dir "$MEMORY_ROOT" --no-previous)
#   or, continuing a prior handoff's task:
# FILE=$("$PY" -X utf8 "$SAVE_POINT" new --topic "$TOPIC" --memory-dir "$MEMORY_ROOT" \
#          --previous "$DIR/<prior>-handoff-<topic>.md")

# 6. Fill every `<!-- FILL: … -->` slot in $FILE with the Edit tool (delete the
#    optional ones: goal-rearm, below-rail, <section>-new). Touch nothing else.
# 7. Validate; exit 0 gates the rails (save-point.md "Emit the copy/paste resume prompt").
"$PY" -X utf8 "$SAVE_POINT" validate "$FILE"
# 8. Print the stored resume prompt; paste its output on screen verbatim.
"$PY" -X utf8 "$SAVE_POINT" emit "$FILE"
```

`new` exits 0 and prints the path it wrote; 1 when it refuses (memory root at or above the repo
root, self-ignore guard missing, no session UUID, a non-UUID or bridge-shaped id, unreadable
predecessor, target already exists) with the reason on stderr; 2 on usage (neither or both
predecessor flags). It never overwrites. A refusal for a missing or non-UUID session id routes the
save-point to the prompt-only path with that reason stated (`save-point.md` "Choosing the path");
every other refusal names its fix.

**Python-absent fallback.** When the ladder finds no Python 3.10+, say so in one line
(`validator unavailable: no python3/python on PATH`), write the shape-2 file by hand from this
document (frontmatter below, the 17 headings in order, the `## Resume prompt` section in the
engine doc's full-path form), mark the checklist box `validate: SKIPPED (no interpreter)`, and
still emit the rails from the file's `## Resume prompt` section. Never a shape-1 file, never a
silent skip.

### Frontmatter shape 2

```yaml
---
type: handoff
handoff_shape: 2
date: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
topic: <kebab>
session_id: <UUID>                        # REQUIRED — CLAUDE_CODE_SESSION_ID at write time
transcript: <absolute path>.jsonl         # resolved + stat'ed at write, else
                                          # unresolved (session <UUID>, projects-root <dir>)
previous_handoff: <prior-filename>.md     # CONDITIONAL — omit at the first hop of a task
chain:                                    # bare filenames, root first, this file last
  - <root-filename>.md
  - <this-filename>.md
---
```

`new` writes every key. `handoff_shape: 2` is what the validator keys its checks on: a file
without the key is shape 1 (one WARN, checks skipped, exit 0); a value higher than the validator
knows is a hard failure that says "read it, do not rewrite it" (exit 3), never a partial pass.

`session_id` captures the current session for downstream chain-walkers (the sibling `retro` skill's
transcript parser, `find-handoff`'s chain validation) and is the id the below-rail
`claude --resume` line reopens. It is `CLAUDE_CODE_SESSION_ID`, which the Bash tool subprocess sets
(Claude Code v2.1.132+; resolve it via Bash, skill markdown does not template-expand env vars). It
must be a UUID with a transcript to match: `new` refuses an unset value and a non-UUID (a bridge
session's `cse_…` id, which `CLAUDE_CODE_BRIDGE_SESSION_ID` carries and is never read), and the
literal `unknown` shape 1 allowed is no longer a value. `transcript` is the session's own on-disk
record, resolved by the documented `~/.claude/projects/*/<session_id>.jsonl` glob and `stat`ed at
write; when the glob misses, the honest `unresolved (…)` value is stored (WARN on validate, FAIL
under `--strict-transcript`) and a later reader re-runs the same glob.

`previous_handoff` (the prior file's bare name, relative to the handoff directory, never a
`handoffs/`-prefixed path) is the backward chain pointer — the walker resolves the prior session's
id by reading that file's own `session_id`, so the pointer is stored once rather than in two fields
that can disagree. `chain:` is the whole chain root-first, the predecessor's `chain:` plus this
file; hop 1 is `[self]`, hop 2 from a shape-1 predecessor is `[predecessor, self]`. There is no
`hop` field: the hop number is `len(chain)`. The `type: handoff` frontmatter is also part of the
stable detection contract `/session-flow:find-handoff` keys off to recover a lost handoff (see
[`save-point.md`](save-point.md) "Detection contract").

### Chain continuity, same task only

Pass `--previous <file>` ONLY when this session actually continued that handoff's work: it resumed
from that handoff (the resume prompt loaded it), or the task/topic clearly matches. Pass
`--no-previous` otherwise; `new` requires exactly one of the two and never picks a file itself. A
shared handoff directory accumulates entries from unrelated tasks — pointing at the newest file
regardless would splice unrelated sessions into one chain, and a later `/session-flow:retro` would
aggregate stale transcripts and decisions as if they belonged to the current work. The first
handoff of a NEW task is `--no-previous`, even when older, unrelated handoffs exist in the
directory. Older entries lacking `session_id` cause chain-walkers to break cleanly at the first
absent field.

**Carrying the goal forward — read it off disk, never out of memory.** With `--previous`, `new`
opens that file and reproduces its `Original goal` verbatim quote and every recorded amendment
into this handoff unchanged, then the five cumulative sections and the `## Prior sessions` rows.
Rebuilding the goal from the conversation is the drift vector itself: the conversation is what
already lost it, and each rebuild is individually plausible, which is why the loss is invisible
until many hops later. The prior file is on disk and one read away — a writer that did not open it
has not carried the goal forward, whatever its text ends up saying. Same rule as the live
`TaskList` call: the check is that the read happened, not that the result looks right. The
validator checks the copy: the predecessor's `chain:`, its `## Prior sessions` rows, and every
cumulative entry must survive in the successor (in place or under `Superseded:`).

### Legacy predecessors and unfinished skeletons

**Shape-1 predecessors are read, never rewritten.** `--previous` accepts a shape-1 file. `new`
maps it: an absent cumulative section becomes `None. (shape-1 predecessor had no <section>)`; the
older 7-section body (`## Task`, `## Progress`, `## Decisions made`, …) is NOT aliased onto the
14-section names; an absent `Original goal` becomes a
`<!-- FILL: goal — RECONSTRUCTED … -->` slot that the validator refuses to pass while empty or
placeholder-shaped (settle the goal with the user, then fill it); the `Opening ask:` pointer gains
`(shape-1 root, no verbatim ask recorded)`; its `## Prior sessions` row carries the
`UNVERIFIED (shape-1 predecessor; brief: …)` cell.

**A predecessor that fails shape-2 validation** (or a hand-written Python-absent file) is still
copied forward: every carried entry is prefixed `UNVERIFIED (predecessor failed validation):`,
and `validate` on the successor downgrades the predecessor-derived checks (chain prefix, Prior
sessions prefix) to WARN naming the predecessor's failure, so one bad hop never blocks every later
hop. The predecessor is never rewritten. Validation looks one level back only; it does not walk the
chain.

**Unfinished skeletons stay on disk and are never a save-point.** A `new` run that was never
filled (compaction mid-write, a fix loop that ended `UNVALIDATED`) leaves a `type: handoff` file
with `<!-- FILL` slots. `validate` fails it, `emit` refuses it (exit 1), `find-handoff` rung 1 skips
it and names it as unfinished, and `continue-in-background` cannot launch from it. `new` never
overwrites an existing target, so a re-run writes a new timestamped file beside it. Cleanup is
user-controlled, like every other handoff file.

Multiple handoffs accumulate in the directory — fine; ISO timestamps keep them ordered, and the
newest entry is the resume point. A continuing handoff carries the prior one's unfinished work
forward: what was still open there becomes the starting position here.
