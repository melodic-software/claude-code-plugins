# EventStorming Simulation Iteration Workflow

This document defines the repeatable process for improving the **output of a simulation run** — re-scoring boards, comparing a run against prior runs, correcting the model, and verifying the corrections. It is NOT the simulation itself; it is the quality loop `--evaluate` drives.

**Scope note (plugin vs authoring).** The consumer-facing loop is RUN → SCORE → COMPARE → DIFF → board-level FIX → VERIFY against the run's own boards and the plugin's data store. A handful of steps below (editing the skill's own reference docs or evaluation rubric — Step 5 "skill-doc" rows, all of Step 7 CODIFY) are **plugin-authoring** activities: they apply only when developing this plugin from source, because a consumer runs it from an immutable installed cache and cannot edit its reference files. When a consumer hits a genuine skill-level gap, the action is to **report it upstream** (open an issue against the plugin), not to edit the cached files.

**When to use this:** After any simulation run, when quality gaps are found, or when you want to validate that a run produced accurate results.

---

## The Iteration Cycle

```
┌─────────────┐
│  1. RUN     │  Run a simulation (any domain, any format subset)
└──────┬──────┘
       ▼
┌─────────────┐
│  2. SCORE   │  Score against the evaluation rubric (simulation-evaluation.md)
└──────┬──────┘
       ▼
┌─────────────┐
│  3. COMPARE │  Compare against source material (EPUB/PDF chapters)
└──────┬──────┘
       ▼
┌─────────────┐
│  4. DIFF    │  Compare against previous version metrics
└──────┬──────┘
       ▼
┌─────────────┐
│  5. FIX     │  Update skill docs, board corrections, memory
└──────┬──────┘
       ▼
┌─────────────┐
│  6. VERIFY  │  Re-run affected phases to verify fixes
└──────┬──────┘
       ▼
┌─────────────┐
│  7. CODIFY  │  Update evaluation rubric with new criteria
└──────┬──────┘
       │
       └──────► Back to 1 for next version
```

---

## Step 1: RUN — Execute a Simulation

**Inputs:**

- Domain to explore (can reuse Developer Conference or pick a new one)
- Format scope: Big Picture only, BP+PM, or BP+PM+DL
- Version number (increment from last run)

**Process:**

- Follow `agentic-simulation.md` exactly
- Run pre-simulation checklist from `simulation-evaluation.md`
- Execute all phases with checkpoints

**Outputs:**

- Miro board(s) with all building blocks
- Agent transcripts (event lists, narrative walk-throughs, policy corrections)
- Screenshot at each checkpoint

---

## Step 2: SCORE — Evaluate Against Rubric

**Inputs:** Board data + transcripts from Step 1

**Process:**

1. Read ALL board items (full pagination)
2. Score each criterion in `simulation-evaluation.md` rubric: Pass / Partial / Fail
3. Calculate weighted scores per phase and overall
4. Flag any Critical criteria that scored Fail

**Scoring rules:**

- Critical (3pts): Must Pass for the phase to be acceptable
- High (2pts): Should Pass; Partial is acceptable with documented reason
- Medium (1pt): Nice to have; Partial or Fail is acceptable

**Output:** Scored rubric with total per phase and overall percentage

---

## Step 3: COMPARE — Source Material Validation

**Inputs:** Scored rubric + EPUB source

**Process:**
For each criterion that scored Partial or Fail:

1. Read the corresponding book chapter (use chapter index in simulation-evaluation.md)
2. Extract the specific quote or description of what SHOULD happen
3. Document: "Source says X, we produced Y, the gap is Z"

For each phase overall:

1. Read the book's description of that phase
2. Compare the simulation output against the book's examples
3. Check: Are we using the right building blocks? Right colors? Right content conventions?
4. Check: Are we producing the right workshop dynamics? (Disagreements, duplicates, corrections)

**Output:** Gap analysis document: Expected (source) vs Actual (simulation) vs Gap (what to fix)

---

## Step 4: DIFF — Version Comparison

**Inputs:** Current version metrics + previous version metrics (from memory)

**Process:**

1. Fill in the version comparison template from `simulation-evaluation.md`
2. Compare each metric: improved, same, regressed?
3. For any regression: investigate why and flag as priority fix
4. For any improvement: document what caused it (prompt change? new gate? structural fix?)

**Output:** Version diff table showing progression

---

## Step 5: FIX — Apply Corrections

**Inputs:** Gap analysis from Step 3 + version diff from Step 4

**Process:**
Categorize each gap by fix location:

| Fix Type | Scope | Where to Fix | Examples |
|----------|-------|-------------|---------|
| **Board correction** | Consumer | Miro boards (via MCP) | Missing legend entries, misplaced stickies, missing UL terms |
| **Run-state update** | Consumer | `${CLAUDE_PLUGIN_DATA}/history.jsonl` | Updated metrics, new findings, version progression |
| **Prompt improvement** | Authoring only | agentic-simulation.md | Better persona prompts, missing focal moments, weak differentiation |
| **Process gate** | Authoring only | agentic-simulation.md | Missing checkpoint, insufficient event count gate, missing cleanup step |
| **Content gap** | Authoring only | Reference docs | Missing building block, incomplete phase description |
| **Evaluation gap** | Authoring only | simulation-evaluation.md | Missing rubric criterion, wrong scoring weight |

Consumer fixes apply to the current run. Authoring-only fixes edit the plugin's own files — a consumer cannot make them (immutable cache); report the gap upstream instead. Apply fixes in priority order: Critical failures > High gaps > Medium gaps

**Output:** List of files changed with what was fixed

---

## Step 6: VERIFY — Re-run Affected Phases

**Inputs:** List of fixes applied

**Process:**
For each fix, determine if it can be verified without a full re-run:

- **Board corrections:** Visual verification via screenshot — does the board now match the source?
- **Prompt improvements:** Requires re-running the affected phase with the new prompt on a test board
- **Process gates:** Requires re-running through the gate to verify it catches the issue
- **Content gaps:** Read the updated doc and verify it matches the source chapter

For prompt improvements and process gates: run a MINI simulation (single phase, 3 personas, same domain) to verify the fix works before committing to a full v(N+1) run.

**Output:** Verification results: each fix confirmed working or needs revision

---

## Step 7: CODIFY — Update Evaluation Infrastructure (plugin-authoring only)

**Applies only when developing this plugin from source** — a consumer running from the installed cache skips this step and instead reports skill-level gaps upstream (see the scope note at the top). The only consumer-facing carry-over is updating the run-state store (item 6).

**Inputs:** Verified fixes + new learnings

**Process:**

1. If a new gap type was discovered: add it as a rubric criterion in simulation-evaluation.md
2. If a scoring weight was wrong: adjust the weight
3. If a pre-simulation check was missing: add it to the checklist
4. If a new best practice emerged: add it to agentic-simulation.md
5. Update version comparison baselines in simulation-evaluation.md
6. Update the run-state store (`${CLAUDE_PLUGIN_DATA}/history.jsonl`) with new version metrics — consumer-facing

**Output:** Updated evaluation infrastructure ready for next iteration

---

## Quick Reference: What to Check When

### After EVERY simulation run

- Score the rubric
- Compare against source
- Update the run-state store (`${CLAUDE_PLUGIN_DATA}/history.jsonl`) with version metrics

### After finding a specific gap

- Fix the gap in the appropriate doc
- Verify with a targeted mini-run
- Add the gap as a rubric criterion if it's not already there

### Periodically (every 2-3 versions)

- Re-read the EPUB source chapters cover to cover — the book is on Leanpub and may be updated
- Check for new practitioner insights (web-research search — Perplexity MCP if present, else `WebSearch`: "EventStorming 2025 2026 new techniques")
- Review whether the evaluation rubric itself is still calibrated correctly
- Clean up old boards (keep only latest version)

### Before trusting the skill for a real domain

- Run at least 2 full iterations (Run → Score → Compare → Fix → Verify)
- Achieve 80%+ on the evaluation rubric across all phases
- Have zero Critical failures
- Verify bounded context identification produces meaningful boundaries (not just random groupings)
- Verify ubiquitous language terms are domain-specific (not generic definitions)
- Verify aggregate consolidation produces behavior-rich aggregates (not entity-per-table)

---

## Files in the Evaluation System

| File | Purpose |
|------|---------|
| `simulation-evaluation.md` | Rubric, checklists, chapter index, version comparison template |
| `iteration-workflow.md` | This file — the per-run quality loop (plus plugin-authoring steps) |
| `agentic-simulation.md` | The simulation execution guide |
| `${CLAUDE_PLUGIN_DATA}/history.jsonl` | Version history, board URLs, findings (per-plugin run-state store) |
| `agentic-simulation.md` "Session lifecycle" | Process learning: MCP preflight — test the Miro server before starting |
| `agentic-simulation.md` (Agent-invocation guidance) | Process learning: real Agent invocations, not scripted |
| `miro-integration.md` (frame positioning) | Process learning: frame positioning gotchas |

---

## Trust Criteria

The skill is ready for production use on a real domain when:

1. **Rubric score >= 80%** across all phases for at least 2 consecutive runs
2. **Zero Critical failures** in the most recent run
3. **Source fidelity confirmed** — all phases match Brandolini's book descriptions
4. **Bounded contexts are meaningful** — divergence signals produce real BC boundaries, not noise
5. **Ubiquitous language is captured** — 5+ domain-specific terms with precise definitions
6. **Aggregates are behavior-rich** — aggregate:command ratio <= 1:1 after consolidation
7. **MCP integration works** — board creation, sticky placement, and reading all via MCP tools
8. **Visual verification passes** — screenshots show correct colors, layout, and density at each checkpoint
9. **Version progression is positive** — each version scores equal or better than the previous
10. **No known gaps** — all identified gaps from the gap analysis are either fixed or explicitly deferred with rationale
