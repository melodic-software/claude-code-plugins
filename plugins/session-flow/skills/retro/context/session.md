# Session Mode — Full 5-Phase Retrospective

Comprehensive post-session analysis. Default mode and most thorough — use at end of session or
after a PR merges.

## Phase 1: Extract (automated metrics)

> Skip this phase if the user explicitly requests it, or if the parser errors (exit 2) — report the
> error and continue with conversation-context analysis only.

### Phase 1.0: Discover the session chain (multi-session-aware)

When handoff save-points exist (the sibling `handoff` skill's directory — the resolved
`<memory_dir>/handoffs/` (default `.work/handoffs/`), or the consuming repo's documented
location), the retro analyzes EVERY chained session across
`/handoff` + `/clear` cycles, not just the current one. The parser walks the chain itself via
`--chain-from` (newest handoff file → its `previous_handoff` pointer → repeat; breaks cleanly at
the first entry lacking `session_id`).

**Continuity gate first.** Use `--chain-from` ONLY when the newest handoff belongs to the current
work: this session resumed from it (the resume prompt loaded it), this session wrote it, or its
`topic`/Task section clearly matches the current task. A shared directory can hold save-points
from completed or abandoned tasks — chaining from an unrelated newest file would splice stale
sessions into this retro's aggregate. When continuity is absent or unclear, fall back to the
single-session form.

### Phase 1.1: Parse the transcript(s)

Resolve `SESSION_DATA_DIR` per SKILL.md "Paths", then:

```bash
PARSER="${CLAUDE_PLUGIN_ROOT}/skills/retro/scripts/parse_transcript.py"

# Pick an interpreter that is actually Python 3.10+ (a bare `python` may be older):
PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 \
     && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    PY="$c"; break
  fi
done

# Single-session form:
"$PY" "$PARSER" --sessions "${CLAUDE_CODE_SESSION_ID}" --base "$SESSION_DATA_DIR"

# Multi-session form (handoff chain exists). Derive HANDOFF_DIR from the resolved
# memory_dir via the shared parser (quote-aware, comment-safe). Resolution:
# concern-file memory_dir key -> a save-point convention you inferred from
# CLAUDE.md / .claude/rules (rung 2 — pass it as DECLARED_SAVEPOINT; prose is an
# inference source, not a machine key) -> the plugin default .work. For the full
# resolution order see the handoff skill's "Where handoffs live".
MEMORY_DIR=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/retro/scripts/parse-concern-value.sh" \
  .claude/topic-docs.yaml memory_dir "${DECLARED_SAVEPOINT:-}")
MEMORY_DIR="${MEMORY_DIR:-.work}"
HANDOFF_DIR="$MEMORY_DIR/handoffs"
NEWEST=$(ls -1 "$HANDOFF_DIR"/*-handoff-*.md 2>/dev/null | sort | tail -1)
"$PY" "$PARSER" --chain-from "$NEWEST" --current-session "${CLAUDE_CODE_SESSION_ID}" --base "$SESSION_DATA_DIR"
```

If `PY` resolves empty (no Python 3.10+ available), skip metrics extraction and note why. The
parser is stdlib-only.

### Script contract

JSON to stdout: `status` / `summary`, plus per-session `data` (session info, turns, tokens, tool
usage + rejections, compactions, turn durations, stop reasons, files modified, subagents, errors)
and — in multi-session form — an `aggregate` block. Exit codes: 0 = success, 1 = warning,
2 = error.

### Present metrics

Format as two GFM tables — **Session Summary** (duration, model, assistant turns, human messages,
compactions, total context tokens, tool rejections, subagent count) and **Tool Distribution**
(tool / count / %, sorted descending).

---

## Session type detection

Before analysis, identify the session type from conversation context — it calibrates Phase 5
scoring:

- **Coding** — code changes made. Score Technical quality on code quality
- **Planning/Design** — architecture decisions, documentation, API design. Score on design
  reasoning and decision quality
- **Research** — investigation, comparison, learning. Score on research rigor and conclusion
  quality
- **Mixed** — score each task individually, then aggregate

---

## Phase 2: Analyze (qualitative assessment)

Analyze across five dimensions using BOTH Phase 1 metrics AND conversation context. Derive the
convention baseline from the consuming repo's own instruction files: its `CLAUDE.md`, the
`.claude/rules/` files relevant to the ecosystems touched this session, and any review-criteria
docs it names. Read only the relevant ones.

### 2A. Error analysis

- Mistakes made and corrected; failed approaches and wasted cycles
- Incorrect assumptions that had to be revised
- Build or test failures caused by changes
- Stale information used without verification

### 2B. Behavioral assessment

Check adherence to the staged workflow (the sibling `workflow` skill, or the consuming repo's own
documented workflow if it defines one):

- Which stages were followed? Which were skipped, and was the skip justified?
- Was research performed for load-bearing claims, with current authoritative sources?
- Was a plan written and approved for non-trivial work? Stress-tested when blast radius was wide?
- Was uncertainty flagged when verification wasn't possible?

### 2C. Feedback regression check

One of the most valuable parts — prevents repeating previously corrected mistakes. If the consumer
uses Claude Code auto-memory (`<SESSION_DATA_DIR>/memory/` exists), read the `feedback_*.md` files
and check whether this session violated any saved guidance:

| Memory file | Violated? | Evidence |
| --- | --- | --- |
| `feedback_example.md` | YES / No / N/A | (specific session behavior) |

Flag regressions prominently — a regression means a previously corrected behavior has resurfaced.
No memory directory → note "auto-memory not in use" and move on.

### 2D. Technical assessment

Evaluate code changes (if any) against the consuming repo's own engineering conventions. If no
code changes were made, note "N/A" and skip.

### 2E. Efficiency assessment

- Compaction count — were compactions avoidable (earlier `/handoff`, tighter reads)?
- Parallel tool-call opportunities missed; redundant file reads
- Subagent usage — appropriate delegation?
- Longest/slowest turns — what caused them?

### Phase 2 output

Present findings as a GFM table per dimension:

| # | Severity | Finding | Evidence | Impact |
| --- | --- | --- | --- | --- |

---

## Phase 3: Recommend (improvements)

Map each Phase 2 finding to an improvement target. Also identify improvements not tied to specific
findings.

**Research before recommending.** For any recommendation involving skills, hooks, agents, or Claude
Code configuration: verify it against current official docs before presenting — never recommend
features from training-data assumptions.

**Load the catalog.** Read `${CLAUDE_PLUGIN_ROOT}/skills/retro/reference/ecosystem-improvement-catalog.md`
before filling the table — the placement decision tree and the per-target recommendation formats
(memory, rules, hooks, skills, agents, MCP servers, settings) live there.

Present as a GFM table with a **Scope** column distinguishing:

- **project** — git-tracked, shared with the team (the repo's `CLAUDE.md`, rules, skills, settings)
- **personal** — machine-specific, NOT committed (auto-memory, user settings)

| # | Target | Scope | Type | Recommendation | Justification | Priority |
| --- | --- | --- | --- | --- | --- | --- |

### Skill candidate analysis (REQUIRED — always include)

Evaluate whether the session revealed a genuinely repeatable multi-step workflow worth
encapsulating as a skill:

| Factor | Minimum for a skill | Skip if |
| --- | --- | --- |
| Steps | 3+ distinct phases | Linear, 1-2 step process |
| Reuse | Likely monthly+ | Truly one-off |
| Complexity | Requires judgment or branching | Simple command alias |
| Context | Needs reference files or rubrics | Self-evident workflow |

Always present the subsection — either candidate(s) with name/description/rationale, or "no
candidates" with a one-line explanation of what was considered.

### Follow-up candidates (REQUIRED — always include)

Evaluate whether the session produced follow-up work for the consumer's work-item tracker:
deferred research, discovered gaps (missing tests, undocumented conventions), research context
worth preserving. Present as a table, or "no candidates — session work was self-contained."

---

## Phase 4: Act (with user approval)

Group Phase 3 recommendations by action type, then **explicitly ask the user** which items to
execute — do not proceed without their response.

- **Personal (not committed):** proposed auto-memory entries — create only on approval
- **Project (already validated this session):** rule/instruction-file updates codifying what
  HAPPENED (a gotcha discovered through failures, a convention established through implementation).
  Apply on approval
- **Queue for follow-up (needs further research):** recommendations beyond what this session
  validated — list them; do NOT make those changes now

Apply the team-shared-first lens: if a learning generalizes to ANY contributor, it belongs in a
tracked surface (the repo's instruction files), not personal memory. Reserve auto-memory for facts
true only for this machine/person.

**Every approved codification follows the workflow** — verify the claim, cross-reference existing
content for duplication, then edit. No "just save it" shortcut.

End Phase 4 with an explicit question, e.g.: "Which of these recommendations should I execute now?
Reply with the numbers, 'all', or 'skip' to proceed to the summary."

---

## Phase 5: Summary

### Accomplishments

1-3 bullets of what the session achieved.

### Key learnings

- **Behavioral:** what to do differently next time
- **Technical:** patterns learned, gotchas discovered

### Actions taken

Checklist of memory saved / rules edited / items queued.

### Session health score

**Calibration:** read the score history at `${CLAUDE_PLUGIN_DATA}/scores/<project-slug>.md` if it
exists and note trends alongside this session's scores.

| Dimension | Score | Notes |
| --- | --- | --- |
| Workflow adherence | /10 | |
| Technical quality | /10 | calibrate to session type |
| Alignment | /10 | convention compliance + memory utilization |
| Efficiency | /10 | |
| Error rate | /10 | 10 = no errors |
| **Overall** | **/10** | weighted average |

**Scoring anchors** (consistency across sessions): 9-10 exemplary (all stages followed, no errors,
feedback respected); 7-8 good (minor gaps); 5-6 mixed (some stages skipped, recoverable errors);
3-4 below standard (multiple skips, regressions, avoidable errors); 1-2 poor (fundamental process
failures or incorrect code shipped).

Every dimension gets a numeric score; use N/A only when truly irrelevant.

### Score tracking

Append this session's scores to `${CLAUDE_PLUGIN_DATA}/scores/<project-slug>.md` (create the
directory and file with a header row on first use):

```markdown
| Date | Session | Type | Workflow | Technical | Alignment | Efficiency | Errors | Overall |
| 2026-03-21 | session-id-short | Coding | 8 | 7 | 8 | 8 | 9 | 8 |
```
