# Handoff document structure + full-path write procedure

Reference consulted while WRITING a full-path handoff (the delivery decision logic — STOP gate,
launch gates, exit checklists — stays in the citing skill's `SKILL.md`; path choice and destination
resolution live in the sibling `save-point.md` engine doc).

The reader is a session with NO prior context. It will act on this file. Be specific — vague
handoffs cost the next session a re-investigation, which is the cost this document exists to avoid.

## Body sections

Ordered so the cheapest useful layer comes first. A reader can stop after **Resumption brief** and
still take the correct next action; everything below it is there for the reader who needs more.

| Order | Section | Owns |
|---|---|---|
| 1 | Resumption brief | the resumption decision |
| 2 | Completion criteria | what "done" means, observably |
| 3 | Constraints that must hold | invariants whose violation breaks the work |
| 4 | Environment to re-establish | machine and session state `/clear` destroyed |
| 5 | Side effects already applied | persistent effects that must NOT be repeated |
| 6 | File roles in this work | which file plays which role, and how far its change got |
| 7 | Decisions already settled | closed choices, with the reasoning that closed them |
| 8 | Approaches tried and abandoned | directions walked and rejected |
| 9 | Findings that cost effort to discover | non-obvious system facts, expensive to re-derive |
| 10 | Remaining actions, in order | every action still to take, sequenced |
| 11 | Open questions to investigate | unknowns the resuming session can resolve itself |
| 12 | Blockers needing an outside decision | work that cannot proceed without someone else |
| 13 | Suggested skills | which skills to invoke for the remaining work |

**Every section is always present.** A section with nothing to report reads `None.` plus a half-line
of reason. A cold reader cannot otherwise tell "nothing to report" from "the author forgot", and the
absence is itself load-bearing — "no approaches abandoned" tells the resumer the ground is untrodden.

**Emit body sections at `##`.** This document nests them under its own heading, so they appear here
one level deeper than they are written.

**Layering is not truncation.** No section carries a length budget except the brief. Progressive
disclosure governs the ORDER facts are met in, never whether they survive. Sections 7, 8, and 9
exist specifically for what a summarizer discards first — rationale, negative knowledge, and
hard-won facts — because those read as "old" while being the most expensive to rediscover.

**Provenance: verified this session, or marked.** A status claim earns plain statement only when
this session verified it — a command run, a file read, an output observed. Anything inherited — a
prior handoff's assertion, an issue label, a remembered state — is written with an explicit
`UNVERIFIED (<source>)` marker, because the resuming session treats an unmarked claim as fact and
builds on it: an inherited claim is a claim to falsify, not a fact to forward. The met/unmet marks
in Completion criteria carry the same rule (see the evidence rule in the citing skill's gotchas).

### Resumption brief

Six lines maximum. The one section a reader may stop at.

Carries: when it was written and against which branch or commit, the goal in one line, where the
work stands in one line, and the single next concrete action. Name the section that governs that
action so a reader wanting more is routed rather than left searching.

The brief names the FIRST action only. It always points at `Remaining actions, in order`, which owns
the full sequence — otherwise a session that completes the one named action has nothing to go on.

This deliberately restates facts owned below — it is an onboarding surface on a document read cold.
The six-line cap bounds the drift, and naming each owning section keeps the pointer honest.

Close it with the one obligation the brief cannot carry: an agent about to change anything reads
**Constraints that must hold** first.

### Completion criteria

One line of why the work exists, then each criterion as an observable test with a met/unmet mark.

A criterion nobody can check is not a criterion — rewrite until a command or a diff settles it.

```markdown
- [x] `dotnet test` green on the affected projects
- [ ] the retry path is exercised by a test that fails without the fix
```

### Constraints that must hold

Invariants whose violation breaks the work. One testable assertion per line, each followed by the
consequence of violating it.

Only things that would actually break something. A preference is a decision — section 7.

Before closing the section, re-scan the conversation for *but*, *except*, *unless*, "the exception
is", "the corner case" — those words mark constraints that emerged mid-discussion and never rose to
a top-line bullet, and an omitted one is exactly what the resuming session ships as a bug.

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

A fact about how the system behaves belongs in section 9; a path you walked belongs here.

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

An action is something to *do*. An unknown to resolve is section 11; something you cannot proceed
on is section 12. Cross-reference those rather than duplicating them: an action that waits on a
blocker is listed here in its sequence position, marked as waiting, and named once in section 12.

The `Resumption brief` names only the first of these. This section owns the rest — it is the one
place the full sequence exists, so it survives when the brief's single action is done.

```markdown
1. Wire the retry policy into `OrderReader` (spec: `docs/adr/0012-retry-policy.md`).
2. Add the cancellation edge-case tests — the happy path is already covered.
3. Waiting on the staging credential grant: re-run the integration suite against staging (§12).
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

## How this document is referenced elsewhere

The emitted resume directive points at the handoff FILE and names no section. Renaming or
reordering a section here therefore requires no edit to `save-point.md`, and does not orphan
handoffs already written to disk.

Consumers cite this section list rather than restating it. A copy of the list in another file drifts
silently — it has before.

## Full-path write procedure

Write the file into the handoff location (`save-point.md` "Where save-points live"):

```bash
TS=$(date -u +%Y%m%dT%H%M%SZ)              # ISO basic — Windows-safe, no colons
TOPIC=<short-kebab-topic>                  # e.g. plan-rev2, retry-loop, post-merge
MEMORY_ROOT=.work                          # resolve via the shared parse-concern-value.sh helper
                                           # (retro skill's Phase 1.1 is the worked call form) —
                                           # never assume the literal .work
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-unknown}"

# Refuse a memory root at/above the repo root before the self-ignore guard can
# touch the consumer's root .gitignore.
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

# Candidate prior handoff (newest by timestamp) for the chain pointer — but
# only USE it when this session is a continuation of that handoff's task
# (see "Chain continuity" below).
PRIOR=$(ls -1 "$DIR"/*-handoff-*.md 2>/dev/null | sort | tail -1)

mkdir -p "$DIR"
# Self-ignore guard (new location only; the session's FIRST memory-tier write —
# skip when already verified this session): the resolved memory root must
# gitignore itself.
if [[ "$DIR" == "$MEMORY_ROOT"/* ]]; then
  grep -qx '\*' "$MEMORY_ROOT/.gitignore" 2>/dev/null \
    || printf '*\n' >> "$MEMORY_ROOT/.gitignore"   # announce this write to the user
fi
# Write: $DIR/${TS}-handoff-${TOPIC}.md
```

**Frontmatter shape:**

```yaml
---
type: handoff
date: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>   # date -u +%Y-%m-%dT%H:%M:%SZ
topic: <kebab>
session_id: <UUID>                        # REQUIRED — $CLAUDE_CODE_SESSION_ID at write time;
                                          # literal "unknown" when unset
previous_handoff: <prior-filename>.md     # CONDITIONAL — omit when no prior handoff exists
---
```

`session_id` captures the current session for downstream chain-walkers (the sibling `retro` skill's
transcript parser). `previous_handoff` (the prior file's name, relative to the handoff directory) is
the backward chain pointer — the walker resolves the prior session's id by reading that file's own
`session_id`, so the pointer is stored once rather than in two fields that can disagree. The
`type: handoff` frontmatter is also part of the stable detection contract
`/session-flow:find-handoff` keys off to recover a lost handoff (see
[`save-point.md`](save-point.md) "Detection contract").

**Chain continuity — same task only.** Emit `previous_handoff` ONLY when this session actually
continued the prior handoff's work: it resumed from that handoff (the resume prompt loaded it), or
the task/topic clearly matches. A shared handoff directory accumulates entries from unrelated tasks
— pointing at the newest file regardless would splice unrelated sessions into one chain, and a later
`/retro` would aggregate stale transcripts and decisions as if they belonged to the current work.
The first handoff of a NEW task omits the field, even when older, unrelated handoffs exist in the
directory. Older entries lacking `session_id` cause chain-walkers to break cleanly at the first
absent field.

`CLAUDE_CODE_SESSION_ID` is set in the Bash tool subprocess (Claude Code v2.1.132+). Resolve it via
Bash — skill markdown does not template-expand env vars.

Multiple handoffs accumulate in the directory — fine; ISO timestamps keep them ordered, and the
newest entry is the resume point. A continuing handoff carries the prior one's unfinished work
forward: what was still open there becomes the starting position here.
