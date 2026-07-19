# Memory Health Criteria

Version: 1.2.0
Last updated: 2026-07-11
Source: Official Claude Code docs (code.claude.com/docs/en/memory, code.claude.com/docs/en/best-practices, code.claude.com/docs/en/sub-agents)

This file defines every check the audit runs. Each check has a severity, description, and instructions
for evaluation. The audit applies checks per-entity-type (CLAUDE.md, rules, memory).

To refresh this file against current official guidance, run the skill's `update` action.

---

## Checks for CLAUDE.md and CLAUDE.local.md

### C1: Line Budget [FAIL]

**What**: Count visible lines (excluding HTML comments). Compare to 200-line target per file.

**How to check**:

1. Read the file
2. Strip HTML comment blocks (`<!-- ... -->`)
3. Count remaining non-empty lines
4. FAIL if > 200 lines without documented justification
5. WARN if > 150 lines (approaching limit)
6. PASS if <= 150 lines

**Why**: Official docs: "Target under 200 lines per CLAUDE.md file. Longer files consume more context
and reduce adherence." Files over 200 lines cause Claude to ignore instructions.

**Allowances**: Complex monorepos using `.claude/rules/` extensively may justify overages, and a repo
may document a deliberate exemption in its own rules (see SKILL.md "Consumer-convention extension
seam"). Report overage and justification together.

### C2: Deletion Test [WARN per section]

**What**: For each top-level section (H1/H2), ask: "Would Claude make mistakes without this section?"

**How to check**:

1. Parse the file into sections by H1/H2 headers
2. For each section, evaluate:
   - Does this contain commands Claude can't guess? → KEEP
   - Does this contain gotchas or non-obvious patterns? → KEEP
   - Does this contain project-specific conventions? → KEEP
   - Could Claude figure this out by reading the code? → FLAG
   - Is this a standard convention any senior engineer knows? → FLAG
   - Is this detailed reference material better suited to a skill? → FLAG
3. WARN for each section that fails the deletion test
4. Include the reason ("could infer from code", "standard practice", "move to skill")

**Why**: Official docs: "For each line, ask: 'Would removing this cause Claude to make mistakes?' If
not, cut it. Bloated CLAUDE.md files cause Claude to ignore your actual instructions!"

### C3: Content Placement [WARN]

**What**: Is each piece of content in the right layer?

**How to check**: For each section, evaluate whether it belongs in:

| Content type | Correct placement |
|-------------|------------------|
| Always-on project conventions | CLAUDE.md |
| Machine-specific config/preferences | CLAUDE.local.md |
| Language/framework-specific rules | `.claude/rules/` (path-scoped when that fits) |
| Reference material needed sometimes | Skills (on-demand, not always-loaded) |
| Deterministic enforcement | Hooks (guaranteed execution) |
| Compile-time/build-time rules | Analyzers, linters, architecture tests |
| Information that changes frequently | Neither — keep it out |

Flag content in the wrong layer. WARN severity because moving content is a judgment call.

**Why**: Official docs: "For domain knowledge or workflows that are only relevant sometimes, use
skills instead. Claude loads them on demand without bloating every conversation." And: "Unlike
CLAUDE.md instructions which are advisory, hooks are deterministic."

### C4: Specificity [WARN]

**What**: Are instructions concrete enough to verify?

**How to check**:

1. Scan for vague instructions: "format code properly", "keep things organized", "follow best practices", "write clean code"
2. Scan for instructions without actionable verbs or concrete outcomes
3. WARN for each vague instruction
4. Include a suggested rewrite

**Why**: Official docs examples: "Use 2-space indentation" instead of "Format code properly". "Run
`npm test` before committing" instead of "Test your changes."

### C5: Non-obvious Only [WARN]

**What**: Does the file contain content Claude could infer from reading code?

**How to check**:

1. Flag file-by-file codebase descriptions (Claude can `ls` and read files)
2. Flag standard language conventions Claude already knows
3. Flag framework documentation that should be linked, not copied
4. WARN per instance

**Why**: Official include/exclude table: Exclude "Anything Claude can figure out by reading code",
"Standard language conventions Claude already knows", "Detailed API documentation (link to docs
instead)."

### C6: Consistency [FAIL]

**What**: Do any instructions contradict each other across CLAUDE.md, CLAUDE.local.md, and rules files?

**How to check**:

1. Identify instructions touching the same topic across files
2. Check for contradictions (e.g., "always use X" in one file, "never use X" in another)
3. Check for redundancy (same instruction in multiple files)
4. FAIL for contradictions (Claude picks one arbitrarily)
5. WARN for redundancy (wastes context budget)

**Why**: Official docs: "If two rules contradict each other, Claude may pick one arbitrarily."

### C7: Currency [FAIL]

**What**: Do referenced files, versions, and counts match reality?

**How to check**:

1. Extract all file path references (e.g., "`docs/foo.md`", "`.claude/rules/bar.md`")
2. Verify each referenced file exists — **reading each reference in context**: instructional files
   cite non-existent paths on purpose (examples, counter-examples, future-deferred refs, regex
   patterns), so a blind existence check false-flags heavily
3. Check version numbers against the repo's actual pin files (e.g. an SDK pin vs `global.json`, a Node
   pin vs `.nvmrc`)
4. Check counts (e.g., "13 MCP servers" vs actual `.mcp.json`)
5. FAIL for missing files or wrong versions
6. WARN for stale counts

**Why**: Stale references cause Claude to hallucinate or waste time looking for nonexistent files.

### C8: Enforcement Hierarchy [WARN]

**What**: Could any CLAUDE.md instruction be enforced by a tool higher in the enforcement hierarchy?

**How to check**:

1. For each rule/instruction, check if it could be:
   - A compiler setting (nullable, warnings-as-errors)
   - A static-analyzer or linter rule
   - An architecture test
   - A pre-commit/pre-push git hook
   - A CI gate
   - A Claude Code hook (deterministic)
2. WARN per instruction that could move up the hierarchy
3. Include which enforcement level it could move to

**Why**: Prefer deterministic enforcement over documentation — when a guideline can become a
compile-time or runtime check, that is the stronger default.

---

## Checks for .claude/rules/ files

### R1: Duplication with CLAUDE.md [WARN]

**What**: Does this rule duplicate content already in CLAUDE.md?

**How to check**: Compare rule content against CLAUDE.md sections. Flag significant overlap.

### R2: Path Scoping Fit [INFO]

**What**: Should this rule carry `paths:` frontmatter so it loads only when matching files are read?

**How to check**: If the rule applies only to specific file types or directories but has no `paths:`
frontmatter, note it as a path-scoping candidate — an always-loaded rule costs context every session.

### R3: Currency [FAIL]

**What**: Same as C7 — verify file references, versions, and facts within rules files.

### R4: Staleness [WARN]

**What**: Does this rule reference features, patterns, or tools that no longer exist in the codebase?

**How to check**: Cross-reference key claims against actual code, configs, and dependencies.

### RD1: Orphan always-loaded rule [WARN] — deterministic

**What**: An always-loaded `.claude/rules/*.md` file (no `paths:` frontmatter, so it costs context
EVERY session) that NO tracked file references. A new always-loaded rule nothing indexes is pure
per-session token tax until someone trips over it — or a candidate for path-scoping (`paths:`
frontmatter) / removal. The doc-derived checks (C7/R3/R4/M2) all run memory/rules → codebase; RD1
runs the reverse direction — codebase → layer.

**How to check**: run
`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/orphan-rule-check.sh"` (deterministic
set-difference: enumerate always-loaded rules, `git grep` each basename across tracked files excluding
the rule's own file; zero hits = orphan). Path-scoped rules are exempt — they load only on
matching-file Read, so being unreferenced costs nothing per session. WARN per orphan.

**Provenance**: repo-agnostic extension, not doc-derived — the `update` action must not overwrite it.

---

## Checks for auto-memory (MEMORY.md + topic files)

### M1: Index Size [FAIL]

**What**: Is MEMORY.md under 200 lines / 25KB?

**How to check**: Count lines and file size. Only the first 200 lines (or 25KB) load at session start
— anything beyond is silently dropped.

### M2: Stale Entries [WARN]

**What**: Do any memory entries reference files, features, or decisions that no longer exist?

**How to check**:

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/memory-index-refs-check.sh"` for the
   deterministic index↔topic-file integrity half (missing targets + orphan topic files)
2. For entries referencing specific files/features, verify they still exist (judgment half — the
   script checks existence, not content)
3. WARN for entries pointing to removed/renamed content

### M3: Duplicate Topics [WARN]

**What**: Are there multiple memory entries covering the same topic?

**How to check**: Compare entry titles and descriptions. Flag entries with >80% semantic overlap.

### M4: Type Correctness [INFO]

**What**: Are memory entries categorized correctly (user/feedback/project/reference)?

**How to check**: Read topic files, check `type:` frontmatter against content. INFO severity —
miscategorization is cosmetic but reduces findability.

---

## Audit output format

Present findings as a deterministic report:

```text
## Memory Health Report — {date}

### Summary
- Files audited: X
- FAIL: X findings
- WARN: X findings
- INFO: X findings
- Estimated context cost: X tokens (from /context)

### FAIL findings (must fix)
| # | Check | File | Finding |
|---|-------|------|---------|
| 1 | C1 | CLAUDE.md | 273 visible lines (200 target, 37% over) |
| 2 | C7 | CLAUDE.md | `docs/missing.md` referenced but doesn't exist |

### WARN findings (should evaluate)
| # | Check | File | Finding |
|---|-------|------|---------|

### INFO findings (informational)
| # | Check | File | Finding |
|---|-------|------|---------|
```

Save the report to `${CLAUDE_PLUGIN_DATA}/audit/last-audit.md` for the `report` action to
retrieve.
