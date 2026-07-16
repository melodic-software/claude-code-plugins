# Leaf roster — fan-out surfaces

Single source of truth for the leaf surfaces this skill fans out across. Both the default lifecycle-tiered mode and run-everything mode cite this file — no duplicated roster.

## Finding-producing agents (this plugin)

| Agent | Role |
|---|---|
| `code-reviewer` | general quality / convention / design judgment |
| `security-reviewer` | OWASP / injection / secrets (P1–P5) |
| `architecture-guardian` | dependency direction / layer boundaries |
| `doc-drift-detector` | doc↔code drift (Stale / Missing / Aspirational) |

**EXCLUDED** (shipped in this plugin for other purposes — not diff-review leaves):

- `ecosystem-specialist` — build/test/lint PASS/FAIL, not a finding-producing diff review.
- `ci-log-auditor` — needs a CI run, not a working-tree diff.

## Ownerless slices (discovered from the consuming project)

When the project ships per-concern review criteria documents, each one becomes a slice leaf — a fresh subagent that reads that document plus the diff and reviews against ONLY that document's criteria (prompt template: this plugin's `quality-gate` skill, per-slice mode).

**Discovery recipe (run at dispatch time — never a hardcoded list):**

1. Glob the common shapes: `review/*.md`, `review/*/README.md`, `docs/review/*.md`, plus any location the project's `CLAUDE.md` / rules name as review criteria.
2. **De-overlap:** drop the criteria documents a dispatched agent already covers as its primary concern — code quality, security, and architecture docs are agent-owned (a slice-subagent re-reading the same criteria on the identical diff is pure waste). Everything else is ownerless and dispatches.
3. Projects with no review-criteria docs simply have zero slice leaves — the agent set still runs.

**Orchestrator↔agent overlap is NOT de-overlapped.** Orchestrator plugins bring different prompts and lenses; running a plugin and a custom agent on the same dimension is intentional adversarial breadth — the normalization pipeline's dedup stage handles the near-duplicates. De-overlap applies ONLY to agent↔own-criteria-doc.

## Total roster

4 agents + N discovered ownerless slices (N varies by project). Report the resolved roster in the tier-transparency line before dispatch.
