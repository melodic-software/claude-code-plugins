# Memory Health Criteria

Version: 1.3.0
Last updated: 2026-07-25
Source: Official Claude Code docs (code.claude.com/docs/en/memory, code.claude.com/docs/en/best-practices, code.claude.com/docs/en/sub-agents, code.claude.com/docs/en/skills)

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
| Reference material needed sometimes | Skills — the body loads on demand; a new skill's listing entry does not (priced below) |
| Learnings Claude discovered while working, not instructions you authored | Auto memory — Claude writes it; you do not hand-author entries, and asking Claude to remember something lands here rather than in CLAUDE.md. Available only while auto memory is enabled (gated below) |
| Deterministic enforcement | Hooks (guaranteed execution) |
| Compile-time/build-time rules | Analyzers, linters, architecture tests |
| Information that changes frequently | Neither — keep it out |
| Content split out of a long CLAUDE.md purely to shorten it | **Not `@path` imports** — imported files load at launch, so the split reorganizes and saves nothing |

Flag content in the wrong layer. WARN severity because moving content is a judgment call.

**Auto memory is a destination only while it is enabled — resolve that before routing to it.** It is
on by default, but `autoMemoryEnabled: false` in any settings scope, or
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, turns it off, and Claude then neither writes nor loads
auto-memory files (<https://code.claude.com/docs/en/memory>). Recommending that accumulated learnings
leave `CLAUDE.md` for auto memory in that state deletes them from every future session instead of
relocating them. Resolve the effective state first — the environment variable overrides the setting,
and the sibling `/claude-memory:stateless` `status` action already resolves both across scopes — and
when auto memory is off, either name a destination that does load or state that enabling auto memory
is a precondition of the move rather than proposing it unconditionally.

**Import inside a path-scoped rule — verified, not doc-stated.** A rule whose body is only
`@some/file.md` has its *imported* content inlined at session start while the rule's own body
correctly defers, so moving content into a path-scoped rule and pulling it in by import saves
nothing. Reproduced first-party on Claude Code 2.1.219 (2026-07-24); no official page states it.
**Provenance**: empirical extension, not doc-derived — the `update` action must not overwrite it
with doc-sourced text, and it needs re-verification on a current version rather than a doc re-fetch.

**Price the move with the recommendation.** Moving content out of an always-loaded surface trades
per-session cost for post-compaction absence, and the trade differs by destination: path-scoped rules
and nested CLAUDE.md are re-injected only when a matching file is read again, while root CLAUDE.md,
unscoped rules, and auto memory are re-injected from disk. Read the destination's row in
[official-guidance.md](official-guidance.md), "Compaction by steering method", before recommending a
move, and state the cost alongside it. A rule that must persist across compaction stays unscoped or
in the project-root CLAUDE.md — a recommendation that omits this proposes a silent behavior change in
long sessions.

A **new** skill carries a second cost the compaction table does not show: the body defers, but the
listing entry it adds — `name` plus the combined `description` and `when_to_use`, truncated at 1,536
characters — is always in context, so the saving is the body minus that entry rather than the whole
body. Moving content into a skill that **already exists** adds no listing entry and does not carry
this cost. The only field that keeps a description out of context is `disable-model-invocation: true`,
which also makes the skill user-invocable only; `user-invocable: false` does not, and `skillOverrides`
does not reach plugin skills at all. State the entry as a cost of the recommended move — whether the
target's listing budget is oversubscribed is a separate question this check does not answer.

**Why**: Official docs: "For domain knowledge or workflows that are only relevant sometimes, use
skills instead. Claude loads them on demand without bloating every conversation." And: "Unlike
CLAUDE.md instructions which are advisory, hooks are deterministic." On imports: "splitting into
`@path` imports helps organization but doesn't reduce context, since imported files load at launch"
(code.claude.com/docs/en/memory). The per-destination compaction behavior is quoted with its sources
in [official-guidance.md](official-guidance.md) rather than restated here. On the listing entry:
"skill descriptions are loaded into context so Claude knows what's available, but full skill content
only loads when invoked", the combined `description` and `when_to_use` text "is truncated at 1,536
characters in the skill listing to reduce context usage", and "Plugin skills are not affected by
`skillOverrides`" (code.claude.com/docs/en/skills).

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
