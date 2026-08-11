# Audit Workflow

Execute the codified checklist from [../reference/criteria.md](../reference/criteria.md) against all
instruction/memory files.

## Step 1: Discovery

Find files in scope:

```bash
# CLAUDE.md and rules files, PROJECT and USER scope, each tagged with its scope.
# The bundled script resolves ${CLAUDE_CONFIG_DIR:-$HOME/.claude} the same way the
# memory-dir resolver does. A bare `find .` sees project scope only, which left
# ~/.claude/CLAUDE.md and ~/.claude/rules/*.md audited by nothing — they load in
# every session, and audit-instructions' surface partition hands them here by name.
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/discover-instruction-surfaces.sh"
# Output: <scope>\t<kind>\t<path>  — scope is `project` or `user`

# Auto-memory — CURRENT repo only. A bare `~/.claude/projects/*/memory/` glob
# matches every project on a multi-project machine and resolves alphabetical-first
# to the WRONG repo; the bundled resolver derives this repo's project-dir slug.
MEMORY_DIR=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/resolve-memory-dir.sh")
ls "$MEMORY_DIR"/*.md 2>/dev/null
```

For each file found, record: **scope**, path, line count, visible line count (excluding HTML comments).
Carry the scope forward — Step 2 routes on it, and a check applied at the wrong scope is a false
positive rather than extra coverage.

## Step 2: Run checks

Read [../reference/criteria.md](../reference/criteria.md), then execute every applicable check against
each discovered file. Apply by entity type:

- **C1-C9**: CLAUDE.md and CLAUDE.local.md, at either scope
- **C9 is project-scoped — skip it for CLAUDE.local.md AND for every `user`-scope file.** The criteria
  file says so directly: C9 applies to project CLAUDE.md only, and `~/.claude/CLAUDE.md` is "not
  repo-scoped". This is the reason Step 1 emits a scope tag. A user-scope `CLAUDE.md` carrying no build
  and test commands is correct, not a FAIL, and reporting one there would be a false positive
  manufactured by the wider discovery
- **R1-R4**: `.claude/rules/` files, at either scope. **Read the rule's `paths:` frontmatter before
  applying a check that assumes it is loaded.** An always-loaded user rule (no `paths:`) costs context
  in every session of every project, so the R-checks apply to it at least as strongly as to a project
  rule. A *path-scoped* user rule is absent until a matching file is read, so a repo-relative currency
  or redundancy finding against one is only valid where its `paths:` can match in **this** project —
  check that first rather than assuming co-residency
- **R1 pairs within a scope.** A user rule's duplication check runs against the *user* `CLAUDE.md`, a
  project rule's against the *project* one — see R1's "Which CLAUDE.md" note. Cross-scope overlap is
  Step 3's, not R1's, or one overlap gets reported twice
- **Scope `both`**: one physical file that both layers reach. Two dotfiles layouts produce it — a repo
  rooted at `~` (where `.claude/rules` *is* `~/.claude/rules`) and a repo rooted at `~/.claude` itself
  (where the depth-1 `CLAUDE.md` *is* `~/.claude/CLAUDE.md`). Discovery emits such a file once with
  this tag. Report it once, and never compare it against itself in Step 3
- **C7/R3 (currency)**: version pins and counts are checked against the repo's own pin files
  (`global.json`, `.nvmrc`, `.python-version`, `.mcp.json`, or ecosystem equivalents). File-path-existence
  currency is **agent judgment**: read each path reference in context — instructional files cite
  non-existent paths on purpose (examples, counter-examples, future-deferred refs, regex patterns),
  so a blind existence check false-flags heavily. Judgment is the correct tool for that half
- **M1-M4**: Auto-memory files (doc-derived health checks)
- **M2 (deterministic backing)**: run
  `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/memory-index-refs-check.sh"` for
  index↔topic-file integrity — forward (index links an absent file) AND reverse (topic file present
  but not indexed, the orphan direction). Fold WARN lines into the report; do NOT hand-derive what the
  script computes
- **RD1**: Always-loaded rules layer (reverse-drift orphan check; deterministic-WARN). Run
  `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/orphan-rule-check.sh"` and fold each WARN
  line into the report — do NOT re-derive by hand
- **REPO checks**: any additional criteria or documented exemptions the consuming repo's own
  `CLAUDE.md` / `.claude/rules/` declare for its instruction layer (see SKILL.md
  "Consumer-convention extension seam")

For each check:

1. Read the "How to check" instructions literally
2. Execute the check steps
3. Record the finding with severity (FAIL/WARN/INFO) or PASS
4. Include the specific evidence (line count, file path, contradicting text)

**Be mechanical on the deterministic spine (C1/M1/RD1, and M2's script-backed half)** — the
criteria file defines what passes and fails there, so same criteria = same results. M2's other
half stays judgment (the script checks existence, not content — see its criteria row). The
judgment-tier checks (C2-C9, R1-R4, M3-M4)
require reading and interpreting content; apply their fixed criteria consistently rather than
skipping the judgment.

## Step 3: Cross-file consistency check (C6)

After per-file checks, cross-reference:

1. Compare CLAUDE.md sections against `.claude/rules/` for contradictions
2. Compare CLAUDE.md against CLAUDE.local.md for redundancy
3. Check if any CLAUDE.md instruction is already enforced by rule, hook, or analyzer
4. Compare the **user**-scope surfaces against the project ones. Both load together in every session
   here, so a user instruction that contradicts a project one is a live conflict rather than a
   layering choice, and a user instruction the project already states is redundant context on every
   run. Report the contradiction against the pair, and say which scope each side came from — the
   resolution differs, since only one of the two is yours to edit on behalf of the repo.
   **Two exclusions.** A `both`-scoped file is one file, not a pair: never compare it with itself. And
   a path-scoped user rule only co-resides where its `paths:` can match here, so establish that before
   calling it a contradiction or a redundancy

## Step 4: Generate report

Use the output format from criteria.md. Save to `${CLAUDE_PLUGIN_DATA}/audit/last-audit.md`
(create the directory if absent — audit output stays contributor-local because it covers personal
auto-memory; see SKILL.md "Report mode"). Pre-rename state migration: if
`${CLAUDE_PLUGIN_DATA}/health/` exists and `${CLAUDE_PLUGIN_DATA}/audit/` does not, move the old
directory to the new name first (the skill was previously named `health` and wrote there) so
prior reports survive the upgrade.

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
