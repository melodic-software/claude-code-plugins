# Handoff document structure + full-path write procedure

Reference consulted while WRITING a full-path handoff (the delivery decision logic — STOP gate,
launch gates, exit checklists — stays in the citing skill's `SKILL.md`; path choice and destination
resolution live in the sibling `save-point.md` engine doc). Walk every section; be specific — vague
handoffs cost the next session a re-investigation.

## The eight body sections

### Task

One paragraph. What are we working on? What does "done" look like? If a contract or approved plan
exists on disk, reference it rather than restating.

### Progress

What's already done:

- **Committed** — list commit SHAs and one-line summaries
- **Uncommitted but working** — files changed and why
- **In progress** — what's partially done (never commit partial work — describe it in prose)

### Decisions made

Bullet list. Non-obvious choices + rationale (often a past incident or research finding):

- Decision → rationale
- Example: "Using `Result<T>` instead of exceptions for not-found → railway-oriented style is the
  project default per its CLAUDE.md"

Goal: the next session trusts prior decisions without rediscovering them.

### Files modified

List, one-line rationale each:

- `path/to/file` — added handler X, wired into DI
- `path/to/test` — covers happy path; still need edge cases

### Tried and ruled out

The most valuable section. Failed approaches and WHY they failed:

- Approach → why it didn't work (specific error, constraint, trade-off)

Without this the next session repeats the dead end. Budget detail generously here.

### Open questions / next steps

Actionable items ordered by priority:

1. [ ] Next immediate action
2. [ ] Question blocking progress (who to ask, how to test)
3. [ ] Follow-up once the blocker resolves

### Suggested skills

Forward pointers: which skills the resuming session should invoke for the remaining work, each tied
to a concrete remaining item — not generic recommendations. Use fully-qualified names
(`plugin:skill`) and qualify each with "if installed": the resuming session may run under a
different plugin set, and a missing skill degrades to doing that work inline. When no skill maps to
the remaining work, write "None — remaining work runs inline" rather than omitting the section.

### Files to review on resume

Entry points the next session reads first:

- Primary: the file holding the current focus
- Related: its tests, the relevant convention/rule files
- Any plan/checklist artifacts and prior handoff entries

## TaskList snapshot + reconstitute instructions

TaskList state is in-memory only — `/clear` blows it away. Capture it verbatim so the resuming
session recreates it via `TaskCreate`.

**Before writing this section:** call `TaskList` to fetch live state. Render every task with its
current status:

| Glyph | Status |
|-------|--------|
| `[x]` | completed |
| `[~]` | in_progress |
| `[ ]` | pending |
| `[!]` | blocked |

Body shape:

````markdown
### TaskList snapshot

- [x] Profile update — done; unclear handles investigated.
- [~] Full scan — wave 1 initialized (0/178 complete). Drive the loop in the fresh session.
- [ ] Full pipeline run — collection → dedup → ranking → synthesis.

### Reconstitute on resume

Fresh session MUST recreate this TaskList before resuming. Run the TaskCreate calls in this exact
order (preserves numbering):

```text
TaskCreate(subject="Profile update", description="...")  → status=completed via TaskUpdate
TaskCreate(subject="Full scan", description="...")       → status=in_progress via TaskUpdate
TaskCreate(subject="Full pipeline run", description="...") → status=pending (default)
```
````

**Exception:** when 0 active tasks OR all `completed`, omit this section — nothing to reconstitute.

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
PRIOR_SID=""
if [[ -n "$PRIOR" ]]; then
  PRIOR_SID=$(awk '/^session_id:/ {print $2; exit}' "$PRIOR")
fi

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
previous_session_id: <UUID>               # CONDITIONAL — omit when no prior handoff exists
---
```

`session_id` captures the current session for downstream chain-walkers (the sibling `retro` skill's
transcript parser). `previous_handoff` (the prior file's name, relative to the handoff directory) +
`previous_session_id` create the backward chain pointer.

**Chain continuity — same task only.** Emit `previous_handoff` / `previous_session_id` ONLY when
this session actually continued the prior handoff's work: it resumed from that handoff (the resume
prompt loaded it), or the task/topic clearly matches. A shared handoff directory accumulates
entries from unrelated tasks — pointing at the newest file regardless would splice unrelated
sessions into one chain, and a later `/retro` would aggregate stale transcripts and decisions as if
they belonged to the current work. The first handoff of a NEW task has neither field, even when
older, unrelated handoffs exist in the directory. Older entries lacking `session_id` cause
chain-walkers to break cleanly at the first absent field.

`CLAUDE_CODE_SESSION_ID` is set in the Bash tool subprocess (Claude Code v2.1.132+). Resolve it via
Bash — skill markdown does not template-expand env vars.

Multiple handoffs accumulate in the directory — fine; ISO timestamps keep them ordered, and the
newest entry is the resume point. The newest handoff reads the previous one's "Next steps" as its
"Progress" starting point.
