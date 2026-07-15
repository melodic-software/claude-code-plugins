# Audit Workflow

Execute the codified checklist from [../reference/criteria.md](../reference/criteria.md) against all
instruction/memory files.

## Step 1: Discovery

Find files in scope:

```bash
# CLAUDE.md files
find . -maxdepth 1 -name "CLAUDE.md" -o -name "CLAUDE.local.md" 2>/dev/null

# Rules files
find .claude/rules -name "*.md" -type f 2>/dev/null

# Auto-memory — CURRENT repo only. A bare `~/.claude/projects/*/memory/` glob
# matches every project on a multi-project machine and resolves alphabetical-first
# to the WRONG repo; the bundled resolver derives this repo's project-dir slug.
MEMORY_DIR=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/health/scripts/resolve-memory-dir.sh")
ls "$MEMORY_DIR"/*.md 2>/dev/null
```

For each file found, record: path, line count, visible line count (excluding HTML comments).

## Step 2: Run checks

Read [../reference/criteria.md](../reference/criteria.md), then execute every applicable check against
each discovered file. Apply by entity type:

- **C1-C8**: CLAUDE.md and CLAUDE.local.md
- **R1-R4**: `.claude/rules/` files
- **C7/R3 (currency)**: version pins and counts are checked against the repo's own pin files
  (`global.json`, `.nvmrc`, `.python-version`, `.mcp.json`, or ecosystem equivalents). File-path-existence
  currency is **agent judgment**: read each path reference in context — instructional files cite
  non-existent paths on purpose (examples, counter-examples, future-deferred refs, regex patterns),
  so a blind existence check false-flags heavily. Judgment is the correct tool for that half
- **M1-M4**: Auto-memory files (doc-derived health checks)
- **M2 (deterministic backing)**: run
  `bash "${CLAUDE_PLUGIN_ROOT}/skills/health/scripts/memory-index-refs-check.sh"` for
  index↔topic-file integrity — forward (index links an absent file) AND reverse (topic file present
  but not indexed, the orphan direction). Fold WARN lines into the report; do NOT hand-derive what the
  script computes
- **RD1**: Always-loaded rules layer (reverse-drift orphan check; deterministic-WARN). Run
  `bash "${CLAUDE_PLUGIN_ROOT}/skills/health/scripts/orphan-rule-check.sh"` and fold each WARN
  line into the report — do NOT re-derive by hand
- **REPO checks**: any additional criteria or documented exemptions the consuming repo's own
  `CLAUDE.md` / `.claude/rules/` declare for its instruction layer (see SKILL.md
  "Consumer-convention extension seam")

For each check:

1. Read the "How to check" instructions literally
2. Execute the check steps
3. Record the finding with severity (FAIL/WARN/INFO) or PASS
4. Include the specific evidence (line count, file path, contradicting text)

**Be mechanical, not interpretive.** The criteria file defines what passes and fails. Apply as
written. Same criteria = same results.

## Step 3: Cross-file consistency check (C6)

After per-file checks, cross-reference:

1. Compare CLAUDE.md sections against `.claude/rules/` for contradictions
2. Compare CLAUDE.md against CLAUDE.local.md for redundancy
3. Check if any CLAUDE.md instruction is already enforced by rule, hook, or analyzer

## Step 4: Generate report

Use the output format from criteria.md. Save to `${CLAUDE_PLUGIN_DATA}/health/last-audit.md`
(create the directory if absent — audit output stays contributor-local because it covers personal
auto-memory; see SKILL.md "Report mode").

Present the report to the user with:

1. Summary counts (FAIL/WARN/INFO/PASS)
2. All FAIL findings first (must fix)
3. WARN findings grouped by check type
4. INFO findings (informational only)
5. Token cost breakdown (from `/context` if available)

## Step 5: Suggest next action

Based on findings:

- If FAILs exist: suggest the `fix` action to address them
- If only WARNs: present as optional improvements, ask if user wants to fix
- If all PASS: report clean health, suggest scheduling periodic re-audit
