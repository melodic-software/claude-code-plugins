# Memory Health Criteria

Version: 1.5.1
Last updated: 2026-08-04
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

**Diagnostic**: The symptom-first tell for this check: "If Claude keeps doing something you don't
want despite having a rule against it, the file is probably too long and the rule is getting lost"
(code.claude.com/docs/en/best-practices). When the audit was prompted by a rule being ignored, add a
C1 WARN citing this tell even when steps 4-6 pass. The branch is prompt-conditioned, so it belongs
to the judgment tier — label it "judgment candidate" in the report; steps 1-6 remain the
deterministic spine, unaffected.

**Allowances**: Complex monorepos using `.claude/rules/` extensively may justify overages, and a repo
may document a deliberate exemption in its own rules (see SKILL.md "Consumer-convention extension
seam"). Report overage and justification together.

### C2: Deletion Test [WARN per line]

**What**: For each line, ask: "Would removing this cause Claude to make mistakes?" If not, cut it.

**How to check**:

1. Strip HTML comment blocks (human-only reference, as in C1) and skip blank and purely structural
   lines (headers, separators, table/list scaffolding) — only substantive instruction lines enter
   the loop
2. For each remaining line, evaluate:
   - A command Claude can't guess? → KEEP
   - A gotcha or non-obvious pattern? → KEEP
   - A project-specific convention? → KEEP
   - Could Claude figure this out by reading the code? → FLAG
   - A standard convention any senior engineer knows? → FLAG
   - Detailed reference material better suited to a skill? → FLAG
3. WARN per flagged line, with the reason ("could infer from code", "standard practice", "move to
   skill"); group findings by H1/H2 section, and collapse a section whose every line flags into one
   section-level finding

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
on by default, but `autoMemoryEnabled` and `CLAUDE_CODE_DISABLE_AUTO_MEMORY` can turn it off, and
Claude then neither writes nor loads auto-memory files
(<https://code.claude.com/docs/en/memory>). Recommending that accumulated learnings leave `CLAUDE.md`
for auto memory in that state deletes them from every future session instead of relocating them.

Resolve the **effective** state with the algorithm the sibling `stateless` skill already owns —
[`skills/stateless/context/status.md`](../../stateless/context/status.md), "Resolve the effective
state" — rather than reading a single scope: the environment variable is authoritative wherever it is
set (`1` → off, `0` → on even against `autoMemoryEnabled: false`), and only when it is unset does
settings precedence (managed > local > project > user) pick the winning `autoMemoryEnabled`, default
`true`. A `false` in a lower-precedence scope therefore does not by itself disable the destination.
When the resolved state is off, either name a destination that does load or state that enabling auto
memory is a precondition of the move, rather than proposing it unconditionally.

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

### C9: Build and Test Commands Present [FAIL]

**What**: Does a project CLAUDE.md state the repo's exact build and test commands, and are the
commands it states correct?

The only CLAUDE.md check that looks for missing or wrong content rather than surplus — C4 asks
whether an instruction that exists is concrete, C5 whether it should have been cut. Applies to
project CLAUDE.md only; skip for CLAUDE.local.md and for personal (`~/.claude/CLAUDE.md`) files,
which are not repo-scoped.

**How to check**:

0. First ask whether the commands are stated on another loaded surface — a nested CLAUDE.md, a
   path-scoped rule, or auto memory. If they are, this is a C3 placement question, not a C9
   finding for ABSENCE: do not WARN that CLAUDE.md omits them. The carve-out suppresses only the
   absence branch — any command CLAUDE.md itself still states goes through steps 2-3 regardless,
   because a stale stated command misleads whether or not a correct one exists elsewhere
1. Look for the repo's build and test invocations stated as runnable commands
2. Verify each stated command against the repo's own manifest or task runner (`package.json`
   scripts, `Makefile`, `*.csproj`, `pyproject.toml`, or ecosystem equivalent)
3. FAIL for a stated command that does not exist there — worse than an absent one: Claude runs it
   and the check fails for the wrong reason
4. WARN if either command is absent, or if present only as prose naming the tool without the
   invocation ("we use pytest" is not a command)
5. Do not flag a repo that has no build or test step; flag only a missing statement of one that exists

**Boundary with C7.** C7 owns *references* — file paths, version pins, counts. C9 owns *commands*.
A wrong build command is not a C7 finding today, because a command is none of the three things C7
checks. Report a wrong command under C9 only, and do not double-report it.

**Why**: Official docs list "build and test commands" first among what project memory is for
(code.claude.com/docs/en/memory), and `/init` populates them by analyzing the codebase — so without
the statement, they are inferred every session rather than read. This check fires on a CLAUDE.md
that exists but omits them. Absent commands make every verification loop start by guessing how to
run the check.

**Counter-evidence, and why step 0 exists**: the same page's CLAUDE.md-vs-auto-memory table puts
"Build commands" in the *auto memory* column's "Use for" cell, against CLAUDE.md's "Coding
standards, workflows, project architecture". The page states both, so the honest reading is that
the commands must be *reachable*, not that they must sit in CLAUDE.md specifically. Step 0 is what
keeps this check from flagging a repo that followed the other half of the same page.

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

**How to check**: Count lines and file size on the content that loads — strip YAML frontmatter and
block-level HTML comments first, since they are removed before the index is loaded and don't count
toward the limits. The SKILL.md pre-computed context already reports both post-strip figures
(`memory-dir-stats.sh --memory-lines` / `--memory-bytes`); use them rather than re-measuring the raw
file. Only the first 200 loaded lines (or 25KB) load at session start — anything beyond is silently
dropped.

Four readings the strip applies, so a hand count matches the reported figures:

1. A block counts only once it closes, and a leading `---` opens frontmatter only for as long as
   what follows is shaped like frontmatter. An opening `---` or `<!--` with no closing delimiter is
   ordinary content and is counted. So is a leading `---` whose block reaches a line that is
   neither blank, a comment, nor a `key:` mapping entry, or that runs past 20 lines — markdown
   carries thematic breaks freely, so the next `---` in a file is usually another break rather
   than a frontmatter close, and without both bounds the entire span between the two would be
   stripped. A leading thematic break, or frontmatter clipped mid-file, must not blank the count.
2. A block-level comment occupies whole lines. Text sharing a line with the comment's open or
   close loads, and is counted — including text between two comments on one line, since each
   comment ends at the first `-->` after its own opener.
3. Comments inside fenced code blocks are preserved: a comment inside a fence is code, not
   block-level markdown.
4. Byte counts measure LF-normalized content, so a CRLF index reports about one byte per line
   under its on-disk size — well under 1% of the 25KB cap.

**Provenance**: the strip rule itself is doc-derived (code.claude.com/docs/en/memory, "How it
works"). The four readings are not. The doc states the fenced-code carve-out for CLAUDE.md only and
is silent on it for MEMORY.md, and says nothing about unterminated blocks, unbounded blocks,
partial lines, or line endings. They are this plugin's reading, chosen so that no input silently
under-reports and leaves this `[FAIL]` gate unable to fire. Where a reading has to guess, it guesses
toward counting: an over-count can only make the gate fire early on a file near its limit, while an
under-count stops it firing at all. The `update` action must not overwrite them.

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
